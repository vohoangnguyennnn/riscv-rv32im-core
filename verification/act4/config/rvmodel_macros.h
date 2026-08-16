// DUT adapter for ACT4 self-checking ELFs.
// SPDX-License-Identifier: MIT

#ifndef RV32IM_5STAGE_RVMODEL_MACROS_H
#define RV32IM_5STAGE_RVMODEL_MACROS_H

// ACT4 keeps this hook after all test-visible data. No DUT-specific data is
// required because completion uses the final word of the simulation TCM.
#define RVMODEL_DATA_SECTION

// Console output is optional in ACT4. Failure diagnostics remain available
// from the RTL retirement history and ACT4 ELF/object dump.
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

// The present milestone has no asynchronous interrupt inputs. ACT4 requires
// these platform hooks to exist even when privileged tests are excluded.
#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 100
#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)
#define RVMODEL_SET_MSW_INT(_R1, _R2)
#define RVMODEL_CLR_MSW_INT(_R1, _R2)
#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)
#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

// The ACT4 simulation TCM is 1 MiB. Its final aligned word is a write-only
// completion mailbox observed through the core retirement trace.
#define RV32IM_ACT4_TOHOST 0x000ffffc

#define RVMODEL_HALT_PASS  \
  li t0, RV32IM_ACT4_TOHOST; \
  li t1, 1;                   \
  sw t1, 0(t0);               \
1:                            \
  j 1b;

#define RVMODEL_HALT_FAIL  \
  li t0, RV32IM_ACT4_TOHOST; \
  li t1, 3;                   \
  sw t1, 0(t0);               \
1:                            \
  j 1b;

#endif
