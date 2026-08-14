// SPDX-License-Identifier: MIT

  .section .text.init, "ax", @progbits
  .align 2
  .globl _start
  .type _start, @function
_start:
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop

  la sp, __stack_top

  // The memory image contains initialized data. Explicitly clear BSS so each
  // program has the standard freestanding C startup contract.
  la t0, __bss_start
  la t1, __bss_end
.Lclear_bss:
  bgeu t0, t1, .Lbss_done
  sw zero, 0(t0)
  addi t0, t0, 4
  j .Lclear_bss
.Lbss_done:

  la t0, trap_entry
  csrw mtvec, t0

  call main
  tail bm_exit
  .size _start, .-_start
