/* The bootloader (uart_boot.c): the first 4 KiB of MCU-0's RAM, 0x8000_0000..0x8000_0FFF, stack included.
   Programs it loads start at 0x8000_1000 (app.ld), so loading never overwrites the bootloader. */
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
  . = . + 0x400;
  _stack_top = .;
  ASSERT(_stack_top <= 0x80001000, "uart_boot: code + data + 1 KiB stack must fit in the first 4 KiB")
}
