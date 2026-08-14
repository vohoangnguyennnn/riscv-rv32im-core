SHELL := /bin/bash

BUILD_DIR ?= /tmp/rv32im-core-isa-$(shell id -u)
CROSS_COMPILE ?= riscv64-unknown-elf-
PYTHON ?= python3

CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf
NM      := $(CROSS_COMPILE)nm

REPO_ROOT := ../..
UPSTREAM  := $(REPO_ROOT)/third_party/riscv-tests
ARCH      := rv32im_zicsr
ABI       := ilp32
TCM_BYTES := 65536

include tests.mk

RV32UI_NAMES := $(addprefix rv32ui-,$(RV32UI_TESTS))
RV32UM_NAMES := $(addprefix rv32um-,$(RV32UM_TESTS))
PROGRAMS := $(RV32UI_NAMES) $(RV32UM_NAMES)

CPPFLAGS := \
	-Ienv \
	-I$(UPSTREAM)/isa/macros/scalar
ASFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medlow \
	-mstrict-align \
	-mno-relax \
	-ffreestanding \
	-fno-common \
	-fno-pic \
	-g3
LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mno-relax \
	-nostdlib \
	-nostartfiles \
	-static \
	-T link.ld \
	-Wl,--build-id=none \
	-Wl,--fatal-warnings

ELFS := $(addprefix $(BUILD_DIR)/,$(addsuffix .elf,$(PROGRAMS)))
MEM_IMAGES := $(ELFS:.elf=.mem)
DISASSEMBLIES := $(ELFS:.elf=.dump)
OBJECTS := $(ELFS:.elf=.o)
BINARIES := $(ELFS:.elf=.bin)

# Keep every debug artifact. GNU make otherwise treats the pattern-generated
# object/binary files as intermediate and may remove them after a build.
.SECONDARY: $(OBJECTS) $(BINARIES) $(ELFS)

.DEFAULT_GOAL := all

.PHONY: all images dumps rv32ui rv32um check-tools check-manifest list clean

all: check-manifest images dumps

images: $(MEM_IMAGES)

dumps: $(DISASSEMBLIES)

rv32ui: $(addprefix $(BUILD_DIR)/,$(addsuffix .mem,$(RV32UI_NAMES)))

rv32um: $(addprefix $(BUILD_DIR)/,$(addsuffix .mem,$(RV32UM_NAMES)))

check-tools:
	@command -v $(CC) >/dev/null 2>&1 || { echo "error: $(CC) not found" >&2; exit 127; }
	@command -v $(OBJCOPY) >/dev/null 2>&1 || { echo "error: $(OBJCOPY) not found" >&2; exit 127; }
	@command -v $(OBJDUMP) >/dev/null 2>&1 || { echo "error: $(OBJDUMP) not found" >&2; exit 127; }
	@command -v $(READELF) >/dev/null 2>&1 || { echo "error: $(READELF) not found" >&2; exit 127; }
	@command -v $(NM) >/dev/null 2>&1 || { echo "error: $(NM) not found" >&2; exit 127; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: $(PYTHON) not found" >&2; exit 127; }

check-manifest:
	@for test_name in $(RV32UI_TESTS) $(RV32UI_OUT_OF_SCOPE_TESTS); do \
		test -f "$(UPSTREAM)/isa/rv32ui/$$test_name.S" || { \
			echo "error: rv32ui manifest source $$test_name.S is missing" >&2; exit 1; \
		}; \
	done
	@for test_name in $(RV32UM_TESTS); do \
		test -f "$(UPSTREAM)/isa/rv32um/$$test_name.S" || { \
			echo "error: rv32um manifest source $$test_name.S is missing" >&2; exit 1; \
		}; \
	done
	@actual=$$(find "$(UPSTREAM)/isa/rv32ui" -maxdepth 1 -name '*.S' \
		-printf '%f\n' | sed 's/\.S$$//' | sort | tr '\n' ' '); \
	expected=$$(printf '%s\n' $(RV32UI_TESTS) $(RV32UI_OUT_OF_SCOPE_TESTS) \
		| sort | tr '\n' ' '); \
	test "$$actual" = "$$expected" || { \
		echo "error: rv32ui manifest does not account for every pinned source" >&2; \
		echo "actual:   $$actual" >&2; \
		echo "expected: $$expected" >&2; \
		exit 1; \
	}
	@actual=$$(find "$(UPSTREAM)/isa/rv32um" -maxdepth 1 -name '*.S' \
		-printf '%f\n' | sed 's/\.S$$//' | sort | tr '\n' ' '); \
	expected=$$(printf '%s\n' $(RV32UM_TESTS) | sort | tr '\n' ' '); \
	test "$$actual" = "$$expected" || { \
		echo "error: rv32um manifest does not account for every pinned source" >&2; \
		echo "actual:   $$actual" >&2; \
		echo "expected: $$expected" >&2; \
		exit 1; \
	}

list:
	@printf '%s\n' $(PROGRAMS)

$(BUILD_DIR)/rv32ui-%.o: $(UPSTREAM)/isa/rv32ui/%.S | check-tools check-manifest
	@mkdir -p $(@D)
	@echo "[AS]    rv32ui-$*"
	@$(CC) $(CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/rv32um-%.o: $(UPSTREAM)/isa/rv32um/%.S | check-tools check-manifest
	@mkdir -p $(@D)
	@echo "[AS]    rv32um-$*"
	@$(CC) $(CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/%.elf: $(BUILD_DIR)/%.o link.ld | check-tools
	@echo "[LINK]  $*"
	@$(CC) $(LDFLAGS) -Wl,-Map,$(BUILD_DIR)/$*.map -o $@ $<
	@$(READELF) -h $@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: $* is not ELF32" >&2; exit 1; \
	}
	@entry=$$($(READELF) -h $@ | awk '/Entry point address:/ { print $$4 }'); \
		test "$$entry" = "0x0" || { \
			echo "error: $* entry is $$entry, expected 0x0" >&2; exit 1; \
		}
	@tohost=$$($(NM) -n $@ | awk '$$3 == "tohost" { print $$1 }'); \
		test "$$tohost" = "0000fffc" || { \
			echo "error: $* tohost is $$tohost, expected 0000fffc" >&2; exit 1; \
		}

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	@echo "[BIN]   $*"
	@$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/%.mem: $(BUILD_DIR)/%.bin $(BUILD_DIR)/%.dump $(REPO_ROOT)/tools/bin_to_memh.py
	@echo "[MEMH]  $*"
	@$(PYTHON) $(REPO_ROOT)/tools/bin_to_memh.py \
		--input $< --output $@ --size $(TCM_BYTES)

$(BUILD_DIR)/%.dump: $(BUILD_DIR)/%.elf
	@echo "[DUMP]  $*"
	@$(OBJDUMP) -d -S -M no-aliases $< > $@

clean:
	@$(RM) -r $(BUILD_DIR)

-include $(addprefix $(BUILD_DIR)/,$(addsuffix .d,$(PROGRAMS)))
