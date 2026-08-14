// SPDX-License-Identifier: MIT

#ifndef RV32IM_CORE_RISCV_TEST_H
#define RV32IM_CORE_RISCV_TEST_H

// Minimal physical-memory environment for the upstream riscv-tests assembly
// programs. The core implements only M-mode, so the unprivileged instruction
// tests execute in M-mode and do not depend on a proxy kernel or an SBI.

#define RVTEST_RV32U                                                    \
  .macro init;                                                          \
  .endm

#define RVTEST_RV64U RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init,"ax",@progbits;                            \
        .option norvc;                                                  \
        .align 2;                                                       \
        .globl _start;                                                  \
_start:                                                                 \
        li TESTNUM, 0;                                                  \
        la t0, unexpected_trap;                                         \
        csrw mtvec, t0;                                                 \
        j test_entry;                                                   \
unexpected_trap:                                                        \
        li TESTNUM, 256;                                                \
        csrr t6, mcause;                                                \
        add TESTNUM, TESTNUM, t6;                                       \
        slli TESTNUM, TESTNUM, 1;                                       \
        ori TESTNUM, TESTNUM, 1;                                        \
1:      la t5, tohost;                                                  \
        sw TESTNUM, 0(t5);                                              \
        j 1b;                                                           \
test_entry:                                                             \
        init;

#define RVTEST_CODE_END                                                 \
        unimp

// riscv-tests places the failing subtest number in gp. Status 1 means pass;
// every failure is encoded as (test_number << 1) | 1.
#define RVTEST_PASS                                                     \
        li TESTNUM, 1;                                                  \
1:      la t5, tohost;                                                  \
        sw TESTNUM, 0(t5);                                              \
        j 1b

#define RVTEST_FAIL                                                     \
1:      beqz TESTNUM, 1b;                                               \
        slli TESTNUM, TESTNUM, 1;                                       \
        ori TESTNUM, TESTNUM, 1;                                        \
2:      la t5, tohost;                                                  \
        sw TESTNUM, 0(t5);                                              \
        j 2b

#define RVTEST_DATA_BEGIN                                               \
        .align 4;                                                       \
        .globl begin_signature;                                         \
begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 4;                                                       \
        .globl end_signature;                                           \
end_signature:

#endif
