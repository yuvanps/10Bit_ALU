#!/usr/bin/env bash
# run_vvp.sh <compiled.vvp> <logfile> [plusargs...]
#
# Runs an Icarus simulation and decides pass/fail with two independent checks:
#   1. exit status -- `vvp -N` makes the testbench's $stop exit with status 1;
#   2. the "TEST PASSED" sentinel line must be present in the log.
# Either one failing fails the run (e.g. a crash before the summary prints).
set -u
vvp_file=$1; log=$2; shift 2
mkdir -p "$(dirname "$log")"

vvp -N "$vvp_file" "$@" > "$log" 2>&1
status=$?
summary=$(grep -E '^(cycles checked|vectors) ' "$log" | tail -n 1)

if [ "$status" -eq 0 ] && grep -q '^TEST PASSED' "$log"; then
    printf 'PASS  %-34s %s\n' "$(basename "$log" .log)" "$summary"
else
    printf 'FAIL  %-34s exit=%s  see %s\n' "$(basename "$log" .log)" "$status" "$log"
    grep -E '^(FAIL|MODEL FAIL|  HOLE|TEST FAILED)' "$log" | head -n 15
    exit 1
fi
