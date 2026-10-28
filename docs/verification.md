# Verification notes

Measured with Icarus Verilog 12.0. Logs are in [`results/sim/`](../results/sim/) and
[`results/mutation.log`](../results/mutation.log).

## 1. What "passing" means

`scripts/run_vvp.sh` marks a run as passing only if **both** of these hold:

1. `vvp -N` exits with status 0. The testbench ends with `$finish` on success and `$stop` on
   failure, and `-N` turns `$stop` into exit status 1. This was measured on this machine.
   Without `-N`, `vvp` drops into its interactive prompt and exits 0, which would
   hide failures in automation.
2. The log contains the line `TEST PASSED`. This catches crashes or early exits that never reach the
   summary.

A watchdog also fails the run if the simulation hangs.

`tb_alu` prints `TEST PASSED` only when all of these are true:

- no check mismatches
- no reference-model mismatches against the hand-written golden vectors
- no coverage holes
- at least one cycle was checked

## 2. Testbench structure (`tb/tb_alu.v`)

```
negedge: stimulus drives rst_n, valid_in, a, b, opcode     (X on data when idle)
posedge: DUT samples
posedge: scoreboard computes what the registers must hold after this edge:
            rst_n == 0   -> all zero, valid 0
            valid_in     -> ref_alu(opcode, a, b), valid 1
            otherwise    -> previous values held, valid 0
posedge + 1 ns: compare all 7 DUT outputs with the expectation, every cycle
```

There is no queue because the latency is fixed at one cycle and there is no backpressure. The
testbench needs no SystemVerilog constructs: stimulus and checking are separated by clock
edges, not by clocking blocks.

### Reference model independence

| Quantity | RTL computes it with | Reference model computes it with |
|---|---|---|
| ADD/SUB/INC/DEC/NEG result | one shared `x + y + cin` adder | separate `integer` expressions per op |
| carry / borrow | adder carry-out | integer comparisons (`A + B >= 2^W`, `A >= B`, …) |
| overflow | sign-bit rule on adder inputs | range check of the signed integer result |
| SLT | `sum[MSB] ^ V` of `A − B` | integer `sa < sb` |
| shifts | Verilog `<<`, `>>`, `>>>` | per-bit loop: `r[i] = a[i ∓ amount]` |
| rotates | mod-W staged mux chain | per-bit index `a[(i − amt) mod W]` |
| illegal decode | `case` listing legal codes | `case` with a `default` |

Only the opcode values (`rtl/alu_opcodes.vh`) are shared. A wrong encoding *value* would therefore
go unnoticed, but a wrong decode would not.

The reference model is itself checked. The `B:golden` section contains 34 vectors whose
expected outputs were written by hand from the spec (§3.3). Each one is compared with the reference
model before the transaction is sent to the DUT.

## 3. Test sections

| Section | Content | Transactions (W = 10) |
|---|---|---:|
| D:reset / b2b / gap / reset-mid | reset beats valid, back-to-back, gaps of 1/3/5, mid-stream resets, illegal right after reset | 9 (+ 5 reset cycles) |
| B:golden | 34 spec vectors (overflow, carry, borrow, SLT wrap, SRA sign fill, rotate wrap) | 34 |
| A:directed | all 32 opcodes × 10 × 10 corner operands {0, 1, 2, SMAX, SMIN, SMIN+1, ALL1, ALL1−1, 0101…, 1010…} | 3,200 |
| C:shift | 5 ops × 5 sources × 7 amounts {0, 1, W−1, W, W+1, 2W, 2^W−1}; ROL/ROR for every amount 0…1023 | 2,223 |
| E:random | 20,000 cycles: ~75% valid, ~10% illegal opcodes, 25% corner operands, rare (1/512) random resets | ~15,000 |

The random sequence is reproducible: `$random(seed)` with `+seed=<n>` (default 20261028).

## 4. Event counters (not functional coverage)

Fixed-size integer arrays count, at accepted transactions:

- per-opcode executions
- carry = 1 and carry = 0 for each arithmetic op
- overflow per op, and each direction separately for ADD and SUB
- zero results per op class
- shift-amount bins {0, 1, W−1, W, > W} per shift op
- interface events: reset with `valid_in` high, reset mid-stream, back-to-back, gap = 1, gap ≥ 3, hold after a transaction

Any required counter at zero is reported as a `HOLE` and fails the run.

These counters only record events the testbench author chose in advance. They have no crosses
(for example, "SUB with a borrow *and* immediately after a reset" is not tracked) and cannot reveal
a scenario nobody thought of. They exist to catch a regression where the stimulus silently stops
reaching a case.

W = 10 counts are in [`results/sim/tb_alu_w10_rca0.log`](../results/sim/tb_alu_w10_rca0.log). For
example, ADD overflow occurs 74× (pos+pos→neg) and 110× (neg+neg→pos), and SUB borrows 334×.

## 5. Mutation testing

`scripts/mutation_test.sh` copies `rtl/` to `build/mutants/<name>/` and applies one `sed` edit per
mutant. The script fails if a pattern no longer matches the RTL, so the mutant list cannot silently
go stale. It then runs `tb_alu` (3,000 random cycles) on each mutant.

| Mutant | Failing checks |
|---|---:|
| overflow uses raw `b` instead of the adder input `~b` | 358 |
| SLT without the overflow correction | 51 |
| carry polarity inverted (x86 borrow convention) | 1,114 |
| SRA operand unsigned, so `>>>` is a logical shift | 138 |
| rotator stage constants computed mod W+1 | 2,129 |
| `zero` not gated for illegal opcodes | 1,152 |
| registers load every cycle instead of holding | 745 |
| `valid_out` ignores `valid_in` | 807 |
| reset does not clear `result` | 11 |
| full-adder carry ignores `cin` (`USE_RCA=1`) | 805 |
| RCA ignores carry-in (`USE_RCA=1`) | 712 |

All 11 were detected. The weakest result is "reset does not clear `result`", caught by only 11
checks, because most resets are followed by a new transaction that overwrites `result` anyway.

## 6. Formal equivalence (`scripts/equiv.ys`)

- **Proof 1 (combinational):** a `miter` of `ripple_carry_adder` and `{cout, sum} = a + b + cin`
  at W = 10. `sat -prove` finds no counterexample over all 2^21 inputs.
- **Proof 2 (sequential):** a `miter` of `alu_top` with `USE_RCA=0` and with `USE_RCA=1`.
  - The base case starts both designs in the all-zero state, which is what reset produces.
  - Every register drives an output, so 1-step temporal induction proves the outputs are equal in
    every reachable state.
  - An earlier attempt with independent undefined initial states failed trivially (the two
    designs started in different states), and that is why the base case uses the reset state.
- **Sanity check:** the same script run on the `rca_carry_chain` mutant fails, so the proof
  is not vacuous.
- **Yosys detail:** `proc_rom` turns the 32-entry legal-opcode `case` into a ROM (`$mem_v2`).
  The SAT solver cannot import memories, so the script runs `memory` first to map the ROM back to logic.

## 7. Verilog-2001 compliance

`make lint` runs:

1. **Verilator `-Wall --default-language 1364-2001` on the RTL.** It must be warning-free.
   - `UNUSEDPARAM` is disabled only inside the shared include file, because each module uses a
     subset of the constants.
   - `split_var` on the rotator stage vector prevents a false `UNOPTFLAT` loop report.
2. **Verilator in 2001 mode on the testbenches** (syntax errors only).
3. **`scripts/check_v2001.sh`** on every source file. It flags SystemVerilog keywords and
   tokens (`logic`, `always_ff`, `$urandom`, `$fatal`, `++`, `+=`, `'0`, `$clog2`, …) after
   stripping comments and strings.

Item 3 is needed because both tools let SystemVerilog through in these modes. Measured:
`iverilog -g2001` accepted `logic`, `$urandom` and `$fatal`, and Verilator in 2001 mode accepted `$urandom`.

## 8. Reproduce

```sh
make test                         # 10 simulations
make test SEED=1 NUM_RANDOM=100000
make mutation
make formal
```
