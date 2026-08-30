/*
Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Modified for the rv32im-core freestanding environment. Timing uses the
architectural mcycle/minstret CSRs; formatted output is captured in a compact
TCM report block consumed by the Verilator harness.
*/
#include "coremark.h"
#include "core_portme.h"
#include "baremetal.h"

#include <stdarg.h>
#include <stdint.h>

#define COREMARK_REPORT_MAGIC   UINT32_C(0x434d524b)
#define COREMARK_REPORT_VERSION UINT32_C(1)
#define COREMARK_CLOCK_HZ       UINT32_C(75000000)

enum
{
    COREMARK_RUN_PERFORMANCE = 0,
    COREMARK_RUN_VALIDATION  = 1
};

typedef struct
{
    uint32_t magic;
    uint32_t version;
    uint32_t run_type;
    uint32_t clock_hz;
    uint32_t iterations;
    uint32_t cycles_lo;
    uint32_t cycles_hi;
    uint32_t instructions_lo;
    uint32_t instructions_hi;
    uint32_t seedcrc;
    uint32_t crclist;
    uint32_t crcmatrix;
    uint32_t crcstate;
    uint32_t crcfinal;
    uint32_t valid;
    uint32_t errors;
} coremark_report_t;

volatile coremark_report_t coremark_report
    __attribute__((section(".coremark_report"), used, aligned(4)));

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#else
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif

volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

static uint64_t start_cycle;
static uint64_t stop_cycle;
static uint64_t start_instret;
static uint64_t stop_instret;

static uint64_t read_counter(const uint32_t low_csr, const uint32_t high_csr)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do
    {
        if (low_csr == UINT32_C(0xb00))
        {
            __asm__ volatile("csrr %0, mcycleh" : "=r"(high_before));
            __asm__ volatile("csrr %0, mcycle" : "=r"(low));
            __asm__ volatile("csrr %0, mcycleh" : "=r"(high_after));
        }
        else
        {
            (void)high_csr;
            __asm__ volatile("csrr %0, minstreth" : "=r"(high_before));
            __asm__ volatile("csrr %0, minstret" : "=r"(low));
            __asm__ volatile("csrr %0, minstreth" : "=r"(high_after));
        }
    } while (high_before != high_after);

    return ((uint64_t)high_after << 32) | low;
}

static uint64_t read_mcycle64(void)
{
    return read_counter(UINT32_C(0xb00), UINT32_C(0xb80));
}

static uint64_t read_minstret64(void)
{
    return read_counter(UINT32_C(0xb02), UINT32_C(0xb82));
}

static int text_equal(const char *left, const char *right)
{
    while ((*left != '\0') && (*left == *right))
    {
        left++;
        right++;
    }
    return *left == *right;
}

static int text_contains(const char *text, const char *needle)
{
    const char *candidate;
    const char *match;

    for (; *text != '\0'; text++)
    {
        candidate = text;
        match = needle;
        while ((*candidate != '\0') && (*match != '\0')
               && (*candidate == *match))
        {
            candidate++;
            match++;
        }
        if (*match == '\0')
            return 1;
    }
    return 0;
}

void start_time(void)
{
    start_instret = read_minstret64();
    start_cycle = read_mcycle64();
}

void stop_time(void)
{
    stop_cycle = read_mcycle64();
    stop_instret = read_minstret64();
    coremark_report.cycles_lo = (uint32_t)(stop_cycle - start_cycle);
    coremark_report.cycles_hi = (uint32_t)((stop_cycle - start_cycle) >> 32);
    coremark_report.instructions_lo
        = (uint32_t)(stop_instret - start_instret);
    coremark_report.instructions_hi
        = (uint32_t)((stop_instret - start_instret) >> 32);
}

CORE_TICKS get_time(void)
{
    return (CORE_TICKS)(stop_cycle - start_cycle);
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / COREMARK_CLOCK_HZ;
}

int ee_printf(const char *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    if (text_equal(fmt, "Total ticks      : %lu\n"))
    {
        coremark_report.cycles_lo = (uint32_t)va_arg(args, unsigned long);
    }
    else if (text_equal(fmt, "Iterations       : %lu\n"))
    {
        coremark_report.iterations = (uint32_t)va_arg(args, unsigned long);
    }
    else if (text_equal(fmt, "seedcrc          : 0x%04x\n"))
    {
        coremark_report.seedcrc = (uint32_t)va_arg(args, int);
    }
    else if (text_contains(fmt, "crclist"))
    {
        (void)va_arg(args, int);
        coremark_report.crclist = (uint32_t)va_arg(args, int);
    }
    else if (text_contains(fmt, "crcmatrix"))
    {
        (void)va_arg(args, int);
        coremark_report.crcmatrix = (uint32_t)va_arg(args, int);
    }
    else if (text_contains(fmt, "crcstate"))
    {
        (void)va_arg(args, int);
        coremark_report.crcstate = (uint32_t)va_arg(args, int);
    }
    else if (text_contains(fmt, "crcfinal"))
    {
        (void)va_arg(args, int);
        coremark_report.crcfinal = (uint32_t)va_arg(args, int);
    }

    if (text_contains(fmt, "ERROR") || text_contains(fmt, "Errors detected")
        || text_contains(fmt, "Cannot validate"))
    {
        coremark_report.errors++;
    }
    if (text_contains(fmt, "Correct operation validated"))
    {
        coremark_report.valid = 1;
    }
    va_end(args);
    return 0;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    volatile uint32_t *words = (volatile uint32_t *)&coremark_report;
    uint32_t index;

    (void)argc;
    (void)argv;
    for (index = 0; index < (sizeof(coremark_report) / sizeof(uint32_t)); index++)
        words[index] = 0;

    coremark_report.magic = COREMARK_REPORT_MAGIC;
    coremark_report.version = COREMARK_REPORT_VERSION;
    coremark_report.clock_hz = COREMARK_CLOCK_HZ;
#if VALIDATION_RUN
    coremark_report.run_type = COREMARK_RUN_VALIDATION;
#else
    coremark_report.run_type = COREMARK_RUN_PERFORMANCE;
#endif

    if ((sizeof(ee_u8) != 1) || (sizeof(ee_s16) != 2)
        || (sizeof(ee_u16) != 2) || (sizeof(ee_s32) != 4)
        || (sizeof(ee_u32) != 4) || (sizeof(ee_ptr_int) != sizeof(void *)))
    {
        coremark_report.errors++;
    }
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    uint32_t expected_seedcrc;

    p->portable_id = 0;
    expected_seedcrc = (coremark_report.run_type == COREMARK_RUN_VALIDATION)
                     ? UINT32_C(0x18f2)
                     : UINT32_C(0xe9f5);
    if ((coremark_report.valid == 1U) && (coremark_report.errors == 0U)
        && (coremark_report.seedcrc == expected_seedcrc))
    {
        bm_pass();
    }
    bm_fail(UINT32_C(0x200) | (coremark_report.errors & UINT32_C(0xff)));
}
