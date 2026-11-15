# OpenROAD-flow-scripts design config for the bare rv32_core (no TCM).
# Run through the repo Makefile: `make asic-synth`, ..., `make asic`.
ASIC_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPO_ROOT := $(patsubst %/,%,$(dir $(ASIC_DIR)))

export DESIGN_NAME     = asic_core_top
export DESIGN_NICKNAME = rv32im_core
export PLATFORM        = sky130hd

# Same RTL list as simulation (files/core.f), plus the flat-port wrapper.
export VERILOG_FILES = $(addprefix $(REPO_ROOT)/,$(shell sed -e '/^[[:space:]]*\#/d' -e '/^[[:space:]]*$$/d' $(REPO_ROOT)/files/core.f)) \
                       $(ASIC_DIR)/asic_core_top.sv
export SYNTH_HDL_FRONTEND = slang
# Keep the RTL state encoding of the IF/LSU FSMs. Yosys would otherwise re-encode
# them (e.g. 2-bit -> one-hot), and LEC, which pairs registers by name, would
# compare bits with different meanings. Area cost is negligible for FSMs this small.
export SYNTH_ARGS = -nofsm
export SDC_FILE = $(ASIC_DIR)/constraint.sdc

# Die size is derived from cell area: cells fill 40% of the core box, the rest
# is room for routing, buffers and clock tree.
export CORE_UTILIZATION = 40
