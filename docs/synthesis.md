# Synthesis notes

Yosys 0.33 (git 2584903a060), DATA_WIDTH = 10. Every number below comes from
[`results/synth/summary.md`](../results/synth/summary.md), which `scripts/synth_summary.sh`
extracts from the raw logs in the same directory.

## 1. Flow

```
script scripts/read_rtl.ys              # read_verilog (no -sv), -Irtl
chparam -set USE_RCA <0|1> alu_top      # the ONLY difference between the two runs
script scripts/synth_<flow>.ys          # hierarchy -check -top alu_top, synth..., check -assert, stat
```

| Flow | Script | Output | What the counts mean |
|---|---|---|---|
| generic | `synth -flatten` (split at `fine` to report coarse cells) | Yosys gates `$_AND_`, `$_MUX_`, `$_SDFFE_…` | technology-independent logic size; not area |
| iCE40 | `synth_ice40` (flattens by default) | `SB_LUT4`, `SB_CARRY`, `SB_DFF*` | resource use before place-and-route |
| Xilinx 7 | `synth_xilinx -flatten` | `LUT1–6`, `CARRY4`, `MUXF7/8`, `FDRE` | resource use before place-and-route; not a Vivado result |

`check -assert` passes in every flow. Every log reports 0 warnings.

Two controls separate the adder from the rest of the ALU:

- **adder alone:** `ref_10` (`a + b + cin`) vs `rca_10` (ripple-carry), generic + iCE40, from
  [`scripts/synth_adder.ys`](../scripts/synth_adder.ys);
- **per-unit breakdown:** behavioral ALU synthesized *without* flattening, showing
  where the cells go, from [`scripts/synth_breakdown.ys`](../scripts/synth_breakdown.ys).

### Version- and tool-specific details found during this work

- **Default flattening differs.** `synth_xilinx` doesn't flatten by default and `synth_ice40` does.
  Without `-flatten` the Xilinx statistics are split per module, so `-flatten` is passed
  explicitly to keep the flows comparable.
- **`ltp` is only valid on the generic netlist.** `ltp -noff` (longest topological path)
  only excludes Yosys-internal flip-flops. On the Xilinx netlist it treated `FDRE` as
  logic and printed false "Detected loop" warnings. It is therefore reported for the generic flow only.
- **`proc_rom`.** This Yosys 0.33 pass converts the legal-opcode `case` into a 32×1 ROM during `proc`.
  `synth` maps the ROM back to gates automatically. Only the formal script needs an explicit `memory` pass.
- **Wire arrays become memories.** The first shifter version used `wire [W-1:0] stage [0:W]`,
  and Yosys inferred a `$mem` cell for it. Changing to one packed vector with `+:` part-selects
  removed it. The equivalence proof caught this before synthesis numbers were collected.
- **`#` starts a comment in Yosys scripts**, so section markers in the logs use `log === … ===`.

## 2. Results

| W = 10 | Behavioral `+` | Structural RCA |
|---|---:|---:|
| Coarse `$alu` cells (adder recognized as arithmetic) | 1 | 0 |
| **Generic** total cells | 970 | 949 |
| Generic longest path (`ltp`, cells) | 33 | 42 |
| **iCE40** SB_LUT4 / SB_CARRY / SB_DFF* | 387 / 10 / 15 | 410 / 0 / 15 |
| **Xilinx** LUT / CARRY4 / MUXF7+8 / FDRE | 316 / 3 / 93 / 15 | 311 / 0 / 97 / 15 |
| **Adder alone**, generic cells / longest path | 66 / 12 | 50 / 21 |
| **Adder alone**, iCE40 LUT4 / SB_CARRY | 10 / 10 | 23 / 0 |

Per unit (behavioral, hierarchy kept, 1,053 cells in total):

| Unit | Cells | Share |
|---|---:|---:|
| `alu_shifter` | 464 | 44% |
| `alu_arith` | 230 | 22% |
| `alu_logic` | 197 | 19% |
| `alu_top` (decode, mux, flags, registers) | 165 | 16% |

## 3. Interpretation

**Generic flow.** The behavioral `+` survives as one `$alu` cell. Yosys lowers it through
`_90_lcu` in `techmap.v`, which is a **Brent–Kung parallel-prefix** carry network. The RCA is
already gates, so it stays a ripple chain. Measured on the adder alone, the result is the expected
trade: behavioral uses 32% more cells (66 vs 50) for 43% less depth (12 vs 21 cells). In the
whole ALU the difference shrinks to −21 cells (−2.2%) and +9 levels, because the adder is a small
part of the design.

**iCE40.** `synth_ice40` maps `$alu` onto the dedicated `SB_CARRY` chain: 10 SB_CARRY and 10
LUT4 for the bare adder. The gate-level RCA is not recognized as an adder, so it costs 23 plain
LUT4s and no carry cells, and the whole ALU needs 23 more LUT4s. On this target, writing
`+` is both smaller and lets the tool use the hardware built for addition. No place-and-route
or timing analysis was run, so **no claim is made about which is faster**, although
FPGA carry chains are generally designed to be fast.

**Xilinx 7.** The two variants differ by only 2 cells (485 vs 483). The behavioral version uses
3 CARRY4. The structural version absorbs the ripple logic into 6-input LUTs. At this width
the difference is negligible.

**Flip-flops: 15, not the 16 predicted in the spec.** `negative` is defined as
`result[MSB]` for every legal opcode, and both registers have the same D input, enable and reset,
so Yosys merged them into one flip-flop. The generic netlist contains `assign result[9] = negative;`. This
is a consequence of the flag policy chosen in the spec, not a bug, and the flag costs nothing.

**Where to optimize next.** The shifter is 44% of the logic. SLL, SRL and SRA are three separate
barrel shifters, so sharing one right-shifter through bit reversal is the obvious next
experiment. That will have far more effect than the choice of adder.

## 4. What these numbers do not show

- No timing: there is no Fmax, slack, or critical-path delay. `ltp` counts cells and treats a
  fast carry cell the same as a LUT.
- No area in µm² and no power: no standard-cell library flow was run.
- FPGA counts are before place-and-route and come from Yosys, not vendor tools.
- Results are for W = 10 only. The cells-vs-width trend is not measured.

The `ALU/` directory (a third-party reference design, not part of this project) has qflow
results on the osu035 library. Its 1,081-cell count includes a 10×10 multiplier and comes from a
different flow, so it is not comparable with any number here.

## 5. Reproduce

```sh
make synth              # all flows + controls, regenerates results/synth/summary.md
yosys -p "script scripts/read_rtl.ys; chparam -set USE_RCA 1 alu_top; script scripts/synth_ice40.ys"
```
