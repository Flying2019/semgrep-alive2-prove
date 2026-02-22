## 基于 Alive2 的源码级优化证明

主要流程：
1. 输入源码基于 Semgrep Registry 规则，针对 C/C++ 实现。
2. 将 Semgrep 规则（尝试）转化成 LLVM IR rule，要求支持变量名替换，支持分支与简单循环。
3. 调用 Alive2 检查 LLVM IR rule 的正确性。
4. 将通过证明的规则应用于新的源码。

相关文件：

- example/rules/：示例规则
- example/code/：示例源码
- semgrep_to_IR.py：尝试将 semgrep 转化成 LLVM IR 的脚本

## 使用方式

1. 安装依赖（包含 Semgrep）：

	```sh
	make setup
	```

2. 运行 Semgrep 获得源码级匹配结果（仅使用 Semgrep Registry 风格的规则，不含 LLVM IR 片段）：

	```sh
	make semgrep
	# 输出：build/reports/semgrep.json
	```

3. 将 Semgrep 规则尝试转化为 LLVM IR 规则对：

	```sh
	make ir
	# 输出：build/ir/*.ll
	```

4. 使用 Alive2 对生成的 LLVM IR 规则进行验证（需要已安装 `alive-tv`，否则自动跳过）：

	```sh
	make alive
	```

5. 将已证明的规则应用到新的源码（在 build/out 下生成改写后的文件，原文件保持不变）：

	```sh
	make apply
	# 改写结果：build/out/
	```

6. 一键跑通上述流程：

	```sh
	make all
	```