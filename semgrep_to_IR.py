#!/usr/bin/env python3
"""
Convert a small subset of Semgrep source-level rules into paired LLVM IR
fragments that Alive2 (alive-tv) can consume.

Supported shapes (minimal demo coverage):
- Addition with zero: patterns containing "$X + 0".

This is intentionally narrow: the goal is to demonstrate the pipeline end to
end. Extend `TRANSLATORS` with more pattern handlers as needed.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Callable, Dict, Iterable, Tuple

import yaml

PatternTranslator = Callable[[str, Dict], Tuple[str, str]]


def add_zero_translator(pattern: str, rule: Dict) -> Tuple[str, str]:
    """Generate IR for folding `x + 0` to `x` for 32-bit integers."""

    src = (
        "; Rule: {name}\n"
        "; Source pattern: {pattern}\n"
        "define i32 @src(i32 %x) {{\n"
        "entry:\n"
        "  %0 = add i32 %x, 0\n"
        "  ret i32 %0\n"
        "}}\n"
    ).format(name=rule.get("id", "unknown"), pattern=pattern)

    tgt = (
        "; Rule: {name}\n"
        "; Target after folding add-zero\n"
        "define i32 @tgt(i32 %x) {{\n"
        "entry:\n"
        "  ret i32 %x\n"
        "}}\n"
    ).format(name=rule.get("id", "unknown"))

    return src, tgt


TRANSLATORS: Iterable[Tuple[str, PatternTranslator]] = [
    ("$X + 0", add_zero_translator),
]


def choose_translator(pattern: str) -> PatternTranslator:
    for needle, translator in TRANSLATORS:
        if needle in pattern:
            return translator
    raise ValueError(f"no translator for pattern: {pattern}")


def extract_main_pattern(rule: Dict) -> str:
    for pat in rule.get("patterns", []):
        if "pattern" in pat:
            return pat["pattern"]
    raise ValueError(f"rule {rule.get('id', '<unknown>')} lacks a 'pattern'")


def emit_ir(rule: Dict, out_dir: Path) -> Path:
    pattern = extract_main_pattern(rule)
    translator = choose_translator(pattern)
    src_ir, tgt_ir = translator(pattern, rule)

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{rule.get('id', 'rule')}.ll"

    with out_path.open("w", encoding="ascii") as f:
        f.write(src_ir)
        f.write("\n\n")
        f.write(tgt_ir)
        f.write("\n")

    return out_path


def convert_rules(rule_dir: Path, out_dir: Path) -> None:
    rule_files = sorted(rule_dir.glob("*.yaml"))
    if not rule_files:
        raise SystemExit(f"no rule files found under {rule_dir}")

    generated = []
    for rule_file in rule_files:
        with rule_file.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        for rule in data.get("rules", []):
            out_path = emit_ir(rule, out_dir)
            generated.append(out_path)

    print("Generated LLVM IR:")
    for path in generated:
        print(f" - {path}")


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rules",
        type=Path,
        default=Path("example/rules"),
        help="Directory containing Semgrep YAML rules",
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
    convert_rules(args.rules, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
