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

PROGRAMS := $(BAREMETAL_PROGRAMS) $(BENCHMARK_PROGRAMS)

COREMARK_DIR := ../third_party/coremark
COREMARK_PORT_DIR := coremark
COREMARK_ITERATIONS ?= 0
COREMARK_PROGRAMS := coremark_performance coremark_validation
COREMARK_SOURCES := \
	$(COREMARK_DIR)/core_list_join.c \
	$(COREMARK_DIR)/core_main.c \
	$(COREMARK_DIR)/core_matrix.c \
	$(COREMARK_DIR)/core_state.c \
	$(COREMARK_DIR)/core_util.c \
	$(COREMARK_PORT_DIR)/core_portme.c
COREMARK_HEADERS := \
	$(COREMARK_DIR)/coremark.h \
	$(COREMARK_PORT_DIR)/core_portme.h \
	include/baremetal.h
COREMARK_CPPFLAGS := \
	-Iinclude \
	-I$(COREMARK_PORT_DIR) \
	-I$(COREMARK_DIR) \
	-DTOTAL_DATA_SIZE=2000 \
	-DITERATIONS=$(COREMARK_ITERATIONS)
COREMARK_MEM_IMAGES := \
	$(addprefix $(BUILD_DIR)/,$(addsuffix .mem,$(COREMARK_PROGRAMS)))
COREMARK_DISASSEMBLIES := \
	$(addprefix $(BUILD_DIR)/,$(addsuffix .dump,$(COREMARK_PROGRAMS)))

FREERTOS_DIR := ../third_party/freertos-kernel
FREERTOS_APP_DIR := freertos
FREERTOS_PROGRAM := freertos_demo
FREERTOS_CPU_CLOCK_HZ ?= 75000000
FREERTOS_BLINK_PERIOD_MS ?= 2
FREERTOS_CPPFLAGS := \
	-Iinclude \
	-I$(FREERTOS_APP_DIR)/include \
	-I$(FREERTOS_APP_DIR) \
	-I$(FREERTOS_DIR)/include \
	-I$(FREERTOS_DIR)/portable/GCC/RISC-V \
	-DFREERTOS_CPU_CLOCK_HZ=$(FREERTOS_CPU_CLOCK_HZ) \
	-DFREERTOS_BLINK_PERIOD_MS=$(FREERTOS_BLINK_PERIOD_MS)
FREERTOS_PROJECT_CFLAGS = \
	$(COMMON_FLAGS) -O2 -std=gnu11 -Wall -Wextra -Werror -fno-builtin
FREERTOS_KERNEL_CFLAGS = \
	$(COMMON_FLAGS) -O2 -std=gnu11 -Wall -Wextra -fno-builtin
FREERTOS_LDFLAGS := \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-mno-relax \
	-nostdlib \
	-nostartfiles \
	-static \
	-T $(FREERTOS_APP_DIR)/link.ld \
	-Wl,--build-id=none \
	-Wl,--gc-sections \
	-Wl,--fatal-warnings
FREERTOS_OBJECTS := \
	$(BUILD_DIR)/freertos/startup.o \
	$(BUILD_DIR)/freertos/demo.o \
	$(BUILD_DIR)/freertos/platform.o \
	$(BUILD_DIR)/bsp/rv32_soc.o \
	$(BUILD_DIR)/freertos-kernel/tasks.o \
	$(BUILD_DIR)/freertos-kernel/list.o \
	$(BUILD_DIR)/freertos-kernel/port.o \
	$(BUILD_DIR)/freertos-kernel/portASM.o
FREERTOS_HEADERS := \
	$(wildcard $(FREERTOS_DIR)/include/*.h) \
	$(FREERTOS_DIR)/portable/GCC/RISC-V/portContext.h \
	$(FREERTOS_DIR)/portable/GCC/RISC-V/portmacro.h \
	$(wildcard $(FREERTOS_APP_DIR)/include/*.h) \
	$(FREERTOS_APP_DIR)/FreeRTOSConfig.h \
	$(FREERTOS_APP_DIR)/freertos_risc_v_chip_specific_extensions.h \
	include/freertos_demo.h \
	include/rv32_soc.h

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

.PHONY: all images baremetal-images freertos-check freertos-images \
	coremark-check coremark-images coremark-force check-tools list clean

all: baremetal-images freertos-images

baremetal-images: images $(DISASSEMBLIES)

images: $(MEM_IMAGES)

freertos-check:
	@echo "[CHECK] FreeRTOS Kernel V11.3.0 upstream source hashes"
	@cd $(FREERTOS_DIR) && sha256sum -c SOURCE.sha256

freertos-images: freertos-check \
	$(BUILD_DIR)/$(FREERTOS_PROGRAM).mem \
	$(BUILD_DIR)/$(FREERTOS_PROGRAM).dump

coremark-check:
	@echo "[CHECK] CoreMark upstream source hashes"
	@cd $(COREMARK_DIR) && sha256sum -c SOURCE.sha256

coremark-images: coremark-check $(COREMARK_MEM_IMAGES) $(COREMARK_DISASSEMBLIES)

coremark-force:

check-tools:
	@command -v $(CC) >/dev/null 2>&1 || { echo "error: $(CC) not found" >&2; exit 127; }
	@command -v $(OBJCOPY) >/dev/null 2>&1 || { echo "error: $(OBJCOPY) not found" >&2; exit 127; }
	@command -v $(OBJDUMP) >/dev/null 2>&1 || { echo "error: $(OBJDUMP) not found" >&2; exit 127; }
	@command -v $(READELF) >/dev/null 2>&1 || { echo "error: $(READELF) not found" >&2; exit 127; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "error: $(PYTHON) not found" >&2; exit 127; }

list:
	@printf '%s\n' $(PROGRAMS) $(FREERTOS_PROGRAM)

$(BUILD_DIR)/%.o: %.c | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/%.o: %.S | check-tools
	@mkdir -p $(@D)
	@echo "[AS]    $<"
	@$(CC) $(CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos/startup.o: freertos/startup.S $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[AS]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos/demo.o: freertos/demo.c $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(FREERTOS_PROJECT_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos/platform.o: freertos/platform.c $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(FREERTOS_PROJECT_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/bsp/rv32_soc.o: bsp/rv32_soc.c include/rv32_soc.h | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) -Iinclude $(FREERTOS_PROJECT_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos-kernel/tasks.o: $(FREERTOS_DIR)/tasks.c $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(FREERTOS_KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos-kernel/list.o: $(FREERTOS_DIR)/list.c $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(FREERTOS_KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos-kernel/port.o: $(FREERTOS_DIR)/portable/GCC/RISC-V/port.c $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[CC]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(FREERTOS_KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/freertos-kernel/portASM.o: $(FREERTOS_DIR)/portable/GCC/RISC-V/portASM.S $(FREERTOS_HEADERS) | check-tools
	@mkdir -p $(@D)
	@echo "[AS]    $<"
	@$(CC) $(FREERTOS_CPPFLAGS) $(ASFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/$(FREERTOS_PROGRAM).elf: $(FREERTOS_OBJECTS) $(FREERTOS_APP_DIR)/link.ld | check-tools
	@mkdir -p $(@D)
	@echo "[LINK]  $(FREERTOS_PROGRAM)"
	@$(CC) $(FREERTOS_LDFLAGS) -Wl,-Map,$(BUILD_DIR)/$(FREERTOS_PROGRAM).map \
		-o $@ $(FREERTOS_OBJECTS) -lgcc
	@$(READELF) -h $@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: $(FREERTOS_PROGRAM) is not ELF32" >&2; exit 1; \
	}

$(BUILD_DIR)/$(FREERTOS_PROGRAM).bin: $(BUILD_DIR)/$(FREERTOS_PROGRAM).elf
	@echo "[BIN]   $(FREERTOS_PROGRAM)"
	@$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/$(FREERTOS_PROGRAM).mem: $(BUILD_DIR)/$(FREERTOS_PROGRAM).bin ../tools/bin_to_memh.py
	@echo "[MEMH]  $(FREERTOS_PROGRAM)"
	@$(PYTHON) ../tools/bin_to_memh.py \
		--input $< --output $@ --size $(TCM_BYTES)

$(BUILD_DIR)/$(FREERTOS_PROGRAM).dump: $(BUILD_DIR)/$(FREERTOS_PROGRAM).elf
	@echo "[DUMP]  $(FREERTOS_PROGRAM)"
	@$(OBJDUMP) -d -S -M no-aliases $< > $@

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

# Compile the five upstream sources and the platform port with one identical
# flag set, as required by the CoreMark run and reporting rules. Runtime/startup
# objects use the same COMMON_FLAGS/CFLAGS and are linked without libc.
$(BUILD_DIR)/coremark_performance.elf: coremark-force $(COMMON_OBJECTS) $(COREMARK_SOURCES) $(COREMARK_HEADERS) link.ld | check-tools
	@mkdir -p $(@D)
	@echo "[LINK]  coremark_performance"
	@$(CC) $(COREMARK_CPPFLAGS) $(CFLAGS) -DPERFORMANCE_RUN=1 \
		$(LDFLAGS) -Wl,-Map,$(BUILD_DIR)/coremark_performance.map -o $@ \
		$(COMMON_OBJECTS) $(COREMARK_SOURCES)
	@$(READELF) -h $@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: coremark_performance is not ELF32" >&2; exit 1; \
	}

$(BUILD_DIR)/coremark_validation.elf: coremark-force $(COMMON_OBJECTS) $(COREMARK_SOURCES) $(COREMARK_HEADERS) link.ld | check-tools
	@mkdir -p $(@D)
	@echo "[LINK]  coremark_validation"
	@$(CC) $(COREMARK_CPPFLAGS) $(CFLAGS) -DVALIDATION_RUN=1 \
		$(LDFLAGS) -Wl,-Map,$(BUILD_DIR)/coremark_validation.map -o $@ \
		$(COMMON_OBJECTS) $(COREMARK_SOURCES)
	@$(READELF) -h $@ | grep -q 'Class:[[:space:]]*ELF32' || { \
		echo "error: coremark_validation is not ELF32" >&2; exit 1; \
	}

define COREMARK_IMAGE_template
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

$(foreach program,$(COREMARK_PROGRAMS),$(eval $(call COREMARK_IMAGE_template,$(program))))

clean:
	@$(RM) -r $(BUILD_DIR)

-include $(COMMON_OBJECTS:.o=.d)
-include $(addprefix $(BUILD_DIR)/tests/,$(addsuffix .d,$(PROGRAMS)))
-include $(FREERTOS_OBJECTS:.o=.d)
