#ifndef RV32IM_SOC_H
#define RV32IM_SOC_H

#include <stdint.h>

#ifndef RV32_SOC_TIMER_BASE
#define RV32_SOC_TIMER_BASE UINT32_C(0x02000000)
#endif

#ifndef RV32_SOC_UART_BASE
#define RV32_SOC_UART_BASE UINT32_C(0x10000000)
#endif

#ifndef RV32_SOC_GPIO_BASE
#define RV32_SOC_GPIO_BASE UINT32_C(0x10010000)
#endif

#define RV32_SOC_MTIMECMP_LO (RV32_SOC_TIMER_BASE + UINT32_C(0x4000))
#define RV32_SOC_MTIMECMP_HI (RV32_SOC_TIMER_BASE + UINT32_C(0x4004))
#define RV32_SOC_MTIME_LO     (RV32_SOC_TIMER_BASE + UINT32_C(0xbff8))
#define RV32_SOC_MTIME_HI     (RV32_SOC_TIMER_BASE + UINT32_C(0xbffc))

#define RV32_SOC_UART_TXDATA  (RV32_SOC_UART_BASE + UINT32_C(0x00))
#define RV32_SOC_UART_RXDATA  (RV32_SOC_UART_BASE + UINT32_C(0x04))
#define RV32_SOC_UART_STATUS  (RV32_SOC_UART_BASE + UINT32_C(0x08))
#define RV32_SOC_UART_BAUDDIV (RV32_SOC_UART_BASE + UINT32_C(0x0c))

#define RV32_SOC_UART_STATUS_TX_READY   (UINT32_C(1) << 0)
#define RV32_SOC_UART_STATUS_TX_BUSY    (UINT32_C(1) << 1)
#define RV32_SOC_UART_STATUS_RX_VALID   (UINT32_C(1) << 2)
#define RV32_SOC_UART_STATUS_RX_OVERRUN (UINT32_C(1) << 3)
#define RV32_SOC_UART_STATUS_RX_FRAME   (UINT32_C(1) << 4)
#define RV32_SOC_UART_RX_EMPTY          (UINT32_C(1) << 31)

#define RV32_SOC_GPIO_INPUT  (RV32_SOC_GPIO_BASE + UINT32_C(0x00))
#define RV32_SOC_GPIO_OUTPUT (RV32_SOC_GPIO_BASE + UINT32_C(0x04))
#define RV32_SOC_GPIO_OE     (RV32_SOC_GPIO_BASE + UINT32_C(0x08))
#define RV32_SOC_GPIO_SET    (RV32_SOC_GPIO_BASE + UINT32_C(0x0c))
#define RV32_SOC_GPIO_CLEAR  (RV32_SOC_GPIO_BASE + UINT32_C(0x10))
#define RV32_SOC_GPIO_TOGGLE (RV32_SOC_GPIO_BASE + UINT32_C(0x14))

#define RV32_SOC_TOHOST_ADDR UINT32_C(0x0000fffc)
#define RV32_SOC_PASS_STATUS UINT32_C(1)

static inline uint32_t rv32_soc_mmio_read32(uint32_t address)
{
  return *(volatile const uint32_t *)(uintptr_t)address;
}

static inline void rv32_soc_mmio_write32(uint32_t address, uint32_t value)
{
  *(volatile uint32_t *)(uintptr_t)address = value;
}

uint64_t rv32_soc_mtime_read(void);
void rv32_soc_mtimecmp_write(uint64_t compare_value);

uint32_t rv32_soc_uart_status(void);
void rv32_soc_uart_clear_errors(void);
void rv32_soc_uart_putc(uint8_t byte);
int rv32_soc_uart_try_getc(void);

uint32_t rv32_soc_gpio_read(void);
void rv32_soc_gpio_write(uint32_t value);
void rv32_soc_gpio_set_output_enable(uint32_t mask);
void rv32_soc_gpio_set(uint32_t mask);
void rv32_soc_gpio_clear(uint32_t mask);
void rv32_soc_gpio_toggle(uint32_t mask);

void rv32_soc_finish(uint32_t status) __attribute__((noreturn));

#endif
