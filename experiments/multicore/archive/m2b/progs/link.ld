/* MC-M2b dual-hart bare-metal layout. No .bss is relied on (nothing clears it: hart 1 may start writing
   shared words before hart 0 could zero anything), so every shared variable lives in .data with an explicit
   initial value. Two 4 KiB stacks: hart h uses [_stack_base + 4K*h, _stack_base + 4K*(h+1)). */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.start) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data   : { *(.data .data.*) }
  . = ALIGN(64);
  .htif : { *(.htif) }
  . = ALIGN(64);
  .codebuf : { *(.codebuf) }
  . = ALIGN(4096);
  _stack_base = .;
  . = . + 0x2000;
  _stack_end = .;
}
