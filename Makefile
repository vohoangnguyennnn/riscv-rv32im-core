SHELL := /bin/bash

VERILATOR ?= verilator
QUESTA_VLIB ?= vlib
QUESTA_VMAP ?= vmap
QUESTA_VLOG ?= vlog
QUESTA_VSIM ?= vsim
BAREMETAL_PLUSARGS ?=
ISA_PLUSARGS ?=
ISA_TRACE_DIR ?=
PYTHON ?= python3

# RISC-V Architectural Certification Tests (ACT4). Source, generated ELFs,
# tool caches, and RTL diagnostics stay outside the repository. The exact ACT4
# release and commit are both checked so a moved tag cannot change sign-off.
ACT4_VERSION ?= 4.0.0
ACT4_COMMIT ?= a7c99303516f4e668f7488f172043392e23b9dfd
ACT4_REPOSITORY ?= https://github.com/riscv/riscv-arch-test.git
ACT4_ROOT ?= /tmp/rv32im-core-act4-$(shell id -u)
ACT4_SOURCE_DIR ?= $(ACT4_ROOT)/source
ACT4_WORK_DIR ?= $(ACT4_ROOT)/work
ACT4_CONFIG_ALIAS ?= $(ACT4_ROOT)/config
ACT4_ARTIFACT_DIR ?= $(ACT4_ROOT)/rtl-artifacts
ACT4_XDG_CACHE ?= $(ACT4_ROOT)/xdg-cache
ACT4_XDG_DATA ?= $(ACT4_ROOT)/xdg-data
ACT4_XDG_STATE ?= $(ACT4_ROOT)/xdg-state
ACT4_UV_CACHE ?= $(ACT4_ROOT)/uv-cache
ACT4_EXTENSIONS ?= I,M
ACT4_TEST ?=
ACT4_RUN_ARGS ?=
ACT4_ELF_DIR = $(ACT4_WORK_DIR)/rv32im-5stage/elfs
ACT4_Z3_WHEEL = $(ACT4_ROOT)/z3_solver-4.16.0.0.whl
ACT4_Z3_LIB = $(ACT4_XDG_CACHE)/udb/z3/z3-4.16.0/x64/libz3.so
ACT4_Z3_URL = https://github.com/Z3Prover/z3/releases/download/z3-4.16.0/z3_solver-4.16.0.0-py3-none-manylinux_2_27_x86_64.whl
ACT4_Z3_SHA256 = afae2551f795670f0522cfce82132d129c408a2694adff71eb01ba0f2ece44f9

# Questa is an interactive debug companion to the Verilator regression.  Keep
# its generated library and waveform database outside the repository, just as
# the Verilator flow does.  TEST selects one top-level testbench whose *_SRCS
# list is defined below; command-line values may override all tool variables.
REPO_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
QUESTA_BUILD_DIR ?= /tmp/rv32im-core-questa-$(shell id -u)
TEST ?= tb_rv32_core
PROGRAM ?= smoke
ISA_TEST ?= rv32ui-add
QUESTA_PLUSARGS ?=
# Integration testbenches intentionally preload the inferred TCM through its
# backdoor array before reset release. Questa 7061 treats that verification-only
# initialization plus the RAM always_ff writer as an error; suppress only this
# diagnostic rather than weakening the synthesizable RAM coding style.
QUESTA_VSIM_FLAGS ?= -suppress 7061

# Verilator's generated GNU Make flow cannot build below a path containing
# spaces. Keep generated models in a deterministic per-user temporary path so
# this repository works from paths such as "New Volume" as well as in CI.
BUILD_DIR := /tmp/rv32im-core-verilator-$(shell id -u)
SOFTWARE_BUILD_DIR := /tmp/rv32im-core-software-$(shell id -u)
ISA_BUILD_DIR := /tmp/rv32im-core-isa-$(shell id -u)

# Keep simulation builds strict. TIMESCALEMOD is waived because synthesizable
# RTL intentionally has no simulation time units; every timing testbench does.
# UNUSEDPARAM is expected when a unit test imports only part of rv32_pkg.
# UNUSEDSIGNAL/PINCONNECTEMPTY cover intentionally ignored instruction,
# bundle, and diagnostic fields. BLKSEQ permits immediate testbench scoreboard
# bookkeeping in clocked monitors. Synthesizable RTL is checked separately by
# the stricter lint target below.
VERILATOR_TEST_FLAGS := \
	--binary \
	--timing \
	--assert \
	-Wall \
	-Wno-TIMESCALEMOD \
	-Wno-UNUSEDPARAM \
	-Wno-UNUSEDSIGNAL \
	-Wno-PINCONNECTEMPTY \
	-Wno-BLKSEQ

# These lint waivers are structural at the standalone core boundary:
# - intentionally unused debug/aggregate outputs are left open;
# - the memory interface is only half-driven until a memory slave is attached;
# - packed pipeline bundles are intentionally consumed field-by-field.
VERILATOR_LINT_FLAGS := \
	--lint-only \
	-Wall \
	-Wno-PINCONNECTEMPTY \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNDRIVEN

CORE_MANIFEST := files/core.f
CORE_SOURCES := $(shell sed -e '/^[[:space:]]*\#/d' -e '/^[[:space:]]*$$/d' $(CORE_MANIFEST))
TCM_SOURCES := $(CORE_SOURCES) rtl/soc/rv32_tcm.sv
SOC_SOURCES := $(TCM_SOURCES) rtl/soc/soc_tcm_top.sv
FPGA_SOURCES := $(SOC_SOURCES) rtl/fpga/reset_sync.sv rtl/fpga/fpga_top.sv

UNIT_TESTS := \
	tb_alu \
	tb_imm_gen \
	tb_decoder \
	tb_branch_unit \
	tb_regfile \
	tb_reset_sync \
	tb_rv32_tcm \
	tb_lsu \
	tb_if_stage \
	tb_id_stage \
	tb_forwarding_unit \
	tb_hazard_unit \
	tb_mul_unit \
	tb_div_unit \
	tb_ex_stage \
	tb_pipeline_ctrl \
	tb_csr

GATE4_TESTS := \
	tb_pipeline_forwarding \
	tb_pipeline_memory_wait \
	tb_pipeline_control

INTEGRATION_TESTS := \
	tb_rv32_core \
	tb_csr_core \
	tb_soc_tcm_top \
	tb_fpga_top \
	$(GATE4_TESTS)

FPGA_TESTS := tb_reset_sync tb_soc_tcm_top tb_fpga_top

ALL_TESTS := $(UNIT_TESTS) $(INTEGRATION_TESTS)

# Curated waveform portfolio aligned with Gates 2-5 of the architecture plan.
# Bare-metal/ISA images use dedicated targets because they need runtime images.
QUESTA_GUI_TESTS := \
	tb_mul_unit \
	tb_div_unit \
	tb_lsu \
	tb_pipeline_ctrl \
	tb_pipeline_forwarding \
	tb_pipeline_memory_wait \
	tb_pipeline_control \
	tb_csr_core \
	tb_rv32_core \
	tb_soc_tcm_top \
	tb_fpga_top

include sw/tests/programs.mk
include sw/isa/tests.mk

BAREMETAL_TARGETS := $(addprefix baremetal-,$(BAREMETAL_PROGRAMS))
ISA_RV32UI_TARGETS := $(addprefix isa-rv32ui-,$(RV32UI_TESTS))
ISA_RV32UM_TARGETS := $(addprefix isa-rv32um-,$(RV32UM_TESTS))
ISA_TARGETS := $(ISA_RV32UI_TARGETS) $(ISA_RV32UM_TARGETS)
ISA_PROGRAMS := \
	$(addprefix rv32ui-,$(RV32UI_TESTS)) \
	$(addprefix rv32um-,$(RV32UM_TESTS))

# Inputs used by the delegated ISA image rules below. Listing them here makes
# the root build notice changes even when an image already exists in /tmp;
# the sw/isa Makefile remains responsible for the actual incremental rebuild.
ISA_IMAGE_COMMON_DEPS := \
	sw/isa/Makefile \
	sw/isa/tests.mk \
	sw/isa/link.ld \
	sw/isa/env/riscv_test.h \
	third_party/riscv-tests/isa/macros/scalar/test_macros.h \
	tools/bin_to_memh.py

tb_alu_SRCS := rtl/core/rv32_pkg.sv rtl/core/alu.sv tb/unit/tb_alu.sv
tb_imm_gen_SRCS := rtl/core/rv32_pkg.sv rtl/core/imm_gen.sv tb/unit/tb_imm_gen.sv
tb_decoder_SRCS := rtl/core/rv32_pkg.sv rtl/core/decoder.sv tb/unit/tb_decoder.sv
tb_branch_unit_SRCS := rtl/core/rv32_pkg.sv rtl/core/branch_unit.sv tb/unit/tb_branch_unit.sv
tb_regfile_SRCS := rtl/core/regfile.sv tb/unit/tb_regfile.sv
tb_reset_sync_SRCS := rtl/fpga/reset_sync.sv tb/unit/tb_reset_sync.sv
tb_rv32_tcm_SRCS := rtl/core/rv32_mem_if.sv rtl/soc/rv32_tcm.sv tb/unit/tb_rv32_tcm.sv
tb_lsu_SRCS := rtl/core/rv32_pkg.sv rtl/core/rv32_mem_if.sv rtl/core/lsu.sv tb/unit/tb_lsu.sv
tb_if_stage_SRCS := rtl/core/rv32_pkg.sv rtl/core/rv32_mem_if.sv rtl/core/if_stage.sv tb/unit/tb_if_stage.sv
tb_id_stage_SRCS := \
	rtl/core/rv32_pkg.sv \
	rtl/core/imm_gen.sv \
	rtl/core/decoder.sv \
	rtl/core/regfile.sv \
	rtl/core/id_stage.sv \
	tb/unit/tb_id_stage.sv
tb_forwarding_unit_SRCS := rtl/core/rv32_pkg.sv rtl/core/forwarding_unit.sv tb/unit/tb_forwarding_unit.sv
tb_hazard_unit_SRCS := rtl/core/rv32_pkg.sv rtl/core/hazard_unit.sv tb/unit/tb_hazard_unit.sv
tb_mul_unit_SRCS := rtl/core/rv32_pkg.sv rtl/core/mul_unit.sv tb/unit/tb_mul_unit.sv
tb_div_unit_SRCS := rtl/core/rv32_pkg.sv rtl/core/div_unit.sv tb/unit/tb_div_unit.sv
tb_ex_stage_SRCS := \
	rtl/core/rv32_pkg.sv \
	rtl/core/alu.sv \
	rtl/core/branch_unit.sv \
	rtl/core/mul_unit.sv \
	rtl/core/div_unit.sv \
	rtl/core/ex_stage.sv \
	tb/unit/tb_ex_stage.sv
tb_pipeline_ctrl_SRCS := rtl/core/rv32_pkg.sv rtl/core/pipeline_ctrl.sv tb/unit/tb_pipeline_ctrl.sv
tb_csr_SRCS := rtl/core/rv32_pkg.sv rtl/core/csr_file.sv tb/unit/tb_csr.sv
tb_rv32_core_SRCS := $(TCM_SOURCES) tb/integration/tb_rv32_core.sv
tb_csr_core_SRCS := $(TCM_SOURCES) tb/integration/tb_csr_core.sv
tb_soc_tcm_top_SRCS := \
	$(SOC_SOURCES) \
	tb/integration/tb_soc_tcm_top.sv
tb_fpga_top_SRCS := \
	$(FPGA_SOURCES) \
	tb/integration/tb_fpga_top.sv
tb_pipeline_forwarding_SRCS := \
	$(TCM_SOURCES) \
	tb/common/rv32_tb_pkg.sv \
	tb/integration/tb_pipeline_forwarding.sv
tb_pipeline_memory_wait_SRCS := \
	$(CORE_SOURCES) \
	tb/common/rv32_tb_pkg.sv \
	tb/common/rv32_delayed_mem.sv \
	tb/integration/tb_pipeline_memory_wait.sv
tb_pipeline_control_SRCS := \
	$(TCM_SOURCES) \
	tb/common/rv32_tb_pkg.sv \
	tb/integration/tb_pipeline_control.sv
tb_baremetal_SRCS := \
	$(TCM_SOURCES) \
	tb/integration/tb_baremetal.sv

# Every integration build expands CORE_SOURCES at parse time. Preserve the
# manifest itself as a dependency so source removal or reordering also causes
# cached Verilator models to be rebuilt, not only source timestamp changes.
$(foreach test,$(ALL_TESTS),$(eval $(test)_BUILD_DEPS :=))
$(foreach test,$(INTEGRATION_TESTS),$(eval $(test)_BUILD_DEPS := $(CORE_MANIFEST)))

BAREMETAL_SIM := $(BUILD_DIR)/tb_baremetal/Vtb_baremetal
ACT4_SIM := $(BUILD_DIR)/tb_baremetal_act4/Vtb_baremetal_act4

.DEFAULT_GOAL := test

.PHONY: all test rtl-check-tools lint unit integration gate4 fpga baremetal software-images \
	isa isa-images isa-rv32ui-arithmetic isa-rv32ui-control \
	isa-rv32ui-memory isa-rv32ui isa-rv32um-multiply isa-rv32um-divide isa-rv32um \
	questa-list questa-compile questa-run questa-gui questa-check \
	questa-baremetal-gui questa-isa-gui questa-clean \
	act4 act4-check-tools act4-fetch act4-config act4-z3 act4-generate \
	act4-sim act4-run act4-test act4-clean \
	list help clean $(ALL_TESTS) $(BAREMETAL_TARGETS) $(ISA_TARGETS)

all: test

test: lint unit integration baremetal isa
	@echo "[PASS] RTL lint, $(words $(ALL_TESTS)) RTL simulations, $(words $(BAREMETAL_PROGRAMS)) bare-metal programs, and $(words $(ISA_PROGRAMS)) ISA tests completed"

rtl-check-tools:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { \
		echo "error: '$(VERILATOR)' was not found in PATH" >&2; \
		exit 127; \
	}

lint: rtl-check-tools
	@echo "[LINT] rv32_core"
	@$(VERILATOR) $(VERILATOR_LINT_FLAGS) --top-module rv32_core -f $(CORE_MANIFEST)
	@echo "[LINT] rv32_tcm"
	@$(VERILATOR) $(VERILATOR_LINT_FLAGS) --top-module rv32_tcm \
		rtl/core/rv32_mem_if.sv rtl/soc/rv32_tcm.sv
	@echo "[LINT] soc_tcm_top"
	@$(VERILATOR) $(VERILATOR_LINT_FLAGS) --top-module soc_tcm_top \
		$(SOC_SOURCES)
	@echo "[LINT] reset_sync"
	@$(VERILATOR) $(VERILATOR_LINT_FLAGS) --top-module reset_sync \
		rtl/fpga/reset_sync.sv
	@echo "[LINT] fpga_top"
	@$(VERILATOR) $(VERILATOR_LINT_FLAGS) --top-module fpga_top -f files/fpga.f

unit: $(UNIT_TESTS)
	@echo "[PASS] $(words $(UNIT_TESTS)) unit tests completed"

integration: $(INTEGRATION_TESTS)
	@echo "[PASS] $(words $(INTEGRATION_TESTS)) integration tests completed"

gate4: $(GATE4_TESTS)
	@echo "[PASS] Gate 4 forwarding, wait-state, control, and precise-squash tests completed"

fpga: $(FPGA_TESTS)
	@echo "[PASS] FPGA reset, SoC boundary, BRAM image, and LED smoke tests completed"

software-images:
	@$(MAKE) -C sw BUILD_DIR=$(SOFTWARE_BUILD_DIR) all

baremetal: $(BAREMETAL_TARGETS)
	@echo "[PASS] $(words $(BAREMETAL_PROGRAMS)) bare-metal software tests completed"

isa-images:
	@$(MAKE) -C sw/isa BUILD_DIR=$(ISA_BUILD_DIR) all

isa-rv32ui-arithmetic: $(addprefix isa-rv32ui-,$(RV32UI_ARITH_TESTS))
	@echo "[PASS] Gate 6 RV32I arithmetic/logic group completed"

isa-rv32ui-control: $(addprefix isa-rv32ui-,$(RV32UI_CONTROL_TESTS))
	@echo "[PASS] Gate 6 RV32I branch/jump group completed"

isa-rv32ui-memory: $(addprefix isa-rv32ui-,$(RV32UI_MEMORY_TESTS))
	@echo "[PASS] Gate 6 RV32I load/store group completed"

isa-rv32ui: $(ISA_RV32UI_TARGETS)
	@echo "[PASS] all $(words $(RV32UI_TESTS)) in-scope rv32ui programs completed"

isa-rv32um-multiply: $(addprefix isa-rv32um-,$(RV32UM_MUL_TESTS))
	@echo "[PASS] Gate 6 RV32M multiply group completed"

isa-rv32um-divide: $(addprefix isa-rv32um-,$(RV32UM_DIV_TESTS))
	@echo "[PASS] Gate 6 RV32M divide/remainder group completed"

isa-rv32um: $(ISA_RV32UM_TARGETS)
	@echo "[PASS] all $(words $(RV32UM_TESTS)) rv32um programs completed"

isa: isa-rv32ui isa-rv32um
	@echo "[PASS] Gate 6 ISA regression: $(words $(ISA_PROGRAMS)) independent programs completed"

list:
	@printf '%s\n' $(ALL_TESTS) $(BAREMETAL_TARGETS) $(ISA_TARGETS)

help:
	@echo "RV32IM RTL regression targets"
	@echo "  make test         Run lint and every RTL/software/ISA regression"
	@echo "  make lint         Lint the core, TCM, SoC, reset, and FPGA top"
	@echo "  make unit         Run all unit tests"
	@echo "  make integration  Run all core integration tests"
	@echo "  make gate4        Run the Gate 4 directed acceptance suite"
	@echo "  make fpga         Run FPGA reset and wrapper smoke tests"
	@echo "  make baremetal    Build and run all freestanding software tests"
	@echo "  make baremetal-X  Build and run one software test (smoke or trap)"
	@echo "  make isa          Run the complete Gate 6 RV32I/RV32M ISA suite"
	@echo "  make isa-rv32ui   Run all in-scope upstream rv32ui tests"
	@echo "  make isa-rv32um   Run all upstream rv32um tests"
	@echo "  make isa-rv32ui-add  Build and run one ISA test"
	@echo "  make act4         Generate and run all 47 ACT4 4.0.0 I/M tests"
	@echo "  make act4-test ACT4_TEST=I-add  Run matching ACT4 test(s)"
	@echo "  make <test-name>  Run one test, for example: make tb_div_unit"
	@echo "  make questa-list  List curated Questa waveform testbenches"
	@echo "  make questa-run TEST=tb_rv32_core  Compile and run one test in batch mode"
	@echo "  make questa-gui TEST=tb_rv32_core  Open the curated waveform in Questa GUI"
	@echo "  make questa-check Run the curated Questa portfolio in batch mode"
	@echo "  make questa-baremetal-gui PROGRAM=smoke  Debug one bare-metal image"
	@echo "  make questa-isa-gui ISA_TEST=rv32ui-add  Debug one ISA image"
	@echo "  make list         List every available simulation test"
	@echo "  make clean        Remove local Verilator, software, ISA, Questa, and ACT4 results"
	@echo ""
	@echo "Parallel example: make -j$$(nproc) test"

clean: questa-clean act4-clean
	@$(RM) -r $(BUILD_DIR) $(SOFTWARE_BUILD_DIR) $(ISA_BUILD_DIR)

# ---------------------------------------------------------------------------
# ACT4 architectural-test flow
# ---------------------------------------------------------------------------
# ACT4 4.0.0's CONFIG_FILES interface is whitespace-separated. A temporary
# symlink gives the DUT config a space-free path even when this checkout lives
# below a directory such as "New Volume".
act4-check-tools:
	@for tool in git curl unzip sha256sum mise riscv64-unknown-elf-gcc \
		riscv64-unknown-elf-objdump sail_riscv_sim $(PYTHON) $(VERILATOR); do \
		command -v $$tool >/dev/null 2>&1 || { \
			echo "error: ACT4 prerequisite '$$tool' was not found in PATH" >&2; \
			exit 127; \
		}; \
	done
	@case "$$(uname -s)/$$(uname -m)" in \
		Linux/x86_64) ;; \
		*) echo "error: the pinned ACT4 Z3 bootstrap currently supports Linux/x86_64" >&2; exit 2 ;; \
	esac
	@riscv64-unknown-elf-gcc -dumpmachine | grep -q '^riscv64-unknown-elf$$' || { \
		echo "error: unexpected RISC-V bare-metal compiler target" >&2; exit 2; \
	}
	@sail_riscv_sim --version 2>&1 | grep -q '0\.10' || { \
		echo "error: ACT4 $(ACT4_VERSION) requires sail-riscv 0.10" >&2; exit 2; \
	}

act4-fetch: act4-check-tools
	@mkdir -p "$(ACT4_ROOT)"
	@if [ ! -d "$(ACT4_SOURCE_DIR)/.git" ]; then \
		echo "[ACT4 FETCH] release $(ACT4_VERSION)"; \
		git clone --depth 1 --branch "$(ACT4_VERSION)" \
			"$(ACT4_REPOSITORY)" "$(ACT4_SOURCE_DIR)"; \
	fi
	@actual=$$(git -C "$(ACT4_SOURCE_DIR)" rev-parse HEAD); \
	if [ "$$actual" != "$(ACT4_COMMIT)" ]; then \
		echo "error: ACT4 source commit $$actual does not match pinned $(ACT4_COMMIT)" >&2; \
		exit 2; \
	fi
	@mise trust "$(ACT4_SOURCE_DIR)/.mise.toml" >/dev/null

act4-config:
	@mkdir -p "$(ACT4_ROOT)"
	@if [ -e "$(ACT4_CONFIG_ALIAS)" ] && [ ! -L "$(ACT4_CONFIG_ALIAS)" ]; then \
		echo "error: refusing to replace non-symlink $(ACT4_CONFIG_ALIAS)" >&2; exit 2; \
	fi
	@ln -sfn "$(REPO_ROOT)/verification/act4/config" "$(ACT4_CONFIG_ALIAS)"

$(ACT4_Z3_LIB): | act4-check-tools
	@mkdir -p "$(@D)" "$(ACT4_ROOT)"
	@echo "[ACT4 FETCH] Z3 4.16.0 runtime"
	@curl -fL --retry 3 "$(ACT4_Z3_URL)" -o "$(ACT4_Z3_WHEEL).tmp"
	@echo "$(ACT4_Z3_SHA256)  $(ACT4_Z3_WHEEL).tmp" | sha256sum -c -
	@mv "$(ACT4_Z3_WHEEL).tmp" "$(ACT4_Z3_WHEEL)"
	@unzip -p "$(ACT4_Z3_WHEEL)" z3/lib/libz3.so > "$@.tmp"
	@mv "$@.tmp" "$@"

act4-z3: $(ACT4_Z3_LIB)

act4-generate: act4-fetch act4-config act4-z3
	@mkdir -p "$(ACT4_WORK_DIR)" "$(ACT4_XDG_DATA)" \
		"$(ACT4_XDG_STATE)" "$(ACT4_UV_CACHE)"
	@echo "[ACT4 GENERATE] extensions $(ACT4_EXTENSIONS)"
	+@XDG_CACHE_HOME="$(ACT4_XDG_CACHE)" \
		XDG_DATA_HOME="$(ACT4_XDG_DATA)" \
		XDG_STATE_HOME="$(ACT4_XDG_STATE)" \
		UV_CACHE_DIR="$(ACT4_UV_CACHE)" \
		$(MAKE) -C "$(ACT4_SOURCE_DIR)" \
		CONFIG_FILES="$(ACT4_CONFIG_ALIAS)/test_config.yaml" \
		WORKDIR="$(ACT4_WORK_DIR)" EXTENSIONS="$(ACT4_EXTENSIONS)"
	@count=$$(find "$(ACT4_ELF_DIR)" -type f -name '*.elf' | wc -l); \
	if [ "$$count" -ne 47 ]; then \
		echo "error: ACT4 $(ACT4_VERSION) I/M generation produced $$count ELFs, expected 47" >&2; \
		exit 2; \
	fi
	@echo "[PASS] ACT4 generated 47 self-checking I/M ELFs"

$(ACT4_SIM): $(tb_baremetal_SRCS) $(CORE_MANIFEST) Makefile | rtl-check-tools
	@mkdir -p $(@D)
	@echo "[BUILD] tb_baremetal ACT4 (1 MiB TCM)"
	+@$(VERILATOR) $(VERILATOR_TEST_FLAGS) \
		--top-module tb_baremetal \
		-GTCM_BYTES=1048576 \
		--Mdir $(@D) \
		-o Vtb_baremetal_act4 \
		$(tb_baremetal_SRCS)

act4-sim: $(ACT4_SIM)

act4-run: act4-generate act4-sim
	@$(PYTHON) verification/act4/run.py \
		--sim "$(ACT4_SIM)" \
		--elf-dir "$(ACT4_ELF_DIR)" \
		--artifact-dir "$(ACT4_ARTIFACT_DIR)" \
		$(ACT4_RUN_ARGS)

act4: act4-run
	@echo "[PASS] ACT4 $(ACT4_VERSION) architectural regression: 47/47 RV32I/RV32M tests"

act4-test: act4-generate act4-sim
	@test -n "$(strip $(ACT4_TEST))" || { \
		echo "error: set ACT4_TEST to a basename, substring, or glob" >&2; exit 2; \
	}
	@$(PYTHON) verification/act4/run.py \
		--sim "$(ACT4_SIM)" \
		--elf-dir "$(ACT4_ELF_DIR)" \
		--artifact-dir "$(ACT4_ARTIFACT_DIR)" \
		--test "$(ACT4_TEST)" \
		$(ACT4_RUN_ARGS)

act4-clean:
	@$(RM) -r "$(ACT4_WORK_DIR)" "$(ACT4_ARTIFACT_DIR)" \
		"$(BUILD_DIR)/tb_baremetal_act4"

# ---------------------------------------------------------------------------
# QuestaSim waveform/debug flow
# ---------------------------------------------------------------------------
# Run vlib/vmap inside the isolated test directory so modelsim.ini and the work
# library never pollute the source tree.  Compile and simulate from REPO_ROOT so
# relative $readmemh paths in existing testbenches keep their normal meaning.
QUESTA_TEST_SRCS = $($(TEST)_SRCS)
QUESTA_TEST_DIR = $(QUESTA_BUILD_DIR)/$(TEST)
QUESTA_MODELSIM_INI = $(QUESTA_TEST_DIR)/modelsim.ini
QUESTA_WAVE_DO = $(REPO_ROOT)/sim/questa/waves/$(TEST).do
QUESTA_BATCH_DO = $(REPO_ROOT)/sim/questa/run_batch.do

questa-list:
	@printf '%s\n' $(QUESTA_GUI_TESTS)
	@echo "tb_baremetal (use questa-baremetal-gui or set QUESTA_PLUSARGS)"

questa-compile:
	@command -v $(QUESTA_VLIB) >/dev/null 2>&1 || { \
		echo "error: '$(QUESTA_VLIB)' was not found in PATH" >&2; exit 127; \
	}
	@command -v $(QUESTA_VMAP) >/dev/null 2>&1 || { \
		echo "error: '$(QUESTA_VMAP)' was not found in PATH" >&2; exit 127; \
	}
	@command -v $(QUESTA_VLOG) >/dev/null 2>&1 || { \
		echo "error: '$(QUESTA_VLOG)' was not found in PATH" >&2; exit 127; \
	}
	@test -n "$(strip $(QUESTA_TEST_SRCS))" || { \
		echo "error: unknown TEST='$(TEST)' or no $(TEST)_SRCS list" >&2; \
		echo "hint: run 'make questa-list'" >&2; exit 2; \
	}
	@mkdir -p "$(QUESTA_TEST_DIR)"
	@if [ ! -d "$(QUESTA_TEST_DIR)/work" ]; then \
		cd "$(QUESTA_TEST_DIR)" && $(QUESTA_VLIB) work; \
	fi
	@cd "$(QUESTA_TEST_DIR)" && $(QUESTA_VMAP) work "$(QUESTA_TEST_DIR)/work"
	@echo "[QUESTA BUILD] $(TEST)"
	@$(QUESTA_VLOG) -ini "$(QUESTA_MODELSIM_INI)" -sv -work work \
		$(foreach src,$(QUESTA_TEST_SRCS),"$(REPO_ROOT)/$(src)")

questa-run: questa-compile
	@command -v $(QUESTA_VSIM) >/dev/null 2>&1 || { \
		echo "error: '$(QUESTA_VSIM)' was not found in PATH" >&2; exit 127; \
	}
	@echo "[QUESTA RUN]   $(TEST)"
	@cd "$(REPO_ROOT)" && $(QUESTA_VSIM) -c $(QUESTA_VSIM_FLAGS) \
		-ini "$(QUESTA_MODELSIM_INI)" \
		-lib work -voptargs=+acc \
		-wlf "$(QUESTA_TEST_DIR)/$(TEST).wlf" \
		-l "$(QUESTA_TEST_DIR)/transcript" \
		work.$(TEST) $(QUESTA_PLUSARGS) \
		-do "do {$(QUESTA_BATCH_DO)}"
	@test -s "$(QUESTA_TEST_DIR)/transcript" || { \
		echo "error: Questa produced no transcript for $(TEST)" >&2; exit 1; \
	}
	@grep -Eq '(^|# )([[:alnum:]_]+: PASS|PASS:)' \
		"$(QUESTA_TEST_DIR)/transcript" || { \
		echo "error: Questa transcript has no PASS result for $(TEST)" >&2; \
		tail -n 40 "$(QUESTA_TEST_DIR)/transcript" >&2; exit 1; \
	}

questa-gui: questa-compile
	@command -v $(QUESTA_VSIM) >/dev/null 2>&1 || { \
		echo "error: '$(QUESTA_VSIM)' was not found in PATH" >&2; exit 127; \
	}
	@test -f "$(QUESTA_WAVE_DO)" || { \
		echo "error: no curated waveform file for TEST='$(TEST)'" >&2; \
		echo "expected: $(QUESTA_WAVE_DO)" >&2; exit 2; \
	}
	@echo "[QUESTA GUI]   $(TEST)"
	@cd "$(REPO_ROOT)" && $(QUESTA_VSIM) -gui $(QUESTA_VSIM_FLAGS) \
		-ini "$(QUESTA_MODELSIM_INI)" \
		-lib work -voptargs=+acc \
		-wlf "$(QUESTA_TEST_DIR)/$(TEST).wlf" \
		-l "$(QUESTA_TEST_DIR)/transcript" \
		work.$(TEST) $(QUESTA_PLUSARGS) \
		-do "do {$(QUESTA_WAVE_DO)}"

questa-check:
	@set -e; for test in $(QUESTA_GUI_TESTS); do \
		$(MAKE) --no-print-directory questa-run TEST=$$test; \
	done
	@echo "[PASS] $(words $(QUESTA_GUI_TESTS)) curated Questa waveform tests completed"

questa-baremetal-gui: software-images
	@case " $(BAREMETAL_PROGRAMS) " in \
		*" $(PROGRAM) "*) ;; \
		*) echo "error: unknown PROGRAM='$(PROGRAM)'; choices: $(BAREMETAL_PROGRAMS)" >&2; exit 2 ;; \
	esac
	@$(MAKE) --no-print-directory questa-gui \
		TEST=tb_baremetal \
		QUESTA_PLUSARGS="+test=$(PROGRAM) +mem=$(SOFTWARE_BUILD_DIR)/$(PROGRAM).mem"

questa-isa-gui:
	@case " $(ISA_PROGRAMS) " in \
		*" $(ISA_TEST) "*) ;; \
		*) echo "error: unknown ISA_TEST='$(ISA_TEST)'" >&2; exit 2 ;; \
	esac
	@$(MAKE) -C sw/isa BUILD_DIR=$(ISA_BUILD_DIR) "$(ISA_BUILD_DIR)/$(ISA_TEST).mem"
	@$(MAKE) --no-print-directory questa-gui \
		TEST=tb_baremetal \
		QUESTA_PLUSARGS="+test=$(ISA_TEST) +mem=$(ISA_BUILD_DIR)/$(ISA_TEST).mem"

questa-clean:
	@$(RM) -r "$(QUESTA_BUILD_DIR)"

$(BAREMETAL_SIM): $(tb_baremetal_SRCS) $(CORE_MANIFEST) Makefile | rtl-check-tools
	@mkdir -p $(@D)
	@echo "[BUILD] tb_baremetal"
	+@$(VERILATOR) $(VERILATOR_TEST_FLAGS) \
		--top-module tb_baremetal \
		--Mdir $(@D) \
		-o Vtb_baremetal \
		$(tb_baremetal_SRCS)

define BAREMETAL_template
baremetal-$(1): software-images $(BAREMETAL_SIM)
	@echo "[RUN]   baremetal-$(1)"
	@$(BAREMETAL_SIM) \
		+test=$(1) \
		+mem=$(SOFTWARE_BUILD_DIR)/$(1).mem \
		$(BAREMETAL_PLUSARGS)
endef

$(foreach program,$(BAREMETAL_PROGRAMS),$(eval $(call BAREMETAL_template,$(program))))

# Delegate one image at a time to the ISA build system. This keeps named test
# targets fast while allowing the top-level -j regression to build independent
# assembly programs concurrently.
$(ISA_BUILD_DIR)/rv32ui-%.mem: third_party/riscv-tests/isa/rv32ui/%.S $(ISA_IMAGE_COMMON_DEPS)
	@$(MAKE) -C sw/isa BUILD_DIR=$(ISA_BUILD_DIR) $@

$(ISA_BUILD_DIR)/rv32um-%.mem: third_party/riscv-tests/isa/rv32um/%.S $(ISA_IMAGE_COMMON_DEPS)
	@$(MAKE) -C sw/isa BUILD_DIR=$(ISA_BUILD_DIR) $@

define ISA_template
isa-$(1): $(ISA_BUILD_DIR)/$(1).mem $(BAREMETAL_SIM)
	@echo "[RUN]   isa-$(1)"
	@$(if $(strip $(ISA_TRACE_DIR)),mkdir -p "$(ISA_TRACE_DIR)",:)
	@$(BAREMETAL_SIM) \
		+test=$(1) \
		+mem=$(ISA_BUILD_DIR)/$(1).mem \
		$(if $(strip $(ISA_TRACE_DIR)),+trace=$(ISA_TRACE_DIR)/$(1).csv) \
		$(ISA_PLUSARGS)
endef

$(foreach program,$(ISA_PROGRAMS),$(eval $(call ISA_template,$(program))))

# Each test has its own Verilator object directory. This prevents generated
# model collisions and lets GNU make safely compile independent tests in
# parallel. The executable target is cached until one of its RTL/TB inputs
# changes; the phony test target always executes the resulting simulation.
define TEST_template
$(BUILD_DIR)/$(1)/V$(1): $$($(1)_SRCS) $$($(1)_BUILD_DEPS) Makefile | rtl-check-tools
	@mkdir -p $$(@D)
	@echo "[BUILD] $(1)"
	+@$$(VERILATOR) $$(VERILATOR_TEST_FLAGS) \
		--top-module $(1) \
		--Mdir $$(@D) \
		-o V$(1) \
		$$($(1)_SRCS)

$(1): $(BUILD_DIR)/$(1)/V$(1)
	@echo "[RUN]   $(1)"
	@$(BUILD_DIR)/$(1)/V$(1)
endef

$(foreach test,$(ALL_TESTS),$(eval $(call TEST_template,$(test))))
