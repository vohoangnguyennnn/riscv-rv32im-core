#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include <stdint.h>

/* The FPGA wrapper and mtime both run from the 75 MHz SoC clock. */
#ifndef FREERTOS_CPU_CLOCK_HZ
#define FREERTOS_CPU_CLOCK_HZ UINT32_C(75000000)
#endif

#define configCPU_CLOCK_HZ                    FREERTOS_CPU_CLOCK_HZ
#define configTICK_RATE_HZ                    1000U
#define configUSE_PREEMPTION                  1
#define configUSE_TIME_SLICING                1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configUSE_TICKLESS_IDLE               0
#define configMAX_PRIORITIES                  4
#define configMINIMAL_STACK_SIZE              128U
#define configMAX_TASK_NAME_LEN               12
#define configTICK_TYPE_WIDTH_IN_BITS         TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD               1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 1
#define configQUEUE_REGISTRY_SIZE             0
#define configENABLE_BACKWARD_COMPATIBILITY   0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 0
#define configUSE_MINI_LIST_ITEM              1
#define configSTACK_DEPTH_TYPE                uint32_t
#define configUSE_NEWLIB_REENTRANT            0

#define configUSE_TIMERS                      0
#define configUSE_EVENT_GROUPS                0
#define configUSE_STREAM_BUFFERS              0
#define configSUPPORT_STATIC_ALLOCATION       1
#define configSUPPORT_DYNAMIC_ALLOCATION      0
#define configKERNEL_PROVIDED_STATIC_MEMORY   1

#define configUSE_IDLE_HOOK                   0
#define configUSE_TICK_HOOK                   1
#define configUSE_MALLOC_FAILED_HOOK          0
#define configCHECK_FOR_STACK_OVERFLOW        2
#define configGENERATE_RUN_TIME_STATS         0
#define configUSE_TRACE_FACILITY              0
#define configUSE_STATS_FORMATTING_FUNCTIONS  0
#define configUSE_CO_ROUTINES                 0
#define configUSE_TASK_NOTIFICATIONS          0
#define configUSE_MUTEXES                     0
#define configUSE_RECURSIVE_MUTEXES           0
#define configUSE_COUNTING_SEMAPHORES         0
#define configUSE_QUEUE_SETS                  0
#define configUSE_APPLICATION_TASK_TAG        0
#define configUSE_POSIX_ERRNO                 0

#define configISR_STACK_SIZE_WORDS            192U
#define configENABLE_FPU                      0
#define configENABLE_VPU                      0
#define configMTIME_BASE_ADDRESS              UINT32_C(0x0200bff8)
#define configMTIMECMP_BASE_ADDRESS           UINT32_C(0x02004000)

#define INCLUDE_vTaskDelay                    1
#define INCLUDE_vTaskDelayUntil               1
#define INCLUDE_vTaskDelete                   0
#define INCLUDE_vTaskSuspend                  0
#define INCLUDE_xTaskGetSchedulerState        0
#define INCLUDE_xTaskGetCurrentTaskHandle     0
#define INCLUDE_uxTaskGetStackHighWaterMark   0
#define INCLUDE_uxTaskGetStackHighWaterMark2  0
#define INCLUDE_xTaskAbortDelay               0
#define INCLUDE_eTaskGetState                 0

void freertos_assert_fail(const char *file, unsigned long line)
  __attribute__((noreturn));
void freertos_trace_task_switched_in(void);

#define configASSERT(condition) \
  do { \
    if ((condition) == 0) { \
      freertos_assert_fail(__FILE__, (unsigned long)__LINE__); \
    } \
  } while (0)

#define traceTASK_SWITCHED_IN() freertos_trace_task_switched_in()

#endif
