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

  /* No interrupt may be observed before the scheduler owns the context. */
  csrci mstatus, 8
  csrw mie, zero
  csrw mscratch, zero

  la t0, __bss_start
  la t1, __bss_end
.Lclear_bss:
  bgeu t0, t1, .Lbss_done
  sw zero, 0(t0)
  addi t0, t0, 4
  j .Lclear_bss
.Lbss_done:

  la t0, freertos_risc_v_trap_handler
  csrw mtvec, t0

  call main
  li a0, 0x11
  tail freertos_platform_fail
  .size _start, .-_start
