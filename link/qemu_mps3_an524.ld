/* yasboot on QEMU mps3-an524.
 *
 * Code in the bram at 0x10000000 (QEMU's boot address on this machine, where
 * the YasOS kernel also lives today).  RAM in DDR above everything the
 * kernel's linker script uses (its kstack ends at 0x81100000), so the loader
 * never overlaps the kernel it will hand over to. */

MEMORY
{
  flash (rx) : ORIGIN = 0x10000000, LENGTH = 128K
  ram   (rw) : ORIGIN = 0x81100000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS
{
  .text :
  {
    KEEP(*(.vectors))
    *(.text*)
    *(.rodata*)
    . = ALIGN(4);
  } > flash

  .data :
  {
    yasboot_data_start = .;
    *(.data*)
    *(.got*)
    . = ALIGN(4);
    yasboot_data_end = .;
  } > ram AT > flash
  yasboot_data_load = LOADADDR(.data);

  .bss (NOLOAD) :
  {
    yasboot_bss_start = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    yasboot_bss_end = .;
  } > ram

  yasboot_stack_top = ORIGIN(ram) + LENGTH(ram);
}
