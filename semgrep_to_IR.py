#!/usr/bin/env python3
"""
Convert a subset of Semgrep source-level rules into paired LLVM IR fragments
that Alive2 (alive-tv) can consume.

Supported expression grammar (all assumed i32):
- Variables: `$X`, `$Y`, ...
- Integer literals: `0`, `1`, ...
- Binary ops (left-assoc, C-like precedence): `* /`, `+ -`, `<< >>`, `&`, `^`, `|`
- Parentheses for grouping

The script parses `pattern` and `fix` from a Semgrep YAML rule and emits two
functions: `@src` encodes the pattern expression, `@tgt` encodes the fix
expression.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import yaml


Token = Tuple[str, str]  # (kind, value)


@dataclass
class Expr:
    pass


@dataclass
class Var(Expr):
    name: str


@dataclass
class Const(Expr):
    value: int


@dataclass
class BinOp(Expr):
    op: str
    left: Expr
    right: Expr


def tokenize(expr: str) -> List[Token]:
    token_spec = re.compile(
        r"\s*(?:"  # leading space, non-capturing
        r"(?P<VAR>\$\w+)"  # $X
        r"|(?P<INT>-?\d+)"  # integer
        r"|(?P<OP><<|>>|\+|\-|\*|/|&|\||\^)"  # ops
        r"|(?P<LP>\()"
        r"|(?P<RP>\))"
        r")"
    )
    pos = 0
    out: List[Token] = []
    while pos < len(expr):
        m = token_spec.match(expr, pos)
        if not m:
            raise ValueError(f"cannot tokenize near: {expr[pos:pos+20]!r}")
        kind = m.lastgroup
        val = m.group(kind)
        out.append((kind, val))
        pos = m.end()
    return out


PRECEDENCE = {
    "*": 5,
    "/": 5,
    "+": 4,
    "-": 4,
    "<<": 3,
    ">>": 3,
    "&": 2,
    "^": 1,
    "|": 0,
}


def parse_expr(tokens: Sequence[Token]) -> Expr:
    idx = 0

    def parse_primary() -> Expr:
        nonlocal idx
        if idx >= len(tokens):
            raise ValueError("unexpected end of expression")
        kind, val = tokens[idx]
        if kind == "VAR":
            idx += 1
            return Var(name=val[1:])
        if kind == "INT":
            idx += 1
            return Const(value=int(val))
        if kind == "LP":
            idx += 1
            node = parse_bp(0)
            if idx >= len(tokens) or tokens[idx][0] != "RP":
                raise ValueError("missing closing parenthesis")
            idx += 1
            return node
        raise ValueError(f"unexpected token {val!r}")

    def parse_bp(min_prec: int) -> Expr:
        nonlocal idx
        left = parse_primary()
        while idx < len(tokens):
            kind, op = tokens[idx]
            if kind != "OP":
                break
            prec = PRECEDENCE.get(op)
            if prec is None or prec < min_prec:
                break
            idx += 1
            right = parse_bp(prec + 1)
            left = BinOp(op=op, left=left, right=right)
        return left

    expr = parse_bp(0)
    if idx != len(tokens):
        raise ValueError("extra tokens at end of expression")
    return expr


def collect_vars(expr: Expr, order: List[str]) -> None:
    if isinstance(expr, Var):
        if expr.name not in order:
            order.append(expr.name)
    elif isinstance(expr, BinOp):
        collect_vars(expr.left, order)
        collect_vars(expr.right, order)


def ast_to_ir(expr: Expr, next_id: List[int], op_flags: Dict[str, str]) -> Tuple[List[str], str]:
    """Return (instructions, value_name). next_id is a single-item counter."""

    if isinstance(expr, Var):
        return [], f"%{expr.name}"
    if isinstance(expr, Const):
        return [], str(expr.value)
    if isinstance(expr, BinOp):
        lhs_inst, lhs_val = ast_to_ir(expr.left, next_id, op_flags)
        rhs_inst, rhs_val = ast_to_ir(expr.right, next_id, op_flags)
        tmp = f"%{next_id[0]}"
        next_id[0] += 1
        op_map = {
            "+": "add",
            "-": "sub",
            "*": "mul",
            "/": "sdiv",
            "&": "and",
            "|": "or",
            "^": "xor",
            "<<": "shl",
            ">>": "ashr",
        }
        llvm_op = op_map.get(expr.op)
        if llvm_op is None:
            raise ValueError(f"unsupported operator: {expr.op}")
        flags = op_flags.get(llvm_op, "")
        flag_suffix = f" {flags}" if flags else ""
        inst = f"  {tmp} = {llvm_op}{flag_suffix} i32 {lhs_val}, {rhs_val}"
        return lhs_inst + rhs_inst + [inst], tmp
    raise TypeError(f"unknown Expr node: {expr}")


def extract_main_pattern(rule: Dict) -> str:
    for pat in rule.get("patterns", []):
        if "pattern" in pat:
            return pat["pattern"]
    raise ValueError(f"rule {rule.get('id', '<unknown>')} lacks a 'pattern'")


def extract_fix(rule: Dict) -> str:
    fix = rule.get("fix")
    if not fix:
        raise ValueError(f"rule {rule.get('id', '<unknown>')} lacks a 'fix'")
    return fix


def emit_ir(rule: Dict, out_dir: Path, pattern_override: str | None = None, id_suffix: str = "") -> Path:
    rule_id = rule.get("id", "rule")
    rule_id_full = f"{rule_id}{id_suffix}" if id_suffix else rule_id

    pattern = pattern_override if pattern_override is not None else extract_main_pattern(rule)
    fix = extract_fix(rule)

    metadata = rule.get("metadata", {}) or {}
    op_flags = {k: v for k, v in metadata.get("ir_flags", {}).items()}
    branch_const = metadata.get("branch_constant")

    if branch_const is not None:
        m = re.search(
            r"if\s*\(\s*([01])\s*\)\s*\{\s*return\s*(.+?);\s*\}\s*else\s*\{\s*return\s*(.+?);\s*\}",
            pattern,
            re.DOTALL,
        )
        if not m:
            raise ValueError(
                f"branch_constant rule {rule_id_full} has unsupported pattern: {pattern!r}"
            )
        cond_val = m.group(1) == "1"
        then_txt, else_txt = m.group(2).strip(), m.group(3).strip()

        then_ast = parse_expr(tokenize(then_txt))
        else_ast = parse_expr(tokenize(else_txt))

        var_order: List[str] = []
        collect_vars(then_ast, var_order)
        collect_vars(else_ast, var_order)
        params_sig = ", ".join(f"i32 %{v}" for v in var_order) if var_order else ""

        def build_block(ast: Expr, next_id: List[int]) -> Tuple[List[str], str]:
            inst, val = ast_to_ir(ast, next_id, op_flags)
            return inst, val

        next_id = [0]
        then_inst, then_val = build_block(then_ast, next_id)
        else_inst, else_val = build_block(else_ast, next_id)
        cond_literal = "true" if cond_val else "false"

        src_ir = "\n".join(
            [
                f"; Rule: {rule_id_full}",
                f"; Expression: {pattern}",
                f"define i32 @src({params_sig}) {{",
                "entry:",
                f"  br i1 {cond_literal}, label %then, label %else",
                "then:",
                *then_inst,
                f"  ret i32 {then_val}",
                "else:",
                *else_inst,
                f"  ret i32 {else_val}",
                "}",
                "",
            ]
        )

        chosen_ast = then_ast if cond_val else else_ast
        next_id = [0]
        tgt_inst, tgt_val = build_block(chosen_ast, next_id)
        tgt_body = "\n".join(tgt_inst)
        if tgt_body:
            tgt_body += "\n"
        tgt_ir = (
            f"; Rule: {rule_id_full}\n"
            f"; Expression: {fix}\n"
            f"define i32 @tgt({params_sig}) {{\n"
            f"entry:\n"
            f"{tgt_body}  ret i32 {tgt_val}\n"
            f"}}\n"
        )
    else:
        src_ast = parse_expr(tokenize(pattern))
        tgt_ast = parse_expr(tokenize(fix))

        var_order: List[str] = []
        collect_vars(src_ast, var_order)
        collect_vars(tgt_ast, var_order)
        params_sig = ", ".join(f"i32 %{v}" for v in var_order) if var_order else ""

        def build_func(name: str, ast: Expr) -> str:
            next_id = [0]
            inst, result = ast_to_ir(ast, next_id, op_flags)
            body = "\n".join(inst)
            if body:
                body += "\n"
            return (
                f"; Rule: {rule_id_full}\n"
                f"; Expression: {pattern if name=='src' else fix}\n"
                f"define i32 @{name}({params_sig}) {{\n"
                f"entry:\n"
                f"{body}  ret i32 {result}\n"
                f"}}\n"
            )

        src_ir = build_func("src", src_ast)
        tgt_ir = build_func("tgt", tgt_ast)

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{rule_id_full}.ll"

    with out_path.open("w", encoding="ascii") as f:
        f.write(src_ir)
        f.write("\n\n")
        f.write(tgt_ir)
        f.write("\n")

    return out_path


def convert_file(rule_file: Path, out_dir: Path) -> None:
    if not rule_file.is_file():
        raise SystemExit(f"rule file not found: {rule_file}")

    with rule_file.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    rules = data.get("rules", [])
    if not rules:
        raise SystemExit(f"no rules found in {rule_file}")

    generated = []
    for rule in rules:
        rule_id = rule.get("id", "rule")

        variants: List[Tuple[str, str]] = []
        for pat in rule.get("patterns", []):
            if "pattern-either" in pat:
                alts = pat["pattern-either"] or []
                for idx, alt in enumerate(alts, start=1):
                    if "pattern" in alt:
                        variants.append((alt["pattern"], f"_alt{idx}"))
            elif "pattern" in pat:
                variants.append((pat["pattern"], ""))

        if not variants:
            raise SystemExit(f"rule {rule_id} has no usable pattern")

        for pattern_txt, suffix in variants:
            out_path = emit_ir(rule, out_dir, pattern_override=pattern_txt, id_suffix=suffix)
            generated.append(out_path)

    print("Generated LLVM IR:")
    for path in generated:
        print(f" - {path}")


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "rule_file",
        type=Path,
        help="Semgrep YAML rule file to translate",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("build/ir"),
        help="Output directory for generated LLVM IR pairs",
    )
    return parser.parse_args(list(argv))


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    convert_file(args.rule_file, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
