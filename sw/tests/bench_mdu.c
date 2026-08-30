#include "baremetal.h"

#include <stdint.h>

int main(void)
{
  volatile uint32_t seed = 0x12345678u;
  uint32_t acc = 7u;

  for (uint32_t i = 1u; i <= 64u; ++i) {
    uint32_t factor = seed | 1u;
    acc = acc * factor;
    acc ^= acc / i;
    acc += acc % (i + 1u);
    seed = seed * 1664525u + 1013904223u;
  }

  if (acc == 0x12345678u) {
    bm_fail(1u);
  }
  bm_pass();
}
