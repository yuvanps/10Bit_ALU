#!/usr/bin/env bash
# check_v2001.sh <files...>
#
# Rejects SystemVerilog constructs that `iverilog -g2001` and
# `verilator --default-language 1364-2001` still accept (both were measured to
# let some through, e.g. $urandom). Comments are stripped first so prose such
# as "operation class" is not flagged.
set -u
keywords='logic|bit|byte|shortint|int|longint|always_comb|always_ff|always_latch|typedef|enum|struct|union|interface|modport|package|import|class|virtual|assert|assume|cover|covergroup|property|sequence|unique|priority|automatic'
tokens='\$urandom|\$urandom_range|\$fatal|\$error|\$warning|\$info|\+\+|--|\+=|-=|\*=|/=|\$clog2|'"'"'\{|(^|[^0-9A-Za-z_])'"'"'[01xXzZ]'

status=0
for f in "$@"; do
    # Drop // comments, then the contents of string literals.
    stripped=$(sed -e 's://.*$::' -e 's/"[^"]*"/""/g' "$f")
    hits=$(printf '%s\n' "$stripped" | grep -nwE "$keywords"; \
           printf '%s\n' "$stripped" | grep -nE "$tokens")
    if [ -n "$hits" ]; then
        echo "$f: SystemVerilog-only construct(s):"
        printf '%s\n' "$hits" | sed 's/^/    line /'
        status=1
    fi
done
[ $status -eq 0 ] && echo "check_v2001: $# files clean"
exit $status
