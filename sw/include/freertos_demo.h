#ifndef RV32IM_FREERTOS_DEMO_H
#define RV32IM_FREERTOS_DEMO_H

#include <stdint.h>

#define FREERTOS_DEMO_REPORT_ADDR  UINT32_C(0x0000e000)
#define FREERTOS_DEMO_REPORT_MAGIC UINT32_C(0x4652544f)
#define FREERTOS_DEMO_KERNEL       UINT32_C(0x000b0300)
#define FREERTOS_DEMO_ECHO_BYTE    UINT32_C(0x000000a5)

typedef struct {
  uint32_t magic;
  uint32_t kernel_version;
  uint32_t tick_count;
  uint32_t tick_hook_count;
  uint32_t context_switch_count;
  uint32_t blink_count;
  uint32_t echo_count;
  uint32_t echoed_byte;
  uint32_t gpio_output;
  uint32_t mstatus;
  uint32_t mie;
  uint32_t mcause;
  uint32_t mepc;
  uint32_t mtval;
  uint32_t failure_code;
  uint32_t reserved;
} freertos_demo_report_t;

#endif
