#include "baremetal.h"

#include <stdint.h>

static volatile uint32_t values[32] = {
  91u, 12u, 77u, 3u, 54u, 28u, 65u, 1u,
  88u, 34u, 19u, 72u, 6u, 43u, 97u, 25u,
  58u, 14u, 81u, 39u, 9u, 68u, 31u, 84u,
  17u, 49u, 5u, 93u, 22u, 61u, 37u, 75u
};

int main(void)
{
  for (uint32_t end = 32u; end > 1u; --end) {
    for (uint32_t i = 0u; i + 1u < end; ++i) {
      uint32_t left = values[i];
      uint32_t right = values[i + 1u];
      if (left > right) {
        values[i] = right;
        values[i + 1u] = left;
      }
    }
  }

  for (uint32_t i = 1u; i < 32u; ++i) {
    if (values[i - 1u] > values[i]) {
      bm_fail(1u);
    }
  }
  bm_pass();
}
