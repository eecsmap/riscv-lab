/* PIPE-P2a uncached-fetch bench: the program in RAM at 0x8000_0000, device-resident code at 0x4000_0000 (uncached) */
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
  . = ALIGN(8);
  _bss_start = .;
  .bss : { *(.bss .bss.*) *(COMMON) }
  . = ALIGN(8);
  _bss_end = .;
  . = ALIGN(16);
  . = . + 0x1000;
  _stack_top = .;
  .devtext 0x40000000 : { *(.devtext) }
}
