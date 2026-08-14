SHELL := /bin/bash

BUILD_DIR ?= /tmp/rv32im-core-software-$(shell id -u)
CROSS_COMPILE ?= riscv64-unknown-elf-
PYTHON ?= python3

CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf

ARCH      := rv32im_zicsr
ABI       := ilp32
TCM_BYTES := 65536

include tests/programs.mk

PROGRAMS := $(BAREMETAL_PROGRAMS)

CPPFLAGS := -Iinclude
COMMON_FLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mcmodel=medlow \
	-mstrict-align \
	-mno-relax \
	-ffreestanding \
	-fno-common \
	-fno-pic \
	-ffunction-sections \
	-fdata-sections \
	-g3
CFLAGS := $(COMMON_FLAGS) -O2 -std=gnu11 -Wall -Wextra -Werror
ASFLAGS := $(COMMON_FLAGS)
LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mno-relax \
	-nostdlib \
	-nostartfiles \
	-static \
	-T link.ld \
	-Wl,--build-id=none \
	-Wl,--gc-sections \
	-Wl,--fatal-warnings

COMMON_OBJECTS := \
	$(BUILD_DIR)/runtime/crt0.o \
	$(BUILD_DIR)/runtime/trap.o \
	$(BUILD_DIR)/runtime/runtime.o
MEM_IMAGES := $(addprefix $(BUILD_DIR)/,$(addsuffix .mem,$(PROGRAMS)))
DISASSEMBLIES := $(addprefix $(BUILD_DIR)/,$(addsuffix .dump,$(PROGRAMS)))

.DEFAULT_GOAL := all

.PHONY: all images check-tools list clean

all: images $(DISASSEMBLIES)

images: $(MEM_IMAGES)

check-tools:
	@command -v $(CC) >/dev/null 2>&1 || { echo "error: $(CC) not found" >&2; exit 127; }
	@command -v $(OBJCOPY) >/dev/null 2>&1 || { echo "error: $(OBJCOPY) not found" >&2; exit 127; }
	@command -v $(OBJDUMP) >/dev/null 2>&1 || { echo "error: $(OBJDUMP) not found" >&2; exit 127; }
	@command -v $(READELF) >/dev/null 2>&1 || { echo "error: $(READELF) not found" >&2; exit 127; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: $(PYTHON) not found" >&2; exit 127; }

list:
	@printf '%s\n' $(PROGRAMS)

$(BUILD_DIR)/%.o: %.c | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/%.o: %.S | check-tools
	@mkdir -p $(@D)
	@echo "[AS]    $<"
	@$(CC) $(CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

define PROGRAM_template
$(BUILD_DIR)/$(1).elf: $(COMMON_OBJECTS) $(BUILD_DIR)/tests/$(1).o link.ld | check-tools
	@mkdir -p $$(@D)
	@echo "[LINK]  $(1)"
	@$$(CC) $$(LDFLAGS) -Wl,-Map,$$(BUILD_DIR)/$(1).map -o $$@ \
		$$(COMMON_OBJECTS) $$(BUILD_DIR)/tests/$(1).o
	@$$(READELF) -h $$@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: $(1) is not ELF32" >&2; exit 1; \
	}

$(BUILD_DIR)/$(1).bin: $(BUILD_DIR)/$(1).elf
	@echo "[BIN]   $(1)"
	@$$(OBJCOPY) -O binary $$< $$@

$(BUILD_DIR)/$(1).mem: $(BUILD_DIR)/$(1).bin ../tools/bin_to_memh.py
	@echo "[MEMH]  $(1)"
	@$$(PYTHON) ../tools/bin_to_memh.py \
		--input $$< --output $$@ --size $$(TCM_BYTES)

$(BUILD_DIR)/$(1).dump: $(BUILD_DIR)/$(1).elf
	@echo "[DUMP]  $(1)"
	@$$(OBJDUMP) -d -S -M no-aliases $$< > $$@
endef

$(foreach program,$(PROGRAMS),$(eval $(call PROGRAM_template,$(program))))

clean:
	@$(RM) -r $(BUILD_DIR)

-include $(COMMON_OBJECTS:.o=.d)
-include $(addprefix $(BUILD_DIR)/tests/,$(addsuffix .d,$(PROGRAMS)))
