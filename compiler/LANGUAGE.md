# YHC-SysY 语言规范（MVP+）

本文档定义当前 YHC 编译器支持的 SysY 风格子集语法与运行语义。

## 1. 程序结构

支持单文件、多函数定义，入口函数仍为 `main`：

```c
int add(int a, int b) {
  return a + b;
}

int main() {
  // statements
}
```

函数返回值类型固定为 `int`，参数类型固定为 `int`。函数可以定义在 `main` 之前或之后，但函数调用必须出现在被调用函数定义之后；当前不支持前向声明、`void`、函数指针、`#include` 和宏。

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
primary         = integer | identifier | identifier "[" expr "]" | call | "(" expr ")" ;
call            = identifier , "(" , [ expr , { "," , expr } ] , ")" ;
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

### 5.1 用户函数调用

```c
int y = add(1, 2);
print_int(add(y, 3));
add(1, 2);
```

- 用户函数调用可作为表达式出现，也可作为独立语句出现
- 参数和返回值均为 32 位整型
- RV32 调用约定：`a0-a5` 传参，`a0` 返回结果

## 6. 运行时语义

- 所有变量为 32 位整型
- 每个函数有独立栈帧；参数作为该函数的局部变量
- 数组按 `int32` 连续布局
- 逻辑表达式结果归一化为 `0` 或 `1`
- 若源码无显式 `return`，编译器自动追加 `return 0`
- `main` 的 `return expr` 映射为 `SYS_exit(expr)`；普通用户函数恢复栈帧后通过 `ret` 返回调用者

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
