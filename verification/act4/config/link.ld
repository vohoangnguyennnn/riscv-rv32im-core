/* ACT4 DUT memory layout for the simulation-only 1 MiB TCM. */
OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

MEMORY
{
  /* Reserve the last word for the ACT4 completion mailbox. */
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x000ffffc
}

SECTIONS
{
  .text.init 0x00000000 :
  {
    KEEP(*(.text.init))
  } > ram

  .text.rvtest . :
  {
    *(.text.rvtest)
    *(.text.rvtest.*)
  } > ram

  . = ALIGN(0x4000);
  .data . :
  {
    *(.data)
    *(.data.*)
    *(.rodata)
    *(.rodata.*)
  } > ram

  . = ALIGN(0x1000);
  .text.rvmodel . :
  {
    *(.text.rvmodel)
    *(.text.rvmodel.*)
    *(.text)
    *(.text.*)
  } > ram

  .bss . (NOLOAD) :
  {
    *(.bss)
    *(.bss.*)
    *(COMMON)
  } > ram

  . = ALIGN(16);
  __act4_image_end = .;

  /DISCARD/ :
  {
    *(.comment)
    *(.note)
    *(.note.*)
    *(.riscv.attributes)
  }
}

ASSERT(rvtest_entry_point == 0x00000000,
       "ACT4 entry point must match the RTL reset vector")
ASSERT(__act4_image_end <= 0x000ffffc,
       "ACT4 image overlaps the completion mailbox")
