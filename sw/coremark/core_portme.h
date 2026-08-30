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

Modified for the rv32im-core freestanding environment.
*/
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

#define HAS_FLOAT   0
#define HAS_TIME_H  0
#define USE_CLOCK   0
#define HAS_STDIO   0
#define HAS_PRINTF  0

#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS   \
    "-O2 -std=gnu11 -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow " \
    "-mstrict-align -mno-relax -ffreestanding -fno-common -fno-pic " \
    "-ffunction-sections -fdata-sections -g3"
#define MEM_LOCATION     "RV32IM 64 KiB TCM"

typedef int16_t   ee_s16;
typedef uint16_t  ee_u16;
typedef int32_t   ee_s32;
typedef uint8_t   ee_u8;
typedef uint32_t  ee_u32;
typedef uint32_t  ee_ptr_int;
typedef size_t    ee_size_t;
typedef double    ee_f32;

#ifndef NULL
#define NULL ((void *)0)
#endif

#define align_mem(x) (void *)(4U + (((ee_ptr_int)(x) - 1U) & ~3U))

#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD  MEM_STATIC

#define MULTITHREAD 1
#define USE_PTHREAD  0
#define USE_FORK     0
#define USE_SOCKET   0

#define MAIN_HAS_NOARGC  1
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int  ee_printf(const char *fmt, ...);

#endif
