#include <stddef.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "freertos_demo.h"
#include "rv32_soc.h"
#include "task.h"

volatile uint32_t freertos_tohost
  __attribute__((section(".tohost"), used, aligned(4)));

volatile freertos_demo_report_t freertos_demo_report
  __attribute__((section(".freertos_report"), used, aligned(4)));

volatile uint32_t freertos_tick_hook_count;
volatile uint32_t freertos_context_switch_count;

void freertos_platform_fail(uint32_t code) __attribute__((noreturn));

static uint32_t csr_read_mstatus(void)
{
  uint32_t value;
  __asm__ volatile ("csrr %0, mstatus" : "=r" (value));
  return value;
}

static uint32_t csr_read_mie(void)
{
  uint32_t value;
  __asm__ volatile ("csrr %0, mie" : "=r" (value));
  return value;
}

static uint32_t csr_read_mtval(void)
{
  uint32_t value;
  __asm__ volatile ("csrr %0, mtval" : "=r" (value));
  return value;
}

void freertos_platform_fail(uint32_t code)
{
  uint32_t status = (code << 1) | UINT32_C(3);

  freertos_demo_report.magic = FREERTOS_DEMO_REPORT_MAGIC;
  freertos_demo_report.kernel_version = FREERTOS_DEMO_KERNEL;
  freertos_demo_report.tick_hook_count = freertos_tick_hook_count;
  freertos_demo_report.context_switch_count = freertos_context_switch_count;
  freertos_demo_report.mstatus = csr_read_mstatus();
  freertos_demo_report.mie = csr_read_mie();
  freertos_demo_report.mtval = csr_read_mtval();
  freertos_demo_report.failure_code = code;

  if (status == RV32_SOC_PASS_STATUS) {
    status = UINT32_C(3);
  }
  rv32_soc_finish(status);
}

void freertos_assert_fail(const char *file, unsigned long line)
{
  (void)file;
  freertos_platform_fail(UINT32_C(0x1000) | ((uint32_t)line & UINT32_C(0x0fff)));
}

void freertos_trace_task_switched_in(void)
{
  freertos_context_switch_count++;
}

void vApplicationTickHook(void)
{
  freertos_tick_hook_count++;
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name)
{
  (void)task;
  (void)task_name;
  freertos_platform_fail(UINT32_C(0x2001));
}

void freertos_risc_v_application_exception_handler(uint32_t cause,
                                                    uint32_t epc)
{
  freertos_demo_report.mcause = cause;
  freertos_demo_report.mepc = epc;
  freertos_platform_fail(UINT32_C(0x3000) | (cause & UINT32_C(0x1f)));
}

void freertos_risc_v_application_interrupt_handler(uint32_t cause,
                                                    uint32_t epc)
{
  freertos_demo_report.mcause = cause;
  freertos_demo_report.mepc = epc;
  freertos_platform_fail(UINT32_C(0x3100) | (cause & UINT32_C(0x1f)));
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

size_t strlen(const char *text)
{
  size_t length = 0U;
  while (text[length] != '\0') {
    length++;
  }
  return length;
}
