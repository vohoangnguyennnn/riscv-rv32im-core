// SPDX-License-Identifier: MIT

#include "baremetal.h"

volatile uint32_t tohost
  __attribute__((section(".tohost"), used, aligned(4)));

void bm_pass(void)
{
  tohost = BM_PASS_STATUS;
  __asm__ volatile ("fence rw, rw" : : : "memory");
  for (;;) {
    __asm__ volatile ("nop");
  }
}

void bm_fail(uint32_t code)
{
  uint32_t status = (code << 1) | UINT32_C(1);

  if (status == BM_PASS_STATUS) {
    status = UINT32_C(3);
  }
  tohost = status;
  __asm__ volatile ("fence rw, rw" : : : "memory");
  for (;;) {
    __asm__ volatile ("nop");
  }
}

void bm_exit(int status)
{
  if (status == 0) {
    bm_pass();
  }
  bm_fail((uint32_t)status);
}

__attribute__((weak))
void bm_trap_handler(uint32_t cause, uint32_t epc, uint32_t tval)
{
  (void)epc;
  (void)tval;
  bm_fail(UINT32_C(0x100) | (cause & UINT32_C(0x1f)));
}

void *memcpy(void *destination, const void *source, size_t length)
{
  uint8_t *dst = (uint8_t *)destination;
  const uint8_t *src = (const uint8_t *)source;

  while (length != 0U) {
    *dst++ = *src++;
    length--;
  }
  return destination;
}

void *memset(void *destination, int value, size_t length)
{
  uint8_t *dst = (uint8_t *)destination;

  while (length != 0U) {
    *dst++ = (uint8_t)value;
    length--;
  }
  return destination;
}

int memcmp(const void *lhs, const void *rhs, size_t length)
{
  const uint8_t *left = (const uint8_t *)lhs;
  const uint8_t *right = (const uint8_t *)rhs;

  while (length != 0U) {
    if (*left != *right) {
      return (*left < *right) ? -1 : 1;
    }
    left++;
    right++;
    length--;
  }
  return 0;
}
