#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

//
// the riscv Platform Level Interrupt Controller (PLIC).
//

void
plicinit(void)
{
  // set desired IRQ priorities non-zero (otherwise disabled).
  *(uint32*)(PLIC + UART0_IRQ*4) = 1;
  *(uint32*)(PLIC + VIRTIO0_IRQ*4) = 1;
}

void
plicinithart(void)
{
  // set enable bits for hart0 S-mode
  // for the uart and virtio disk.
  *(uint32*)PLIC_SENABLE(0) = (1 << UART0_IRQ) | (1 << VIRTIO0_IRQ);

  // set hart0 S-mode priority threshold to 0.
  *(uint32*)PLIC_SPRIORITY(0) = 0;
}

// ask the PLIC what interrupt we should serve.
int
plic_claim(void)
{
  int irq = *(uint32*)PLIC_SCLAIM(0);
  return irq;
}

// tell the PLIC we've served this IRQ.
void
plic_complete(int irq)
{
  *(uint32*)PLIC_SCLAIM(0) = irq;
}
