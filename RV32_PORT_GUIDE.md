# YHsys RV32 架构移植指南

本文档详细描述将 YHsys 从 RV64（64位 RISC-V）移植到 RV32（32位 RISC-V）架构所需的所有修改。

## 1. 概述

当前系统基于 xv6 的 RV64 实现，使用 Sv39 页表方案。移植到 RV32 需要改用 Sv32 页表方案，并相应调整所有数据类型、寄存器操作和内存布局。

### 关键差异对比

| 特性 | RV64 (当前) | RV32 (目标) |
|------|-------------|-------------|
| 寄存器宽度 | 64-bit | 32-bit |
| 虚拟地址空间 | 39-bit (Sv39) | 32-bit (Sv32) |
| 页表层级 | 3级 | 2级 |
| 每页 PTE 数量 | 512 (8字节) | 1024 (4字节) |
| 最大虚拟地址 | 0x3FFFFFFFFF (256GB) | 0xFFFFFFFF (4GB) |
| satp 格式 | 模式(63-60) + ASID(59-44) + PPN(43-0) | 模式(31) + ASID(30-22) + PPN(21-0) |

---

## 2. 需要修改的文件清单

### 2.1 核心类型定义

#### `os/kernel/types.h`
**修改内容**: 将 `uint64` 和 `pde_t` 改为 32 位

```c
// 修改前
typedef unsigned long uint64;  // 64位
typedef uint64 pde_t;          // 页表项为64位

// 修改后
typedef unsigned long uint32;  // 已经是32位
typedef uint32 pde_t;          // 页表项改为32位
```

**注意**: 移除 `uint64` 类型或改为 `uint32`，同时移除 `uint64` 相关的 `typedef unsigned long uint64;` 定义。

---

#### `os/kernel/riscv.h`
**修改内容**: 大量修改，这是移植的核心文件

**2.1.1 寄存器读写函数**: 将 `uint64` 改为 `uint32`

```c
// 所有 CSR 读写函数
static inline uint32 r_mhartid() { ... }
static inline uint32 r_mstatus() { ... }
static inline void w_mstatus(uint32 x) { ... }
// ... 其他所有寄存器操作
```

**2.1.2 页表方案修改**: Sv39 → Sv32

```c
// 修改前 (Sv39)
#define SATP_SV39 (8L << 60)
#define MAKE_SATP(pagetable) (SATP_SV39 | (((uint64)pagetable) >> 12))

// 修改后 (Sv32)
#define SATP_SV32 (1L << 31)  // 模式位在 bit 31
#define MAKE_SATP(pagetable) (SATP_SV32 | (((uint32)pagetable) >> 12))
```

**2.1.3 虚拟地址常量**: MAXVA 重新计算

```c
// 修改前 (Sv39)
#define MAXVA (1L << (9 + 9 + 9 + 12 - 1))

// 修改后 (Sv32)
#define MAXVA (1L << (10 + 10 + 12))  // 4GB
```

**2.1.4 页表索引宏**: PX 宏调整

```c
// 修改前 (Sv39)
#define PXMASK          0x1FF // 9 bits
#define PXSHIFT(level)  (PGSHIFT+(9*(level)))

// 修改后 (Sv32)
#define PXMASK          0x3FF // 10 bits (2级页表)
#define PXSHIFT(level)  (PGSHIFT+(10*(level)))
```

**2.1.5 PTE 类型定义**

```c
// 修改前
typedef uint64 pte_t;
typedef uint64 *pagetable_t;

// 修改后
typedef uint32 pte_t;
typedef uint32 *pagetable_t;
```

**2.1.6 页表转换宏**: PA2PTE 和 PTE2PA

```c
// 修改前
#define PA2PTE(pa) ((((uint64)pa) >> 12) << 10)
#define PTE2PA(pte) (((pte) >> 10) << 12)
#define PTE_FLAGS(pte) ((pte) & 0x3FF)

// 修改后 (保持相同，因为 RV32 也是 PPN 在 bits 31-10)
#define PA2PTE(pa) ((((uint32)pa) >> 12) << 10)
#define PTE2PA(pte) (((pte) >> 10) << 12)
#define PTE_FLAGS(pte) ((pte) & 0x3FF)
```

**2.1.7 状态寄存器位域**: 调整位位置

```c
// mstatus 位 (保持不变，但使用32位操作)
#define MSTATUS_MPP_MASK (3L << 11)
#define MSTATUS_MPP_M (3L << 11)
#define MSTATUS_MPP_S (1L << 11)

// sstatus 位 (保持不变)
#define SSTATUS_SPP (1L << 8)
#define SSTATUS_SPIE (1L << 5)
#define SSTATUS_UPIE (1L << 4)
#define SSTATUS_SIE (1L << 1)
#define SSTATUS_UIE (1L << 0)
```

**2.1.8 中断使能位**: SIE 位域

```c
// 修改前
#define SIE_SEIE (1L << 9)
#define SIE_STIE (1L << 5)

// 修改后 (RV32 位位置相同)
#define SIE_SEIE (1L << 9)
#define SIE_STIE (1L << 5)
```

---

### 2.2 进程相关结构

#### `os/kernel/proc.h`
**修改内容**: `struct context` 和 `struct trapframe` 使用 32 位寄存器

**2.2.1 上下文结构**

```c
// 修改前
struct context {
  uint64 ra;
  uint64 sp;
  uint64 s0;
  // ... s1-s11
};

// 修改后
struct context {
  uint32 ra;
  uint32 sp;
  uint32 s0;
  // ... s1-s11
};
```

**2.2.2 Trapframe 结构**

```c
// 修改前
struct trapframe {
  uint64 kernel_satp;
  uint64 kernel_sp;
  // ... 所有字段为 uint64
};

// 修改后
struct trapframe {
  uint32 kernel_satp;
  uint32 kernel_sp;
  // ... 所有字段为 uint32
};
```

**2.2.3 进程结构中的指针类型**

```c
// 修改前
struct proc {
  uint64 kstack;
  uint64 sz;
  // ...
};

// 修改后
struct proc {
  uint32 kstack;
  uint32 sz;
  // ...
};
```

---

### 2.3 内存管理

#### `os/kernel/memlayout.h`
**修改内容**: 虚拟地址相关常量

**2.3.1 PLIC 地址计算 (hart 相关)**

```c
// 修改前 (64位地址计算)
#define PLIC_SENABLE(hart) (PLIC + 0x2080 + (hart)*0x100)

// 修改后 (32位地址计算，保持相同)
#define PLIC_SENABLE(hart) (PLIC + 0x2080 + (hart)*0x100)
```

**2.3.2 TRAMPOLINE 和 TRAPFRAME**

```c
// 修改前
#define TRAMPOLINE (MAXVA - PGSIZE)
#define TRAPFRAME (TRAMPOLINE - PGSIZE)

// 修改后 (MAXVA 已改变)
#define TRAMPOLINE (MAXVA - PGSIZE)  // 现在接近 4GB
#define TRAPFRAME (TRAMPOLINE - PGSIZE)
```

---

#### `os/kernel/vm.c`
**修改内容**: 页表层级从 3 级改为 2 级

**2.3.3 walk() 函数**

```c
// 修改前 (3级页表)
pte_t * walk(pagetable_t pagetable, uint64 va, int alloc) {
  if(va >= MAXVA)
    panic("walk");
  for(int level = 2; level > 0; level--) {  // level 2, 1
    pte_t *pte = &pagetable[PX(level, va)];
    // ...
  }
  return &pagetable[PX(0, va)];
}

// 修改后 (2级页表)
pte_t * walk(pagetable_t pagetable, uint32 va, int alloc) {
  if(va >= MAXVA)
    panic("walk");
  for(int level = 1; level > 0; level--) {  // level 1 only
    pte_t *pte = &pagetable[PX(level, va)];
    // ...
  }
  return &pagetable[PX(0, va)];
}
```

**2.3.4 freewalk() 函数**

```c
// 修改前
void freewalk(pagetable_t pagetable) {
  for(int i = 0; i < 512; i++) { ... }
}

// 修改后
void freewalk(pagetable_t pagetable) {
  for(int i = 0; i < 1024; i++) { ... }  // 1024 PTEs per page
}
```

**2.3.5 所有使用 uint64 的函数参数和返回值**

```c
// kvmmap, mappages, uvmalloc 等函数
void kvmmap(pagetable_t kpgtbl, uint32 va, uint32 pa, uint32 sz, int perm)
uint32 walkaddr(pagetable_t pagetable, uint32 va)
int mappages(pagetable_t pagetable, uint32 va, uint32 size, uint32 pa, int perm)
// ... 等等
```

---

### 2.4 陷阱和中断处理

#### `os/kernel/trap.c`
**修改内容**: 使用 32 位类型

```c
// 所有 uint64 改为 uint32
void trapinithart(void) {
  w_stvec((uint32)kernelvec);
}

uint32 usertrap(void) {
  // ...
  uint32 satp = MAKE_SATP(p->pagetable);
  return satp;
}

void prepare_return(void) {
  // ...
  p->trapframe->kernel_satp = r_satp();
  // ...
}
```

**2.4.1 scause 值的检查**

```c
// 修改前 (64位中断原因)
if(scause == 0x8000000000000009L) { ... }
if(scause == 0x8000000000000005L) { ... }

// 修改后 (32位中断原因)
if(scause == 0x80000009) { ... }  // 外部中断
if(scause == 0x80000005) { ... }  // 定时器中断
```

---

#### `os/kernel/trampoline.S`
**修改内容**: 64位指令改为32位指令

**2.4.2 寄存器保存/恢复**

```asm
# 修改前 (64位)
sd ra, 40(a0)    # 存储64位寄存器
ld ra, 40(a0)    # 加载64位寄存器

# 修改后 (32位)
sw ra, 40(a0)    # 存储32位寄存器
lw ra, 40(a0)    # 加载32位寄存器
```

**2.4.3 栈偏移调整**

由于寄存器从 64 位变为 32 位，trapframe 中每个寄存器的偏移需要重新计算：

```asm
# 修改前 (64位，每个寄存器8字节)
/*   0 */ uint64 kernel_satp;   // offset 0
/*   8 */ uint64 kernel_sp;     // offset 8
/*  16 */ uint64 kernel_trap;   // offset 16
# ... 依此类推，每个8字节

# 修改后 (32位，每个寄存器4字节)
/*   0 */ uint32 kernel_satp;   // offset 0
/*   4 */ uint32 kernel_sp;     // offset 4
/*   8 */ uint32 kernel_trap;   // offset 8
# ... 依此类推，每个4字节
```

---

#### `os/kernel/kernelvec.S`
**修改内容**: 同样改为 32 位指令

```asm
# 修改前
sd ra, 0(sp)
ld ra, 0(sp)

# 修改后
sw ra, 0(sp)
lw ra, 0(sp)
```

**栈帧大小调整**: 从 256 字节改为 128 字节（32个寄存器 * 4字节）

```asm
# 修改前
addi sp, sp, -256
...
addi sp, sp, 256

# 修改后
addi sp, sp, -128
...
addi sp, sp, 128
```

---

#### `os/kernel/swtch.S`
**修改内容**: 32 位上下文切换

```asm
# 修改前 (64位)
sd ra, 0(a0)
ld ra, 0(a1)

# 修改后 (32位)
sw ra, 0(a0)
lw ra, 0(a1)
```

**偏移调整**: struct context 中每个寄存器 4 字节而非 8 字节

```asm
# 修改前
sd ra, 0(a0)
sd sp, 8(a0)
sd s0, 16(a0)

# 修改后
sw ra, 0(a0)
sw sp, 4(a0)
sw s0, 8(a0)
```

---

### 2.5 启动代码

#### `os/kernel/entry.S`
**修改内容**: 保持兼容，但注意启动地址

RV32 和 RV64 在此级别代码几乎相同，因为使用的是基本 RV32I 指令。

---

#### `os/kernel/start.c`
**修改内容**: PMP 配置和定时器

**2.5.1 PMP 配置**

```c
// 修改前 (64位地址)
w_pmpaddr0(0x3fffffffffffffull);

// 修改后 (32位地址)
w_pmpaddr0(0xffffffff);
```

**2.5.2 menvcfg 寄存器 (RV32 可能没有)**

```c
// 修改前
w_menvcfg(r_menvcfg() | (1L << 63));

// 修改后 (RV32 可能没有 menvcfg，或需要不同的处理)
// 可能需要完全删除或使用不同的扩展使能方式
```

---

### 2.6 系统调用和进程管理

#### `os/kernel/syscall.c`, `sysproc.c`, `sysfile.c`
**修改内容**: 参数和返回值类型

```c
// 所有 uint64 改为 uint32
uint32 sys_sbrk(void) {
  // ...
}
```

---

#### `os/kernel/exec.c`
**修改内容**: ELF 加载相关

**2.6.1 ELF 类型**

```c
// 确保使用正确的 ELF32 格式
// 可能需要修改 elf.h 中的定义
```

**2.6.2 栈指针计算**

```c
// 修改前
sp -= (argc+1) * sizeof(uint64);

// 修改后
sp -= (argc+1) * sizeof(uint32);
```

---

#### `os/kernel/elf.h`
**修改内容**: 使用 32 位 ELF 定义

```c
// 可能需要修改或确认 ELF 头结构使用 32 位字段
struct elfhdr {
  uint magic;
  uchar elf[12];
  ushort type;
  ushort machine;
  uint version;
  uint entry;        // 32-bit entry point
  uint phoff;        // 32-bit offset
  uint shoff;
  uint flags;
  ushort ehsize;
  ushort phentsize;
  ushort phnum;
  ushort shentsize;
  ushort shnum;
  ushort shstrndx;
};
```

---

### 2.7 文件系统

#### `os/kernel/fs.c`, `file.c`, `bio.c`
**修改内容**: 主要是指针类型

大部分文件系统代码使用 `struct` 指针，不需要大的修改。但需要检查使用 `uint64` 的地方。

---

### 2.8 设备驱动

#### `os/kernel/virtio_disk.c`
**修改内容**: VirtIO 描述符使用 64 位地址

VirtIO 规范要求描述符中的地址是 64 位的，即使运行在 RV32 上。这部分需要特别处理：

```c
// VirtIO 描述符保持 64 位地址
struct virtq_desc {
  uint64 addr;   // 保持64位！
  uint32 len;
  uint16 flags;
  uint16 next;
} __attribute__((packed));
```

---

### 2.9 用户空间

#### `os/user/ulib.c`
**修改内容**: 类型定义

```c
// 修改前
char* sbrk(int n) { ... }

// 确保所有 size_t 和指针相关操作正确
```

---

#### `os/user/user.h`
**修改内容**: 系统调用声明

```c
// 保持兼容，主要是确保参数类型正确
```

---

### 2.10 链接器脚本

#### `os/kernel/kernel.ld`
**修改内容**: 通常不需要修改，但确认输出格式

```ld
OUTPUT_ARCH( "riscv" )  # 可能需要改为 riscv:rv32
```

---

#### `os/user/user.ld`
**修改内容**: 类似处理

---

### 2.11 Makefile

#### `os/Makefile`
**修改内容**: 编译器标志

**2.11.1 架构标志**

```makefile
# 修改前
CFLAGS += -march=rv64gc

# 修改后
CFLAGS += -march=rv32gc
CFLAGS += -mabi=ilp32  # 32位整数、长整型、指针
```

**2.11.2 工具链前缀**

```makefile
# 可能需要改为 32 位工具链
TOOLPREFIX = riscv32-unknown-elf-
# 或
TOOLPREFIX = riscv64-unknown-elf- (带 -march=rv32gc -mabi=ilp32)
```

**2.11.3 QEMU 配置**

```makefile
# 修改前
QEMU = qemu-system-riscv64

# 修改后
QEMU = qemu-system-riscv32
```

**2.11.4 汇编文件编译**

```makefile
# 修改前
$(CC) -march=rv64gc -g -c -o $@ $<

# 修改后
$(CC) -march=rv32gc -mabi=ilp32 -g -c -o $@ $<
```

---

## 3. 完整文件修改清单

### 必须修改的文件 (核心)

| 文件 | 修改类型 | 重要程度 |
|------|----------|----------|
| `os/kernel/types.h` | 类型定义 | 关键 |
| `os/kernel/riscv.h` | CSR、页表、常量 | 关键 |
| `os/kernel/proc.h` | 数据结构 | 关键 |
| `os/kernel/memlayout.h` | 内存布局 | 关键 |
| `os/kernel/vm.c` | 页表遍历 | 关键 |
| `os/kernel/trap.c` | 中断处理 | 关键 |
| `os/kernel/trampoline.S` | 汇编代码 | 关键 |
| `os/kernel/kernelvec.S` | 汇编代码 | 关键 |
| `os/kernel/swtch.S` | 汇编代码 | 关键 |
| `os/kernel/start.c` | 启动代码 | 高 |
| `os/kernel/entry.S` | 启动汇编 | 中 |
| `os/Makefile` | 构建系统 | 关键 |

### 需要修改的文件 (syscall/驱动)

| 文件 | 修改类型 |
|------|----------|
| `os/kernel/syscall.c` | 参数类型 |
| `os/kernel/sysproc.c` | 参数类型 |
| `os/kernel/sysfile.c` | 参数类型 |
| `os/kernel/exec.c` | ELF 处理 |
| `os/kernel/elf.h` | ELF 格式 |
| `os/kernel/virtio_disk.c` | 64位描述符保留 |
| `os/kernel/plic.c` | 中断处理 |
| `os/kernel/uart.c` | 寄存器访问 |

### 用户空间文件

| 文件 | 修改类型 |
|------|----------|
| `os/user/ulib.c` | 类型 |
| `os/user/user.h` | 声明 |
| `os/user/user.ld` | 链接脚本 |

---

## 4. 逐步移植步骤

### 步骤 1: 准备构建系统

1. 安装 RV32 工具链或配置现有工具链使用 RV32
2. 修改 `Makefile` 中的架构标志
3. 测试编译空程序确认工具链工作

### 步骤 2: 修改核心头文件

1. `types.h`: 移除 `uint64`，将 `pde_t` 改为 `uint32`
2. `riscv.h`:
   - 修改所有 CSR 函数使用 `uint32`
   - 更改 `SATP_SV39` 为 `SATP_SV32`
   - 修改 `MAKE_SATP` 宏
   - 修改 `MAXVA` 计算
   - 修改 `PXMASK` 和 `PXSHIFT`
   - 修改 `pte_t` 和 `pagetable_t` 定义
3. `proc.h`: 修改 `struct context` 和 `struct trapframe`
4. `memlayout.h`: 更新相关常量

### 步骤 3: 修改虚拟内存代码

1. `vm.c`:
   - 修改 walk() 为 2 级页表
   - 修改 freewalk() 为 1024 条目
   - 更新所有函数签名
2. `trap.c`:
   - 修改 scause 检查值
   - 更新类型为 `uint32`

### 步骤 4: 修改汇编代码

1. `trampoline.S`:
   - `sd` → `sw`
   - `ld` → `lw`
   - 更新所有偏移量（每个寄存器 4 字节）
2. `kernelvec.S`:
   - 同样修改
   - 栈帧大小改为 128
3. `swtch.S`:
   - 同样修改
   - 偏移改为 4 字节增量

### 步骤 5: 修改启动代码

1. `start.c`:
   - 修改 PMP 配置
   - 处理 menvcfg (可能删除)

### 步骤 6: 修改系统调用和进程管理

1. 更新 `syscall.c`, `sysproc.c`, `sysfile.c`
2. 更新 `exec.c` 和 `elf.h`
3. 更新 `proc.c` 中的进程创建代码

### 步骤 7: 更新用户空间

1. 修改 `user/` 目录下的 `Makefile`
2. 更新 `ulib.c` 和 `user.h`
3. 重新编译用户程序

### 步骤 8: 测试和调试

1. 编译内核
2. 在 QEMU 中运行
3. 逐步调试启动流程
4. 测试用户程序

---

## 5. 常见问题

### Q1: VirtIO 描述符的 64 位地址怎么办？
**A**: VirtIO 规范要求描述符中的地址是 64 位的。在 RV32 上，高 32 位应为 0。需要确保驱动程序正确处理这一点。

### Q2: 定时器中断如何工作？
**A**: RV32 使用 `time` CSR，但可能不是标准的。需要检查具体实现，或使用 `rdtime` 伪指令。

### Q3: 页表在 RV32 上如何布局？
**A**: Sv32 使用 2 级页表：
- VPN[1] (bits 31:22) → 第一级页表索引
- VPN[0] (bits 21:12) → 第二级页表索引
- 页内偏移 (bits 11:0)

### Q4: SATP 寄存器格式？
**A**: RV32 SATP:
- Mode (bit 31): 1 = Sv32
- ASID (bits 30:22): 地址空间 ID
- PPN (bits 21:0): 页表物理页号

### Q5: 中断原因编码变化？
**A**: 在 RV32 中，scause 是 32 位的。中断原因的最高位为 1，其余位表示原因：
- 外部中断: `0x80000009` (9 | 0x80000000)
- 定时器中断: `0x80000005` (5 | 0x80000000)

---

## 6. 参考资源

- [RISC-V Privileged ISA Specification](https://riscv.org/specifications/privileged-isa/)
- [xv6-riscv 源码](https://github.com/mit-pdos/xv6-riscv)
- [QEMU RISC-V 文档](https://www.qemu.org/docs/master/system/riscv/virt.html)

---

## 7. 修改检查清单

### 编译前检查
- [ ] `riscv.h` 中所有 `uint64` 改为 `uint32`
- [ ] `riscv.h` 中 `SATP_SV39` 改为 `SATP_SV32`
- [ ] `riscv.h` 中 `MAXVA` 重新计算
- [ ] `riscv.h` 中 `PXMASK` 改为 `0x3FF`
- [ ] `proc.h` 中 `struct context` 改为 32 位
- [ ] `proc.h` 中 `struct trapframe` 改为 32 位
- [ ] `vm.c` 中 walk() 改为 2 级
- [ ] 所有 `.S` 文件中 `sd/ld` 改为 `sw/lw`
- [ ] `Makefile` 中添加 `-mabi=ilp32`
- [ ] `Makefile` 中架构改为 `rv32gc`

### 运行时检查
- [ ] 内核成功启动到 `main()`
- [ ] 定时器中断正常工作
- [ ] 可以创建第一个用户进程
- [ ] 系统调用正常工作
- [ ] 用户 shell 可以运行
- [ ] 文件系统操作正常
