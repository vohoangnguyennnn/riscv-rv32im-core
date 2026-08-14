OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  /* Reserve the final TCM word for the test completion mailbox. */
  tcm (rwx) : ORIGIN = 0x00000000, LENGTH = 0x0000fffc
}

PHDRS
{
  text PT_LOAD FLAGS(5); /* read + execute */
  data PT_LOAD FLAGS(6); /* read + write */
}

SECTIONS
{
  .text :
  {
    KEEP(*(.text.init))
    *(.text .text.*)
  } > tcm :text

  .rodata :
  {
    *(.rodata .rodata.*)
  } > tcm :text

  .data : ALIGN(16)
  {
    *(.data .data.*)
    *(.sdata .sdata.*)
  } > tcm :data

  .bss (NOLOAD) : ALIGN(16)
  {
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
  } > tcm :data

  . = ALIGN(16);
  _end = .;

  /DISCARD/ :
  {
    *(.comment)
    *(.note .note.*)
    *(.riscv.attributes)
  }
}

PROVIDE(tohost = 0x0000fffc);
ASSERT(_start == 0x00000000, "ISA reset entry must be address zero")
ASSERT(_end <= 0x0000fffc, "ISA test image overlaps tohost")
