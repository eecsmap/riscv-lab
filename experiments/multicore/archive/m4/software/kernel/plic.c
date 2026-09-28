#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

//
// the riscv Platform Level Interrupt Controller (PLIC).
//

// MC-M3 platform contract (TEACHING_PLATFORM_NO_PLIC_DEVICES): this SoC wires NO device interrupt source to
// its PLIC -- the console is HTIF (polled from the timer tick) and the disk is testchipip's block device
// (polled, see blkdev.c) -- and the PLIC it has exposes one M-mode context per hart and no S-mode contexts.
// xv6's PLIC_SENABLE(hart)/PLIC_SPRIORITY(hart) are S-mode context addresses: on this PLIC hart 0's land on
// hart 1's M-mode context registers and hart 1's on nothing (measured in MC-M2b dual04). Writing them was
// harmless on one core and would be wrong on two, so on this platform the kernel does not touch the PLIC at
// all; devintr()'s external-interrupt branch can never be taken (no source exists). Nothing here claims a
// device interrupt is supported.
void
plicinit(void)
{
#ifndef TEACHING_PLATFORM_NO_PLIC_DEVICES
  // set desired IRQ priorities non-zero (otherwise disabled).
  *(uint32 *)(PLIC + UART0_IRQ * 4) = 1;
  *(uint32 *)(PLIC + VIRTIO0_IRQ * 4) = 1;
#endif
}

void
plicinithart(void)
{
#ifndef TEACHING_PLATFORM_NO_PLIC_DEVICES
  int hart = cpuid();

  // set enable bits for this hart's S-mode
  // for the uart and virtio disk.
  *(uint32 *)PLIC_SENABLE(hart) = (1 << UART0_IRQ) | (1 << VIRTIO0_IRQ);

  // set this hart's S-mode priority threshold to 0.
  *(uint32 *)PLIC_SPRIORITY(hart) = 0;
#endif
}

// ask the PLIC what interrupt we should serve.
int
plic_claim(void)
{
  int hart = cpuid();
  int irq = *(uint32 *)PLIC_SCLAIM(hart);
  return irq;
}

// tell the PLIC we've served this IRQ.
void
plic_complete(int irq)
{
  int hart = cpuid();
  *(uint32 *)PLIC_SCLAIM(hart) = irq;
}
