#!/usr/bin/env bash
# Logic equivalence check (eqy, oss-cad-suite): RTL (gold) vs synthesized
# netlist (gate). eqy pairs registers by name and proves every partition of
# combinational logic between them equal, so no test vectors are needed.
# Usage: asic/run_lec.sh <netlist.v> <cells.v>
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
netlist=$(realpath "$1") cells=$(realpath "$2")
work=$repo/build/asic/lec
mkdir -p "$work"
rtl=$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$repo/files/core.f" | sed "s|^|$repo/|" | tr '\n' ' ')

cat > "$work/core.eqy" <<EOF
[options]
splitnets on

[gold]
plugin -i slang
read_slang -D SYNTHESIS --ignore-assertions --top asic_core_top $rtl $repo/asic/asic_core_top.sv
prep -top asic_core_top
flatten
memory_map
# Synthesis removed flops that can never leave their reset value (e.g. the
# masked mcause_q[30:5]); apply the same reset-based optimisation to the gold
# side so both have the same state elements to pair. wreduce narrows word-level
# muxes whose upper bits are constant (as synthesis does), so `opt`/opt_dff can
# see those D bits fold to the reset constant.
# No opt_dff -sat: that also removes flops synthesis kept (e.g. div iter_q[5]).
wreduce
opt
# The remaining reset-constant bits sit behind CSR write masks (WARL zero bits of
# mcause/mie/mstatus, fixed cause bits of the LSU exception). A SAT check proves
# they never leave reset; it is limited to these registers so it cannot remove
# flops synthesis kept elsewhere.
opt_dff -sat w:u_core.u_csr_file.mcause_q w:u_core.u_csr_file.mie_q w:u_core.u_csr_file.mstatus_q w:u_core.u_lsu.exception_q %u %u %u %ci1:+[Q]
opt
opt_clean
# Keep only flop outputs as match points: internal combinational names may be
# legally restructured by synthesis and must not be compared one-to-one.
rename -hide t:\$*dff* %co x:* %% w:* %D

[gate]
read_verilog $cells
read_verilog $netlist
prep -top asic_core_top
flatten
# Drop the now-unused cell model modules (incl. power-only boxes like decap).
hierarchy -top asic_core_top -purge_lib
opt_clean

[match asic_core_top]
# These registers drive an output port (assign x_o = x_q) that the parent wires
# to a net of its own, so one net has three names. The RTL keeps the _q name,
# synthesis kept the parent's net name: tell eqy they are the same register.
gold-match /u_core\.u_csr_file\.mtvec_q\[([0-9]+)\]/ u_core.csr_mtvec[\1]
gold-match /u_core\.u_csr_file\.mepc_q\[([0-9]+)\]/ u_core.csr_mepc[\1]
gold-match /u_core\.u_ex_stage\.u_div_unit\.result_q\[([0-9]+)\]/ u_core.u_ex_stage.div_result[\1]
gold-match /u_core\.u_ex_stage\.u_mul_unit\.result_q\[([0-9]+)\]/ u_core.u_ex_stage.mul_result[\1]
gold-match u_core.u_pipeline_ctrl.trap_drain_q u_core.trap_drain

[collect *]
# Proving the 31x32 register file as one partition is much faster.
group *u_regfile.regs*
# Bus request outputs are combinational functions of IF/LSU state that the core
# also uses internally. Cutting there turns them into free inputs and lets the
# solver pick impossible combinations (e.g. LSU busy but valid low); bind keeps
# their driving logic inside each consuming partition instead.
bind imem_req_*
bind dmem_req_*

[strategy sby]
use sby
depth 2
engine smtbmc bitwuzla
EOF

cd "$work"
eqy -f -j "$(nproc)" core.eqy
