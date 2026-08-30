#include <stdint.h>

#include "FreeRTOS.h"
#include "freertos_demo.h"
#include "rv32_soc.h"
#include "task.h"

#define BLINK_MASK UINT32_C(1)
#define BLINK_STACK_WORDS 160U
#define ECHO_STACK_WORDS  192U
#define CHECK_STACK_WORDS 192U

#ifndef FREERTOS_BLINK_PERIOD_MS
#define FREERTOS_BLINK_PERIOD_MS 2U
#endif

extern volatile freertos_demo_report_t freertos_demo_report;
extern volatile uint32_t freertos_tick_hook_count;
extern volatile uint32_t freertos_context_switch_count;
void freertos_platform_fail(uint32_t code) __attribute__((noreturn));

static StaticTask_t blink_task_tcb;
static StaticTask_t echo_task_tcb;
static StaticTask_t check_task_tcb;
static StackType_t blink_task_stack[BLINK_STACK_WORDS];
static StackType_t echo_task_stack[ECHO_STACK_WORDS];
static StackType_t check_task_stack[CHECK_STACK_WORDS];

static volatile uint32_t blink_count;
static volatile uint32_t echo_count;
static volatile uint32_t echoed_byte;

static void uart_write_text(const char *text)
{
  while (*text != '\0') {
    rv32_soc_uart_putc((uint8_t)*text);
    text++;
  }
}

static void blink_task(void *argument)
{
  (void)argument;

  for (;;) {
    rv32_soc_gpio_toggle(BLINK_MASK);
    blink_count++;
    vTaskDelay(pdMS_TO_TICKS(FREERTOS_BLINK_PERIOD_MS));
  }
}

static void echo_task(void *argument)
{
  int byte;

  (void)argument;
  uart_write_text("READY\n");

  for (;;) {
    byte = rv32_soc_uart_try_getc();
    if (byte >= 0) {
      rv32_soc_uart_putc((uint8_t)byte);
      echoed_byte = (uint32_t)byte;
      echo_count++;
    }
    vTaskDelay(pdMS_TO_TICKS(1U));
  }
}

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

static void check_task(void *argument)
{
  (void)argument;

  for (;;) {
    if ((blink_count >= 3U) &&
        (echo_count >= 1U) &&
        (freertos_tick_hook_count >= 4U) &&
        (freertos_context_switch_count >= 8U)) {
      freertos_demo_report.magic = FREERTOS_DEMO_REPORT_MAGIC;
      freertos_demo_report.kernel_version = FREERTOS_DEMO_KERNEL;
      freertos_demo_report.tick_count = (uint32_t)xTaskGetTickCount();
      freertos_demo_report.tick_hook_count = freertos_tick_hook_count;
      freertos_demo_report.context_switch_count = freertos_context_switch_count;
      freertos_demo_report.blink_count = blink_count;
      freertos_demo_report.echo_count = echo_count;
      freertos_demo_report.echoed_byte = echoed_byte;
      freertos_demo_report.gpio_output =
        rv32_soc_mmio_read32(RV32_SOC_GPIO_OUTPUT);
      freertos_demo_report.mstatus = csr_read_mstatus();
      freertos_demo_report.mie = csr_read_mie();
      freertos_demo_report.failure_code = 0U;
      rv32_soc_finish(RV32_SOC_PASS_STATUS);
    }
    vTaskDelay(pdMS_TO_TICKS(1U));
  }
}

int main(void)
{
  TaskHandle_t blink_handle;
  TaskHandle_t echo_handle;
  TaskHandle_t check_handle;
  volatile uint32_t *report_words =
    (volatile uint32_t *)(uintptr_t)FREERTOS_DEMO_REPORT_ADDR;

  for (uint32_t index = 0U;
       index < (uint32_t)(sizeof(freertos_demo_report_t) / sizeof(uint32_t));
       index++) {
    report_words[index] = 0U;
  }

  rv32_soc_gpio_write(0U);
  rv32_soc_gpio_set_output_enable(BLINK_MASK);
  rv32_soc_uart_clear_errors();

  freertos_demo_report.magic = FREERTOS_DEMO_REPORT_MAGIC;
  freertos_demo_report.kernel_version = FREERTOS_DEMO_KERNEL;

  blink_handle = xTaskCreateStatic(blink_task, "blink",
                                   BLINK_STACK_WORDS, NULL, 1U,
                                   blink_task_stack, &blink_task_tcb);
  echo_handle = xTaskCreateStatic(echo_task, "echo",
                                  ECHO_STACK_WORDS, NULL, 2U,
                                  echo_task_stack, &echo_task_tcb);
  check_handle = xTaskCreateStatic(check_task, "check",
                                   CHECK_STACK_WORDS, NULL, 3U,
                                   check_task_stack, &check_task_tcb);

  if ((blink_handle == NULL) || (echo_handle == NULL) ||
      (check_handle == NULL)) {
    freertos_platform_fail(UINT32_C(0x4001));
  }

  vTaskStartScheduler();
  freertos_platform_fail(UINT32_C(0x4002));
}
