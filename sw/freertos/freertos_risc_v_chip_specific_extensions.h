#ifndef RV32IM_FREERTOS_RISCV_EXTENSIONS_H
#define RV32IM_FREERTOS_RISCV_EXTENSIONS_H

/* The SoC has standard memory-mapped mtime/mtimecmp and no extra registers. */
#define portasmHAS_SIFIVE_CLINT           0
#define portasmHAS_MTIME                  1
#define portasmADDITIONAL_CONTEXT_SIZE    0

.macro portasmSAVE_ADDITIONAL_REGISTERS
  /* No implementation-specific architectural state. */
.endm

.macro portasmRESTORE_ADDITIONAL_REGISTERS
  /* No implementation-specific architectural state. */
.endm

#endif
