# YHC-SysY 语言规范（MVP+）

本文档定义当前 YHC 编译器支持的 SysY 风格子集语法与运行语义。

## 1. 程序结构

当前仅支持单文件、单入口函数：

```c
int main() {
  // statements
}
```

不支持 `#include`、宏、多函数定义。

## 2. 词法规则

- 标识符：`[A-Za-z_][A-Za-z0-9_]*`
- 整数字面量：十进制有符号 32 位整数写法中的非负文本形式（如 `0`, `1`, `42`）
- 字符串字面量：双引号包围，支持 `\n`, `\t`, `\r`, `\\`, `\"`
- 注释：
  - `// ...`
  - `# ...`

## 3. 表达式（按优先级从低到高）

```ebnf
expr            = logical_or ;
logical_or      = logical_and , { "||" , logical_and } ;
logical_and     = bitwise_or , { "&&" , bitwise_or } ;
bitwise_or      = bitwise_xor , { "|" , bitwise_xor } ;
bitwise_xor     = bitwise_and , { "^" , bitwise_and } ;
bitwise_and     = equality , { "&" , equality } ;
equality        = relational , { ("==" | "!=") , relational } ;
relational      = shift , { ("<" | "<=" | ">" | ">=") , shift } ;
shift           = additive , { ("<<" | ">>") , additive } ;
additive        = multiplicative , { ("+" | "-") , multiplicative } ;
multiplicative  = unary , { ("*" | "/" | "%") , unary } ;
unary           = ("+" | "-" | "!" | "~") , unary | primary ;
primary         = integer | identifier | identifier "[" expr "]" | "(" expr ")" ;
```

已支持：

- 算术：`+ - * / %`、括号优先级、一元负号
- 逻辑：`&& || !`
- 比较：`== != < <= > >=`
- 位运算：`& | ^ ~ << >>`

## 4. 语句

### 4.1 变量与数组

```c
int x;
int x = expr;
int arr[16];
```

- 标量默认初始化为 `0`
- 静态栈数组（`int arr[N]`）默认逐元素清零
- 当前不支持数组初始化列表

### 4.2 赋值与自增自减

```c
x = expr;
x += expr;
x -= expr;
x *= expr;
x /= expr;
x %= expr;
x++;
x--;
arr[i] = expr;
arr[i] += expr;
arr[i]++;
```

### 4.3 控制流

```c
if (cond) { ... }
if (cond) { ... } else { ... }
if (cond1) { ... } else if (cond2) { ... } else { ... }
while (cond) { ... }
return expr;
```

## 5. 内置函数

保留并兼容以下内置函数：

```c
print_int(expr);
print_str("text");
pause(expr);
```

- `print_int(expr)`：输出十进制整数并附加换行
- `print_str("...")`：按字节写字符串
- `pause(expr)`：映射至 `SYS_pause`
- `return expr`：映射至 `SYS_exit`

## 6. 运行时语义

- 所有变量为 32 位整型
- 存储位置位于 `main` 的栈帧
- 数组按 `int32` 连续布局
- 逻辑表达式结果归一化为 `0` 或 `1`
- 若源码无显式 `return`，编译器自动追加 `return 0`

## 7. 示例

```c
int main() {
  int i = 0;
  int sum = 0;
  int arr[4];
  while (i < 4) {
    arr[i] = i * 2 + 1;
    sum += arr[i];
    i++;
  }
  if ((sum > 0) && !(sum == 7)) {
    print_int(sum);
  } else {
    print_str("fallback\n");
  }
  return 0;
}
```
