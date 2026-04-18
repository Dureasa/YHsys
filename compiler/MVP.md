# YHC Compiler（工业化重构版）

当前目录提供完整链路：

source (`.c`) -> 词法/语法/语义 -> IR (`.ir.json`) -> RV32 assembly (`.s`) -> ELF -> YHsys fs image

## 编译器架构

```
compiler/
  frontend/
    lexer/      # 词法分析
    parser/     # 语法分析（优先级表达式）
    semantic/   # 语义分析（符号表/数组约束）
    ast/        # AST 定义
  ir/           # 中间表示与 lowering
  backend/
    riscv/      # RV32 代码生成
  utils/        # 错误处理、公共工具函数
  yhc_compile.py
  mvp/          # 向后兼容包装层
```

完整语法见：`compiler/LANGUAGE.md`

## Build + Integrate

From repository root:

```bash
bash compiler/scripts/build_yh_program.sh compiler/examples/hello.c hello
bash compiler/scripts/build_yh_program.sh compiler/examples/branch_var.c branch
bash compiler/scripts/build_yh_program.sh compiler/examples/sysy_ops.c sysy_ops
```

Outputs:

- IR: `compiler/build/yhc_<name>.ir.json`
- ASM: `compiler/build/yhc_<name>.s`
- OBJ: `compiler/build/yhc_<name>.o`
- ELF: `compiler/build/yhc_<name>.elf`
- 注入后用户程序：`os/out/bin/user/_yhc_<name>`
- 重打包镜像：`os/out/img/fs-system.img`

## Inject Existing Binary To FS Image

```bash
bash compiler/scripts/inject_user_binary.sh <path/to/program.elf> <cmd_name>
```

After running this script, booting `make qemu` and `ls` in shell will show `<cmd_name>`.

## Run QEMU Directly

```bash
bash compiler/scripts/run_make_qemu.sh
```

This script directly executes `make qemu` under `os/`.

## Run In YHsys

```bash
python3 compiler/scripts/run_yh_program.py --program yhc_hello --os-dir os
python3 compiler/scripts/run_yh_program.py --program yhc_branch --os-dir os
python3 compiler/scripts/run_yh_program.py --program yhc_sysy_ops --os-dir os
```

Or boot manually:

```bash
cd os
make qemu
# in shell:
yhc_hello
```

## Clean Generated Compiler Outputs

```bash
bash compiler/scripts/clean_mvp.sh
```

This removes generated compiler outputs and `_yhc_*` binaries from `os/out/bin/user`, then repacks fs image.
