/* Linker script for riscyC1.
 *
 * The bootloader writes the loaded image into BOTH instruction and data memory
 * at the same addresses, so a single flat layout works: code is fetched from
 * imem, data is read from dmem, and both see identical contents.
 *
 * Memory: 1024 words = 4 KB, starting at 0x0.
 * Addresses at or above 0x1000 are memory-mapped I/O, not memory.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;

  .text.init : { *(.text.init) }

  .text : {
    *(.text)
    *(.text.*)
  }

  . = ALIGN(4);

  .data : {
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
    *(.rodata)
    *(.rodata.*)
  }

  .bss : {
    *(.bss)
    *(.sbss)
    *(COMMON)
  }

  _end = .;
}
