/* A program loaded by the bootloader (make boot-load): the same layout as software/probes/link.ld, but starting at
   0x8000_1000, above the bootloader's 4 KiB. The image must end below 0x8001_0000 (64 KiB of RAM). */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x80001000;
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
  ASSERT(_stack_top <= 0x80010000, "program + 4 KiB stack must end below 0x8001_0000")
}
