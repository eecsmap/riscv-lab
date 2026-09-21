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
}
