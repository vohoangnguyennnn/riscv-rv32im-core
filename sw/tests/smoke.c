// SPDX-License-Identifier: MIT

#include "baremetal.h"

static volatile uint32_t initialized_words[4] = {
  UINT32_C(7),
  UINT32_C(9),
  UINT32_C(0x11223344),
  UINT32_C(100)
};

static uint32_t zeroed_words[8];

__attribute__((noinline))
static uint32_t arithmetic_kernel(uint32_t lhs, uint32_t rhs)
{
  return (lhs * rhs) + lhs + rhs;
}

int main(void)
{
  volatile uint32_t divisor = initialized_words[0];
  volatile int32_t signed_lhs = -100;
  volatile int32_t signed_rhs = 7;
  const volatile uint8_t *bytes =
    (const volatile uint8_t *)&initialized_words[2];
  uint32_t misa;
  uintptr_t stack_pointer;

  __asm__ volatile ("mv %0, sp" : "=r" (stack_pointer));
  BM_CHECK((stack_pointer & UINT32_C(0xf)) == 0U, UINT32_C(1));

  for (size_t index = 0; index < 8U; index++) {
    BM_CHECK(zeroed_words[index] == 0U, UINT32_C(2));
  }

  BM_CHECK(arithmetic_kernel(initialized_words[0], initialized_words[1]) == 79U,
           UINT32_C(3));
  BM_CHECK((initialized_words[3] / divisor) == 14U, UINT32_C(4));
  BM_CHECK((initialized_words[3] % divisor) == 2U, UINT32_C(5));
  BM_CHECK((signed_lhs / signed_rhs) == -14, UINT32_C(6));
  BM_CHECK((signed_lhs % signed_rhs) == -2, UINT32_C(7));

  BM_CHECK(bytes[0] == UINT8_C(0x44), UINT32_C(8));
  BM_CHECK(bytes[1] == UINT8_C(0x33), UINT32_C(9));
  BM_CHECK(bytes[2] == UINT8_C(0x22), UINT32_C(10));
  BM_CHECK(bytes[3] == UINT8_C(0x11), UINT32_C(11));

  zeroed_words[3] = initialized_words[0] + initialized_words[1];
  BM_CHECK(zeroed_words[3] == 16U, UINT32_C(12));

  misa = bm_csr_read_misa();
  BM_CHECK((misa >> 30) == 1U, UINT32_C(13));
  BM_CHECK((misa & (UINT32_C(1) << 8)) != 0U, UINT32_C(14));
  BM_CHECK((misa & (UINT32_C(1) << 12)) != 0U, UINT32_C(15));
  BM_CHECK(bm_csr_read_mhartid() == 0U, UINT32_C(16));

  return 0;
}
