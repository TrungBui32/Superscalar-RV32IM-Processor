#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="${1:-sim/build/muldiv_tests}"
mkdir -p "$build_dir"
for width in 4 6 8 32; do
    iverilog -g2012 -s tb_muldiv -Ptb_muldiv.W="$width" \
        -o "$build_dir/unit$width" tests/muldiv/tb_muldiv.sv rtl/core/muldiv_unit.v
    vvp "$build_dir/unit$width"
done
iverilog -g2012 -s tb_muldiv_core -o "$build_dir/core" \
    tests/muldiv/tb_muldiv_core.sv rtl/core/*.v
for slot in 0 1; do
    for stall in 0 1 2; do
        vvp "$build_dir/core" +slot="$slot" +stall="$stall"
    done
done
for stall in 0 1 2; do
    vvp "$build_dir/core" +redirect=1 +stall="$stall"
done
for stall in 0 1 2; do
    vvp "$build_dir/core" +mixed=1 +stall="$stall"
done
iverilog -g2012 -s tb_muldiv_irq -o "$build_dir/irq" \
    tests/muldiv/tb_muldiv_irq.sv rtl/core/*.v
for mode in 0 1; do
    for slot in 0 1; do
        for stalls in 0 1; do
            for arrival in 0 1; do
                vvp "$build_dir/irq" +mode="$mode" +slot="$slot" \
                    +stalls="$stalls" +arrival="$arrival"
            done
        done
    done
done
