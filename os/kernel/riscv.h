#ifndef __ASSEMBLER__

// which hart (core) is this?
static inline uint32
r_mhartid()
{
  uint32 x;
  asm volatile("csrr %0, mhartid" : "=r" (x) );
  return x;
}

// Machine Status Register, mstatus

#define MSTATUS_MPP_MASK (3U << 11) // previous mode.
#define MSTATUS_MPP_M (3U << 11)
#define MSTATUS_MPP_S (1U << 11)
#define MSTATUS_MPP_U (0U << 11)

static inline uint32
r_mstatus()
{
  uint32 x;
  asm volatile("csrr %0, mstatus" : "=r" (x) );
  return x;
}

static inline void
w_mstatus(uint32 x)
{
  asm volatile("csrw mstatus, %0" : : "r" (x));
}

// machine exception program counter, holds the
// instruction address to which a return from
// exception will go.
static inline void
w_mepc(uint32 x)
{
  asm volatile("csrw mepc, %0" : : "r" (x));
}

// Supervisor Status Register, sstatus

#define SSTATUS_SPP (1U << 8)  // Previous mode, 1=Supervisor, 0=User
#define SSTATUS_SPIE (1U << 5) // Supervisor Previous Interrupt Enable
#define SSTATUS_UPIE (1U << 4) // User Previous Interrupt Enable
#define SSTATUS_SIE (1U << 1)  // Supervisor Interrupt Enable
#define SSTATUS_UIE (1U << 0)  // User Interrupt Enable

static inline uint32
r_sstatus()
{
  uint32 x;
  asm volatile("csrr %0, sstatus" : "=r" (x) );
  return x;
}

static inline void
w_sstatus(uint32 x)
{
  asm volatile("csrw sstatus, %0" : : "r" (x));
}

// Supervisor Interrupt Pending
static inline uint32
r_sip()
{
  uint32 x;
  asm volatile("csrr %0, sip" : "=r" (x) );
  return x;
}

static inline void
w_sip(uint32 x)
{
  asm volatile("csrw sip, %0" : : "r" (x));
}

// Supervisor Interrupt Enable
#define SIE_SEIE (1U << 9) // external
#define SIE_STIE (1U << 5) // timer
static inline uint32
r_sie()
{
  uint32 x;
  asm volatile("csrr %0, sie" : "=r" (x) );
  return x;
}

static inline void
w_sie(uint32 x)
{
  asm volatile("csrw sie, %0" : : "r" (x));
}

// Machine-mode Interrupt Enable
#define MIE_STIE (1U << 5)  // supervisor timer
static inline uint32
r_mie()
{
  uint32 x;
  asm volatile("csrr %0, mie" : "=r" (x) );
  return x;
}

static inline void
w_mie(uint32 x)
{
  asm volatile("csrw mie, %0" : : "r" (x));
}

// supervisor exception program counter, holds the
// instruction address to which a return from
// exception will go.
static inline void
w_sepc(uint32 x)
{
  asm volatile("csrw sepc, %0" : : "r" (x));
}

static inline uint32
r_sepc()
{
  uint32 x;
  asm volatile("csrr %0, sepc" : "=r" (x) );
  return x;
}

// Machine Exception Delegation
static inline uint32
r_medeleg()
{
  uint32 x;
  asm volatile("csrr %0, medeleg" : "=r" (x) );
  return x;
}

static inline void
w_medeleg(uint32 x)
{
  asm volatile("csrw medeleg, %0" : : "r" (x));
}

// Machine Interrupt Delegation
static inline uint32
r_mideleg()
{
  uint32 x;
  asm volatile("csrr %0, mideleg" : "=r" (x) );
  return x;
}

static inline void
w_mideleg(uint32 x)
{
  asm volatile("csrw mideleg, %0" : : "r" (x));
}

// Supervisor Trap-Vector Base Address
// low two bits are mode.
static inline void
w_stvec(uint32 x)
{
  asm volatile("csrw stvec, %0" : : "r" (x));
}

static inline uint32
r_stvec()
{
  uint32 x;
  asm volatile("csrr %0, stvec" : "=r" (x) );
  return x;
}

// Supervisor Timer Comparison Register
static inline uint32
r_stimecmp()
{
  uint32 x;
  // asm volatile("csrr %0, stimecmp" : "=r" (x) );
  asm volatile("csrr %0, 0x14d" : "=r" (x) );
  return x;
}

static inline void
w_stimecmp(uint32 x)
{
  // asm volatile("csrw stimecmp, %0" : : "r" (x));
  asm volatile("csrw 0x14d, %0" : : "r" (x));
}

// Machine Environment Configuration Register
static inline uint32
r_menvcfg()
{
  uint32 x;
  // asm volatile("csrr %0, menvcfg" : "=r" (x) );
  asm volatile("csrr %0, 0x30a" : "=r" (x) );
  return x;
}

static inline void
w_menvcfg(uint32 x)
{
  // asm volatile("csrw menvcfg, %0" : : "r" (x));
  asm volatile("csrw 0x30a, %0" : : "r" (x));
}

// Physical Memory Protection
static inline void
w_pmpcfg0(uint32 x)
{
  asm volatile("csrw pmpcfg0, %0" : : "r" (x));
}

static inline void
w_pmpaddr0(uint32 x)
{
  asm volatile("csrw pmpaddr0, %0" : : "r" (x));
}

// use riscv's sv32 page table scheme (RV32).
#define SATP_SV32 (1U << 31)

#define MAKE_SATP(pagetable) (SATP_SV32 | (((uint32)pagetable) >> 12))

// supervisor address translation and protection;
// holds the address of the page table.
static inline void
w_satp(uint32 x)
{
  asm volatile("csrw satp, %0" : : "r" (x));
}

static inline uint32
r_satp()
{
  uint32 x;
  asm volatile("csrr %0, satp" : "=r" (x) );
  return x;
}

// Supervisor Trap Cause
static inline uint32
r_scause()
{
  uint32 x;
  asm volatile("csrr %0, scause" : "=r" (x) );
  return x;
}

// Supervisor Trap Value
static inline uint32
r_stval()
{
  uint32 x;
  asm volatile("csrr %0, stval" : "=r" (x) );
  return x;
}

// Machine-mode Counter-Enable
static inline void
w_mcounteren(uint32 x)
{
  asm volatile("csrw mcounteren, %0" : : "r" (x));
}

static inline uint32
r_mcounteren()
{
  uint32 x;
  asm volatile("csrr %0, mcounteren" : "=r" (x) );
  return x;
}

// machine-mode cycle counter
static inline uint32
r_time()
{
  uint32 x;
  asm volatile("csrr %0, time" : "=r" (x) );
  return x;
}

// enable device interrupts
static inline void
intr_on()
{
  w_sstatus(r_sstatus() | SSTATUS_SIE);
}

// disable device interrupts
static inline void
intr_off()
{
  w_sstatus(r_sstatus() & ~SSTATUS_SIE);
}

// are device interrupts enabled?
static inline int
intr_get()
{
  uint32 x = r_sstatus();
  return (x & SSTATUS_SIE) != 0;
}

static inline uint32
r_sp()
{
  uint32 x;
  asm volatile("mv %0, sp" : "=r" (x) );
  return x;
}

// read and write tp, the thread pointer, which xv6 uses to hold
// this core's hartid (core number), the index into cpus[].
static inline uint32
r_tp()
{
  uint32 x;
  asm volatile("mv %0, tp" : "=r" (x) );
  return x;
}

static inline void
w_tp(uint32 x)
{
  asm volatile("mv tp, %0" : : "r" (x));
}

static inline uint32
r_ra()
{
  uint32 x;
  asm volatile("mv %0, ra" : "=r" (x) );
  return x;
}

// flush the TLB.
static inline void
sfence_vma()
{
  // the zero, zero means flush all TLB entries.
  asm volatile("sfence.vma zero, zero");
}

typedef uint32 pte_t;
typedef uint32 *pagetable_t; // 1024 PTEs

#endif // __ASSEMBLER__

#define PGSIZE 4096 // bytes per page
#define PGSHIFT 12  // bits of offset within a page

#define PGROUNDUP(sz)  (((sz)+PGSIZE-1) & ~(PGSIZE-1))
#define PGROUNDDOWN(a) (((a)) & ~(PGSIZE-1))

#define PTE_V (1U << 0) // valid
#define PTE_R (1U << 1)
#define PTE_W (1U << 2)
#define PTE_X (1U << 3)
#define PTE_U (1U << 4) // user can access

// shift a physical address to the right place for a PTE.
#define PA2PTE(pa) ((((uint32)pa) >> 12) << 10)

#define PTE2PA(pte) (((pte) >> 10) << 12)

#define PTE_FLAGS(pte) ((pte) & 0x3FF)

// extract the two 10-bit page table indices from a virtual address (Sv32).
#define PXMASK          0x3FF // 10 bits
#define PXSHIFT(level)  (PGSHIFT+(10*(level)))
#define PX(level, va) ((((uint32) (va)) >> PXSHIFT(level)) & PXMASK)

// one beyond the highest possible virtual address.
// Sv32: 2-level page table, 10+10+12 bits = 4GB address space
// MAXVA = 4GB = 0x100000000, but use 0xFFFFFFFF + 1 for clarity
#define MAXVA (0xFFFFFFFFU + 1U)
