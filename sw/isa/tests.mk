# SPDX-License-Identifier: MIT

# Official riscv-tests programs enabled by the RV32IM project scope.
# Keep these groups explicit: they define both the Gate 6 execution order and
# the public coverage claim made by the regression.
RV32UI_ARITH_TESTS := \
	simple \
	add addi \
	and andi \
	auipc lui \
	or ori \
	sll slli \
	slt slti sltiu sltu \
	sra srai \
	srl srli \
	sub \
	xor xori

RV32UI_CONTROL_TESTS := \
	beq bge bgeu blt bltu bne \
	jal jalr

RV32UI_MEMORY_TESTS := \
	lb lbu lh lhu lw \
	sb sh sw \
	ld_st st_ld

RV32UI_TESTS := \
	$(RV32UI_ARITH_TESTS) \
	$(RV32UI_CONTROL_TESTS) \
	$(RV32UI_MEMORY_TESTS)

RV32UM_MUL_TESTS := mul mulh mulhsu mulhu
RV32UM_DIV_TESTS := div divu rem remu
RV32UM_TESTS := $(RV32UM_MUL_TESTS) $(RV32UM_DIV_TESTS)

# These exist in the pinned upstream rv32ui directory but intentionally do
# not belong to the current design contract:
# - fence_i: Zifencei extension, explicitly outside the RV32IM scope.
# - ma_data: requires invisible completion of misaligned accesses, whereas
#   this core's documented execution environment raises precise traps.
RV32UI_OUT_OF_SCOPE_TESTS := fence_i ma_data
