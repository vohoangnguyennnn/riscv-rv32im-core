#include "baremetal.h"

#include <stdint.h>

static uint32_t fib(uint32_t n)
{
  if (n < 2u) {
    return n;
  }
  return fib(n - 1u) + fib(n - 2u);
}

int main(void)
{
  if (fib(16u) != 987u) {
    bm_fail(1u);
  }
  bm_pass();
}
