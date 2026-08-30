#include "rv32_soc.h"

uint64_t rv32_soc_mtime_read(void)
{
  uint32_t high_before;
  uint32_t low;
  uint32_t high_after;

  do {
    high_before = rv32_soc_mmio_read32(RV32_SOC_MTIME_HI);
    low = rv32_soc_mmio_read32(RV32_SOC_MTIME_LO);
    high_after = rv32_soc_mmio_read32(RV32_SOC_MTIME_HI);
  } while (high_before != high_after);

  return ((uint64_t)high_before << 32) | (uint64_t)low;
}

void rv32_soc_mtimecmp_write(uint64_t compare_value)
{
  /*
   * The privileged specification's RV32 sequence prevents either partially
   * updated half from transiently comparing below mtime.
   */
  rv32_soc_mmio_write32(RV32_SOC_MTIMECMP_LO, UINT32_MAX);
  rv32_soc_mmio_write32(RV32_SOC_MTIMECMP_HI,
                        (uint32_t)(compare_value >> 32));
  rv32_soc_mmio_write32(RV32_SOC_MTIMECMP_LO,
                        (uint32_t)compare_value);
}

uint32_t rv32_soc_uart_status(void)
{
  return rv32_soc_mmio_read32(RV32_SOC_UART_STATUS);
}

void rv32_soc_uart_clear_errors(void)
{
  rv32_soc_mmio_write32(RV32_SOC_UART_STATUS,
                        RV32_SOC_UART_STATUS_RX_OVERRUN |
                        RV32_SOC_UART_STATUS_RX_FRAME);
}

void rv32_soc_uart_putc(uint8_t byte)
{
  /* A TXDATA store is backpressured by the UART until it can be accepted. */
  rv32_soc_mmio_write32(RV32_SOC_UART_TXDATA, (uint32_t)byte);
}

int rv32_soc_uart_try_getc(void)
{
  uint32_t value;

  if ((rv32_soc_uart_status() & RV32_SOC_UART_STATUS_RX_VALID) == 0U) {
    return -1;
  }

  value = rv32_soc_mmio_read32(RV32_SOC_UART_RXDATA);
  if ((value & RV32_SOC_UART_RX_EMPTY) != 0U) {
    return -1;
  }
  return (int)(value & UINT32_C(0xff));
}

uint32_t rv32_soc_gpio_read(void)
{
  return rv32_soc_mmio_read32(RV32_SOC_GPIO_INPUT);
}

void rv32_soc_gpio_write(uint32_t value)
{
  rv32_soc_mmio_write32(RV32_SOC_GPIO_OUTPUT, value);
}

void rv32_soc_gpio_set_output_enable(uint32_t mask)
{
  rv32_soc_mmio_write32(RV32_SOC_GPIO_OE, mask);
}

void rv32_soc_gpio_set(uint32_t mask)
{
  rv32_soc_mmio_write32(RV32_SOC_GPIO_SET, mask);
}

void rv32_soc_gpio_clear(uint32_t mask)
{
  rv32_soc_mmio_write32(RV32_SOC_GPIO_CLEAR, mask);
}

void rv32_soc_gpio_toggle(uint32_t mask)
{
  rv32_soc_mmio_write32(RV32_SOC_GPIO_TOGGLE, mask);
}

void rv32_soc_finish(uint32_t status)
{
  rv32_soc_mmio_write32(RV32_SOC_TOHOST_ADDR, status);
  __asm__ volatile ("fence rw, rw" : : : "memory");
  for (;;) {
    __asm__ volatile ("nop");
  }
}
