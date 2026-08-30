#include "baremetal.h"

#include <stdint.h>

int main(void)
{
  uint32_t a = 0x13579bdfu;
  uint32_t b = 0x2468ace0u;

  // Eight independent-ish integer operations amortize one loop branch.
  for (uint32_t i = 0; i < 512u; ++i) {
    a += 0x9e3779b9u;
    b ^= a << 3;
    a = (a >> 5) | (a << 27);
    b += i + 17u;
    a ^= b >> 7;
    b = (b << 11) | (b >> 21);
    a += b ^ 0xa5a5a5a5u;
    b ^= a + 0x3c6ef372u;
  }

  if ((a == 0u) && (b == 0u)) {
    bm_fail(1u);
  }
  bm_pass();
}
