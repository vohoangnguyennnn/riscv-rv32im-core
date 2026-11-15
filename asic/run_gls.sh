#!/usr/bin/env bash
# Zero-delay gate-level simulation (Questa, 4-state) of the synthesized core.
# Runs every given memory image on the RTL and on the netlist with the same
# testbench and requires PASS on both with identical cycle counts.
# Usage: asic/run_gls.sh <netlist.v> <cells.v> <image.mem>...
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
netlist=$(realpath "$1") cells=$(realpath "$2")
shift 2
images=()
for image in "$@"; do images+=("$(realpath "$image")"); done
set -- "${images[@]}"
work=$repo/build/asic/gls
mkdir -p "$work"
cd "$work"

core_rtl=$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$repo/files/core.f" | sed "s|^|$repo/|")

build() { # <lib> <sources...>
  local lib=$1; shift
  [ -d "$lib" ] || vlib "$lib" >/dev/null
  vlog -quiet -sv -mfcu -work "$lib" -suppress 2583 "$@" > "$lib.compile.log" 2>&1 \
    || { cat "$lib.compile.log"; exit 1; }
}

echo "[GLS] compile RTL reference"
# shellcheck disable=SC2086
build rtl $core_rtl "$repo/asic/asic_core_top.sv" "$repo/rtl/soc/rv32_tcm.sv" "$repo/asic/tb_gls.sv"
echo "[GLS] compile gate-level netlist + sky130 cell models"
build gate "$repo/rtl/core/rv32_mem_if.sv" "$repo/rtl/soc/rv32_tcm.sv" "$cells" "$netlist" "$repo/asic/tb_gls.sv"

run() { # <lib> <image> <name> -> prints cycle count or FAIL
  local out
  # 7061: testbench preloads TCM memory (same waiver as the repo Questa flow).
  # 14408: Starter Edition capacity note (netlist > 5000 instances; slower, still correct).
  # +initreg+0: every flop powers up 0, like an FPGA after configuration. Without
  # it the IF/LSU reset-drain logic keeps power-on X state (see asic/README.md);
  # GLS_INIT= (empty) runs the pessimistic power-on check instead.
  out=$(vsim -c -quiet -suppress 7061,14408 ${GLS_INIT-"-voptargs=+initreg+0"} -lib "$1" tb_gls +mem="$2" +test="$3" -do "run -all; quit -f" 2>&1 | tee "$1.$3.log")
  grep -oP 'tb_gls: PASS \S+ \(\K[0-9]+' <<<"$out" || echo FAIL
}

printf '%-18s %10s %10s  %s\n' test rtl_cycles gls_cycles result
fails=0
for image in "$@"; do
  name=$(basename "$image" .mem)
  r=$(run rtl "$image" "$name")
  g=$(run gate "$image" "$name")
  if [[ $r != FAIL && $r == "$g" ]]; then verdict=MATCH; else verdict=MISMATCH; fails=$((fails + 1)); fi
  printf '%-18s %10s %10s  %s\n' "$name" "$r" "$g" "$verdict"
done
echo "[GLS] $(( $# - fails ))/$# images match (logs in $work)"
[ "$fails" -eq 0 ]
