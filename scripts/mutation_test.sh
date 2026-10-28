#!/usr/bin/env bash
# mutation_test.sh -- proves the testbench can fail.
#
# Each mutant copies rtl/ into build/mutants/<name>/, injects one realistic
# bug with sed, and runs tb_alu against it. A mutant is KILLED when the
# testbench fails (good) and SURVIVES when it passes (a verification gap).
# The script exits nonzero if any mutant survives or a sed pattern no longer
# matches the RTL (so the mutant list cannot silently rot).
set -u
cd "$(dirname "$0")/.."

SRCS="full_adder.v ripple_carry_adder.v alu_arith.v alu_logic.v alu_shifter.v alu_top.v"
NUM_RANDOM=${NUM_RANDOM:-3000}
survived=0; broken=0

# name @ use_rca @ file @ sed expression (basic regex) @ description
MUTANTS=(
"sub_overflow_raw_b@0@alu_arith.v@s/(x\[MSB\] == y\[MSB\]) && (sum\[MSB\] != x\[MSB\])/(a[MSB] == b[MSB]) \&\& (sum[MSB] != a[MSB])/@overflow uses raw b instead of the adder input ~b"
"slt_no_ovf_fix@0@alu_arith.v@s/sum\[MSB\] ^ adder_overflow;/sum[MSB];/@SLT uses the sign bit without the overflow correction"
"carry_is_borrow@0@alu_arith.v@s/carry    = cout;/carry    = ~cout;/@carry flag polarity inverted (x86 borrow convention)"
"sra_logical@0@alu_shifter.v@s/\\\$signed(a) >>> b/a >>> b/@SRA operand unsigned, so >>> is a logical shift"
"rotate_stage_wrong@0@alu_shifter.v@s/pow2_mod(k, DATA_WIDTH)/pow2_mod(k, DATA_WIDTH + 1)/@rotator stage constants computed mod W+1"
"zero_on_illegal@0@alu_top.v@s/wire next_zero     = legal & /wire next_zero     = /@zero flag not gated for illegal opcodes"
"no_hold_on_idle@0@alu_top.v@s/            if (valid_in) begin/            begin/@registers load every cycle instead of holding"
"valid_stuck@0@alu_top.v@s/valid_out <= valid_in;/valid_out <= 1'b1;/@valid_out ignores valid_in"
"reset_keeps_result@0@alu_top.v@/if (!rst_n) begin/,/end else begin/{/result     <=/d}@reset does not clear result"
"rca_carry_chain@1@full_adder.v@s/assign cout = g | (p & cin);/assign cout = g | p;/@full-adder carry ignores cin"
"rca_cin_dropped@1@ripple_carry_adder.v@s/assign c\[0\] = cin;/assign c[0] = 1'b0;/@RCA ignores carry-in (breaks SUB/INC/NEG)"
)

printf '%-20s %-9s %s\n' "mutant" "verdict" "injected bug"
for m in "${MUTANTS[@]}"; do
    IFS='@' read -r name rca file expr desc <<< "$m"
    dir=build/mutants/$name
    rm -rf "$dir"; mkdir -p "$dir"
    cp rtl/*.v rtl/*.vh "$dir"/
    sed -i "$expr" "$dir/$file"
    if cmp -s "rtl/$file" "$dir/$file"; then
        printf '%-20s %-9s %s\n' "$name" "BROKEN" "sed pattern did not match $file"
        broken=$((broken + 1)); continue
    fi
    files=""; for s in $SRCS; do files="$files $dir/$s"; done
    if ! iverilog -g2001 -I"$dir" -s tb_alu -P tb_alu.USE_RCA="$rca" \
            -P tb_alu.NUM_RANDOM="$NUM_RANDOM" -o "$dir/tb.vvp" $files tb/tb_alu.v \
            > "$dir/compile.log" 2>&1; then
        verdict="KILLED"; how="(compile error)"
    elif vvp -N "$dir/tb.vvp" > "$dir/sim.log" 2>&1 && grep -q '^TEST PASSED' "$dir/sim.log"; then
        verdict="SURVIVED"; how=""; survived=$((survived + 1))
    else
        verdict="KILLED"
        how="($(grep -m1 -oE '[0-9]+ check failures' "$dir/sim.log"))"
    fi
    printf '%-20s %-9s %s %s\n' "$name" "$verdict" "$desc" "$how"
done

total=${#MUTANTS[@]}
echo "mutants: $total, killed: $((total - survived - broken)), survived: $survived, broken: $broken"
[ $survived -eq 0 ] && [ $broken -eq 0 ]
