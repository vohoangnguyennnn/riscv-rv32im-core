#ifndef RV32IM_BAREMETAL_H
#define RV32IM_BAREMETAL_H

#include <stddef.h>
#include <stdint.h>

#define BM_TOHOST_ADDR UINT32_C(0x0000fffc)
#define BM_PASS_STATUS UINT32_C(1)

extern volatile uint32_t tohost;

void bm_exit(int status) __attribute__((noreturn));
void bm_pass(void) __attribute__((noreturn));
void bm_fail(uint32_t code) __attribute__((noreturn));

/*
 * Override this weak function in a test that expects synchronous traps.
 * The assembly entry preserves all integer registers. A returning handler
 * must update mepc when it wants execution to resume after the faulting
 * instruction.
 */
void bm_trap_handler(uint32_t cause, uint32_t epc, uint32_t tval);

static inline uint32_t bm_csr_read_misa(void)
{
  uint32_t value;
  __asm__ volatile ("csrr %0, misa" : "=r" (value));
  return value;
}

static inline uint32_t bm_csr_read_mhartid(void)
{
  uint32_t value;
  __asm__ volatile ("csrr %0, mhartid" : "=r" (value));
  return value;
}

static inline void bm_csr_write_mepc(uint32_t value)
{
  __asm__ volatile ("csrw mepc, %0" : : "r" (value) : "memory");
}

#define BM_CHECK(condition, code) \
  do {                            \
    if (!(condition)) {           \
      bm_fail((code));            \
    }                             \
  } while (0)

#endif
