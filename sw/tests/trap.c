// SPDX-License-Identifier: MIT

#include "baremetal.h"

enum {
  CAUSE_ILLEGAL_INSTRUCTION = 2,
  CAUSE_BREAKPOINT          = 3,
  CAUSE_ECALL_M             = 11
};

static volatile uint32_t expected_cause;
volatile uint32_t expected_epc;
static volatile uint32_t trap_count;

#define TRIGGER_TRAP(instruction)                 \
  __asm__ volatile (                              \
    ".option push\n"                             \
    ".option norelax\n"                          \
    "la t0, 1f\n"                                \
    "la t1, expected_epc\n"                      \
    "sw t0, 0(t1)\n"                             \
    "1: " instruction "\n"                      \
    ".option pop\n"                              \
    : : : "t0", "t1", "memory")

void bm_trap_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
  BM_CHECK(cause == expected_cause, UINT32_C(0x20) + trap_count);
  BM_CHECK(epc == expected_epc, UINT32_C(0x30) + trap_count);

  if (cause == CAUSE_ILLEGAL_INSTRUCTION) {
    BM_CHECK(tval == UINT32_C(0xffffffff), UINT32_C(0x40));
  } else if (cause == CAUSE_BREAKPOINT) {
    BM_CHECK(tval == epc, UINT32_C(0x41));
  } else {
    BM_CHECK(tval == 0U, UINT32_C(0x42));
  }

  trap_count++;
  bm_csr_write_mepc(epc + UINT32_C(4));
}

int main(void)
{
  BM_CHECK(trap_count == 0U, UINT32_C(0x50));

  expected_cause = CAUSE_ECALL_M;
  TRIGGER_TRAP("ecall");
  BM_CHECK(trap_count == 1U, UINT32_C(0x51));

  expected_cause = CAUSE_BREAKPOINT;
  TRIGGER_TRAP("ebreak");
  BM_CHECK(trap_count == 2U, UINT32_C(0x52));

  expected_cause = CAUSE_ILLEGAL_INSTRUCTION;
  TRIGGER_TRAP(".word 0xffffffff");
  BM_CHECK(trap_count == 3U, UINT32_C(0x53));

  return 0;
}
