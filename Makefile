# Makefile -- lint, simulation, formal equivalence, mutation testing and
# synthesis for the parameterized Verilog-2001 ALU. `make help` lists targets.

SHELL := /bin/bash

IVERILOG  ?= iverilog
VVP       ?= vvp
YOSYS     ?= yosys
VERILATOR ?= verilator
GTKWAVE   ?= gtkwave

RTL_DIR := rtl
RTL     := $(addprefix $(RTL_DIR)/,full_adder.v ripple_carry_adder.v alu_arith.v \
                                   alu_logic.v alu_shifter.v alu_top.v)
HDRS    := $(RTL_DIR)/alu_opcodes.vh
TBS     := tb/tb_alu.v tb/tb_ripple_carry_adder.v
FORMAL  := formal/equiv_wrappers.v

IVFLAGS := -g2001 -Wall -I$(RTL_DIR)
VLFLAGS := --lint-only --default-language 1364-2001 -I$(RTL_DIR)

BUILD  := build
SIMLOG := results/sim
SYNLOG := results/synth
FMLLOG := results/formal

SEED       ?= 20261028
NUM_RANDOM ?= 20000
ALU_WIDTHS ?= 8 10 16
RCA_WIDTHS ?= 1 4 10 16

.PHONY: all help lint test sim formal mutation synth waves gtkwave clean

all: lint test formal mutation synth

help:
	@echo "make lint       Verilator -Wall (2001 mode) + SystemVerilog token guard"
	@echo "make sim        ALU testbench, DATA_WIDTH=10, both adder configurations"
	@echo "make test       full matrix: ALU at W=$(ALU_WIDTHS) x USE_RCA=0/1, RCA at W=$(RCA_WIDTHS)"
	@echo "make formal     Yosys SAT proofs: RCA == a+b+cin, behavioral ALU == structural ALU"
	@echo "make mutation   inject bugs into a copy of the RTL; every one must be caught"
	@echo "make synth      Yosys generic / iCE40 / Xilinx synthesis + results/synth/summary.md"
	@echo "make waves      short simulation with VCD output (build/tb_alu.vcd)"
	@echo "make gtkwave    open the VCD with the saved signal layout"
	@echo "make all        lint test formal mutation synth"
	@echo "Variables: SEED=$(SEED) NUM_RANDOM=$(NUM_RANDOM)"

# ---------------------------------------------------------------------------
# Lint: RTL must be warning-free under Verilator -Wall; testbenches only need
# to parse as Verilog-2001 (they use delays and system tasks by design).
# ---------------------------------------------------------------------------
lint:
	$(VERILATOR) $(VLFLAGS) -Wall --top-module alu_top -GUSE_RCA=0 $(RTL)
	$(VERILATOR) $(VLFLAGS) -Wall --top-module alu_top -GUSE_RCA=1 $(RTL)
	$(VERILATOR) $(VLFLAGS) -Wall --top-module ripple_carry_adder $(RTL_DIR)/full_adder.v $(RTL_DIR)/ripple_carry_adder.v
	$(VERILATOR) $(VLFLAGS) --timing -Wno-lint -Wno-style --top-module tb_alu $(RTL) tb/tb_alu.v
	$(VERILATOR) $(VLFLAGS) --timing -Wno-lint -Wno-style --top-module tb_ripple_carry_adder $(RTL) tb/tb_ripple_carry_adder.v
	scripts/check_v2001.sh $(RTL) $(HDRS) $(TBS) $(FORMAL)
	@echo "lint: clean"

# ---------------------------------------------------------------------------
# Simulation. Each configuration is its own target so failures are isolated.
# ---------------------------------------------------------------------------
define ALU_SIM
sim_alu_w$(1)_rca$(2): | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -s tb_alu -P tb_alu.DATA_WIDTH=$(1) -P tb_alu.USE_RCA=$(2) \
	    -P tb_alu.NUM_RANDOM=$(NUM_RANDOM) -o $(BUILD)/tb_alu_w$(1)_rca$(2).vvp $(RTL) tb/tb_alu.v
	@scripts/run_vvp.sh $(BUILD)/tb_alu_w$(1)_rca$(2).vvp $(SIMLOG)/tb_alu_w$(1)_rca$(2).log +seed=$(SEED)
ALU_SIMS += sim_alu_w$(1)_rca$(2)
endef

define RCA_SIM
sim_rca_w$(1): | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -s tb_ripple_carry_adder -P tb_ripple_carry_adder.WIDTH=$(1) \
	    -o $(BUILD)/tb_rca_w$(1).vvp $(RTL_DIR)/full_adder.v $(RTL_DIR)/ripple_carry_adder.v tb/tb_ripple_carry_adder.v
	@scripts/run_vvp.sh $(BUILD)/tb_rca_w$(1).vvp $(SIMLOG)/tb_rca_w$(1).log +seed=$(SEED)
RCA_SIMS += sim_rca_w$(1)
endef

$(foreach w,$(ALU_WIDTHS),$(foreach r,0 1,$(eval $(call ALU_SIM,$(w),$(r)))))
$(foreach w,$(RCA_WIDTHS),$(eval $(call RCA_SIM,$(w))))
.PHONY: $(ALU_SIMS) $(RCA_SIMS)

sim: sim_alu_w10_rca0 sim_alu_w10_rca1

test: $(ALU_SIMS) $(RCA_SIMS)
	@echo "test: all $(words $^) simulations passed"

$(BUILD):
	@mkdir -p $(BUILD)

# ---------------------------------------------------------------------------
# Formal equivalence and mutation testing
# ---------------------------------------------------------------------------
formal:
	@mkdir -p $(FMLLOG)
	@$(YOSYS) -q -l $(FMLLOG)/equiv.log scripts/equiv.ys > /dev/null
	@grep -q '^EQUIVALENCE PROVEN' $(FMLLOG)/equiv.log
	@grep -E 'SUCCESS|EQUIVALENCE' $(FMLLOG)/equiv.log

mutation: | $(BUILD)
	@scripts/mutation_test.sh | tee results/mutation.log; exit $${PIPESTATUS[0]}

# ---------------------------------------------------------------------------
# Synthesis: same RTL, same flow, only `chparam -set USE_RCA` differs.
# ---------------------------------------------------------------------------
YS_READ = script scripts/read_rtl.ys

synth:
	@mkdir -p $(SYNLOG)
	@for flow in generic ice40 xilinx; do for rca in 0 1; do \
	    echo "yosys: $$flow USE_RCA=$$rca"; \
	    $(YOSYS) -l $(SYNLOG)/$${flow}_rca$$rca.log \
	        -p "$(YS_READ); chparam -set USE_RCA $$rca alu_top; script scripts/synth_$$flow.ys" \
	        > /dev/null || exit 1; \
	done; done
	@for top in ref_10 rca_10; do \
	    echo "yosys: adder-only $$top"; \
	    $(YOSYS) -l $(SYNLOG)/adder_$$top.log \
	        -p "$(YS_READ); read_verilog $(FORMAL); hierarchy -check -top $$top; script scripts/synth_adder.ys" \
	        > /dev/null || exit 1; \
	done
	@echo "yosys: per-unit breakdown"
	@$(YOSYS) -l $(SYNLOG)/breakdown_rca0.log -p "$(YS_READ); script scripts/synth_breakdown.ys" > /dev/null
	@scripts/synth_summary.sh

# ---------------------------------------------------------------------------
# Waveforms
# ---------------------------------------------------------------------------
waves: | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -s tb_alu -P tb_alu.NUM_RANDOM=200 -o $(BUILD)/tb_alu_waves.vvp $(RTL) tb/tb_alu.v
	$(VVP) -N $(BUILD)/tb_alu_waves.vvp +vcd=$(BUILD)/tb_alu.vcd +seed=$(SEED) | tail -n 2

gtkwave: waves
	$(GTKWAVE) $(BUILD)/tb_alu.vcd scripts/tb_alu.gtkw &

clean:
	rm -rf $(BUILD)
