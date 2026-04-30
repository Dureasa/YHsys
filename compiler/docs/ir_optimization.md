# IR Optimization Passes

本文档记录 YHC 编译器中新增的 IR 层 O1 优化，包括常量传播、代数化简、死分支删除，以及论文量化实验所需的开关、IR dump、统计文件和测试方法。

## 代码结构

编译器主入口：

- `compiler/yhc_compile.py`
- 主流程是 `tokenize -> Parser -> SemanticAnalyzer -> lower_program -> optimize_ir -> generate_asm`
- `optimize_ir` 位于 IR 生成之后、RISC-V 汇编生成之前

IR 数据结构：

- `compiler/ir/ir_types.py`
- `IRModule` 包含 `symbols`、`constants`、`instructions`
- `IRInstruction` 使用 `op + args` 描述线性 IR 指令

IR lowering：

- `compiler/ir/builder.py`
- `lower_program()` 将 AST 降到 JSON 风格的线性 IR

优化实现：

- `compiler/ir/optimizer.py`
- 对 `dict` 形式 IR 做局部优化，不改变前端和后端接口
- `compiler/ir/__init__.py` 导出 `optimize_ir` 和 `OptimizationStats`

构建脚本：

- `compiler/scripts/build_yh_program.sh`
- 通过环境变量 `YHC_OPT_LEVEL` 透传 `--no-opt` 或 `--O1`

测试脚本：

- `compiler/scripts/run_opt_tests.py`
- 覆盖 IR 检查、统计检查、`--no-opt` 与 `--O1` 运行输出一致性

## Pass 插入位置

优化 pass 插入在 `compiler/yhc_compile.py` 的 IR 生成和 codegen 之间：

```python
ir_before = lower_program(program, symbols)
if opt_enabled:
    ir_after, opt_stats = optimize_ir(ir_before)
else:
    ir_after = json.loads(json.dumps(ir_before))
```

随后 `generate_asm(ir_after, ...)` 使用优化后的 IR 生成汇编。

这样做的原因：

- 保持前端词法、语法、语义分析不变
- 保持后端 codegen 接口不变
- 优化只作用在现有 IR 层，改动范围小
- 便于保存优化前 IR 和优化后 IR，用于论文实验对比

## 优化内容

### 常量传播

实现位置：

- `compiler/ir/optimizer.py`
- `_simplify_expr()`
- `_optimize_once()`

实现范围：

- 在线性 IR 中维护局部常量环境 `env`
- 当变量被常量赋值后，后续使用处替换为整数常量
- 当变量重新赋值时，清除旧常量
- 支持 `assign`、`sys_write_expr`、`sys_pause_expr`、`sys_exit_expr` 中表达式的替换

示例：

```c
int a = 7;
int b = a;
print_int(b);
a = 9;
print_int(a);
```

优化后 `b = a` 和 `print_int(b)` 中的使用可以变成常量 `7`。

边界：

- 遇到 `label`、`goto`、`if_goto` 会清空常量环境
- 不做跨基本块激进传播
- 不引入 SSA 或全局数据流分析
- 数组写入按保守方式处理

### 代数化简

实现位置：

- `compiler/ir/optimizer.py`
- `_simplify_expr()`
- `_simplify_fixed_point()`

支持规则：

- `x + 0 -> x`
- `0 + x -> x`
- `x - 0 -> x`
- `x * 1 -> x`
- `1 * x -> x`
- `x * 0 -> 0`
- `0 * x -> 0`
- `x / 1 -> x`

同时保留并复用整数常量折叠，例如：

- `2 + 3 -> 5`
- `x = 3; y = x * 1 + 0 -> y = 3`

边界：

- 不做可能改变异常或未定义行为的激进规则
- 除法和取模遇到右操作数为 `0` 时不折叠
- 只处理现有 IR 表达式，不扩展语言特性

### 死分支删除

实现位置：

- `compiler/ir/optimizer.py`
- `_optimize_once()`
- `_remove_dead_branches()`
- `_cleanup_control_flow()`

支持范围：

- `if (1)` 删除不可达 else 分支
- `if (0)` 删除不可达 then 分支
- 条件经常量传播和代数化简后变成常量时，也删除不可达分支
- 删除不可达 IR 指令
- 删除冗余 `goto label` 后紧跟 `label` 的跳转
- 删除不再被引用的标签

示例：

```c
int x = 3;
int y = (x * 1) + 0;
if (y - 3) {
  print_int(0);
} else {
  print_int(y);
}
```

优化过程：

- `x` 传播为 `3`
- `y` 化简为 `3`
- `y - 3` 化简为 `0`
- 条件恒假，删除 then 分支
- 后续固定点迭代继续把 `print_int(y)` 优化为 `print_int(3)`

边界：

- 删除基于现有线性 IR 的可达性分析
- 不构建完整 CFG
- 不做循环不变式外提、公共子表达式删除、全局寄存器分配等优化

## O1 固定点迭代

`optimize_ir()` 会重复运行局部优化，直到 IR 不再变化：

```python
while True:
    next_module = _optimize_once(optimized)
    if next_module == optimized:
        break
    optimized = next_module
```

目的：

- 死分支删除后可能形成新的直线代码
- 新直线代码中可能继续触发常量传播和代数化简
- 保持实现简单，不引入复杂数据流分析

## 开启和关闭优化

直接调用编译器：

```sh
python3 compiler/yhc_compile.py \
  --input compiler/tests/opt_combo.c \
  --ir compiler/build/opt_combo.ir.json \
  --asm compiler/build/opt_combo.s \
  --stats-json compiler/build/opt_combo.optstats.json \
  --syscall-header os/kernel/syscall.h \
  --program-name opt_combo \
  --O1
```

关闭优化：

```sh
python3 compiler/yhc_compile.py \
  --input compiler/tests/opt_combo.c \
  --ir compiler/build/opt_combo.ir.json \
  --asm compiler/build/opt_combo.s \
  --stats-json compiler/build/opt_combo.optstats.json \
  --syscall-header os/kernel/syscall.h \
  --program-name opt_combo \
  --no-opt
```

通过构建脚本开启优化：

```sh
YHC_OPT_LEVEL=--O1 bash compiler/scripts/build_yh_program.sh compiler/tests/opt_combo.c cbo
```

通过构建脚本关闭优化：

```sh
YHC_OPT_LEVEL=--no-opt bash compiler/scripts/build_yh_program.sh compiler/tests/opt_combo.c cbn
```

`build_yh_program.sh` 默认使用 `--no-opt`，便于保留基线结果。

## IR Dump

直接调用 `yhc_compile.py` 时：

- `--ir` 输出最终 IR
- `--ir-before` 可指定优化前 IR
- `--ir-after` 可指定优化后 IR
- 如果不指定 `--ir-before` 和 `--ir-after`，会根据 `--ir` 自动生成默认路径

构建脚本生成的文件：

- `compiler/build/yhc_<name>.ir.json`
- `compiler/build/yhc_<name>.before.ir.json`
- `compiler/build/yhc_<name>.after.ir.json`

查看优化前后 IR：

```sh
sed -n '1,220p' compiler/build/yhc_cbo.before.ir.json
sed -n '1,220p' compiler/build/yhc_cbo.after.ir.json
```

## 统计数据

终端会输出：

```text
[yhc] ir stats: before=<N> after=<M> removed=<K>
```

JSON 统计文件格式：

```json
{
  "opt_level": "O1",
  "instructions_before": 11,
  "instructions_after": 4,
  "instructions_removed": 7
}
```

构建脚本生成的统计文件：

- `compiler/build/yhc_<name>.optstats.json`

读取统计文件：

```sh
cat compiler/build/yhc_cbo.optstats.json
```

这些字段可以直接用于论文表格：

- `instructions_before`
- `instructions_after`
- `instructions_removed`

## 测试样例

新增最小测试样例：

- `compiler/tests/opt_constprop.c`
- `compiler/tests/opt_algebraic.c`
- `compiler/tests/opt_dead_branch.c`
- `compiler/tests/opt_combo.c`

覆盖内容：

- `opt_constprop.c`：变量常量赋值后的局部常量传播
- `opt_algebraic.c`：`x+0`、`1*x`、`x*0` 等代数化简
- `opt_dead_branch.c`：条件经传播后变成常量的死分支删除
- `opt_combo.c`：常量传播、代数化简、死分支删除联合优化

运行完整优化测试：

```sh
PYTHONPYCACHEPREFIX=/tmp/pycache python3 compiler/scripts/run_opt_tests.py
```

测试脚本会执行：

- `--no-opt` 编译
- `--O1` 编译
- 检查 `--no-opt` 不改变 IR
- 检查 `--O1` 后 IR 符合预期
- 检查 JSON 统计字段正确
- 构建并在 YHsys/QEMU 中运行程序
- 验证 `--no-opt` 与 `--O1` 运行输出一致

已通过测试输出：

```text
[ok] opt_constprop
[ok] opt_algebraic
[ok] opt_dead_branch
[ok] opt_combo
all optimization tests passed
```

## 修改文件汇总

核心实现：

- `compiler/ir/optimizer.py`
- `compiler/ir/__init__.py`

驱动和实验输出：

- `compiler/yhc_compile.py`
- `compiler/scripts/build_yh_program.sh`

测试：

- `compiler/scripts/run_opt_tests.py`
- `compiler/tests/opt_constprop.c`
- `compiler/tests/opt_algebraic.c`
- `compiler/tests/opt_dead_branch.c`
- `compiler/tests/opt_combo.c`

文档：

- `compiler/docs/ir_optimization.md`
