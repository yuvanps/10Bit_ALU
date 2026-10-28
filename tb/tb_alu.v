`timescale 1ns / 1ps

// tb_alu -- self-checking Verilog-2001 testbench for alu_top.
//
// Structure
//   * Stimulus is driven on the falling clock edge; the DUT samples on the
//     rising edge, so testbench and DUT never race.
//   * A scoreboard (always @(posedge clk)) models the output registers: it
//     works out what valid_out/result/flags must be after every edge
//     (reset, accept, or hold) and checks the DUT 1 ns later -- on EVERY
//     cycle, not only on transaction cycles. That checks latency, valid
//     timing and hold behavior with the same code.
//   * ref_alu() is an independent reference model. It uses integer
//     arithmetic with range checks for overflow and bit-by-bit loops for
//     shifts/rotates; it shares nothing with the RTL except the opcode values.
//
// Pass/fail
//   Ends with "TEST PASSED" + $finish, or "TEST FAILED" + $stop. Run under
//   `vvp -N`, which turns $stop into exit status 1 (Verilog-2001 $finish
//   cannot set an exit code).
//
// Plusargs
//   +seed=<n>       random seed (default SEED)
//   +vcd=<file>     write a VCD waveform
//
// Limits: the reference model uses 32-bit integers, so DATA_WIDTH <= 30.
module tb_alu;
    parameter DATA_WIDTH = 10;
    parameter USE_RCA    = 0;
    parameter NUM_RANDOM = 20000;
    parameter SEED       = 20261028;
    parameter MAX_REPORT = 20;      // detailed failure messages to print

    `include "alu_opcodes.vh"

    localparam W = DATA_WIDTH;
    localparam [W-1:0] ZERO = {W{1'b0}};
    localparam [W-1:0] ONE  = {{(W-1){1'b0}}, 1'b1};
    localparam [W-1:0] ALL1 = {W{1'b1}};
    localparam [W-1:0] SMAX = {1'b0, {(W-1){1'b1}}};   // largest positive
    localparam [W-1:0] SMIN = {1'b1, {(W-1){1'b0}}};   // most negative

    // Packed expectation vector: {illegal, negative, zero, overflow, carry, result}
    localparam VW = W + 5;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    reg          clk;
    reg          rst_n;
    reg          valid_in;
    reg  [W-1:0] a;
    reg  [W-1:0] b;
    reg  [4:0]   opcode;
    wire         valid_out;
    wire [W-1:0] result;
    wire         carry, overflow, zero, negative, illegal_op;

    alu_top #(
        .DATA_WIDTH (W),
        .USE_RCA    (USE_RCA)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .a          (a),
        .b          (b),
        .opcode     (opcode),
        .valid_out  (valid_out),
        .result     (result),
        .carry      (carry),
        .overflow   (overflow),
        .zero       (zero),
        .negative   (negative),
        .illegal_op (illegal_op)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Reference model
    // ------------------------------------------------------------------
    // Signed value of a W-bit pattern as an integer.
    function integer to_signed;
        input [W-1:0] v;
        begin
            if (v[W-1])
                to_signed = v - (1 << W);
            else
                to_signed = v;
        end
    endfunction

    function signed_out_of_range;
        input integer v;
        begin
            signed_out_of_range = (v > ((1 << (W-1)) - 1)) || (v < -(1 << (W-1)));
        end
    endfunction

    function [VW-1:0] ref_alu;
        input [4:0]   op;
        input [W-1:0] ra;
        input [W-1:0] rb;
        integer ua, ub, sa, sb, full, sfull, amt, i;
        reg [W-1:0] r;
        reg c, v, ill, z, n;
        begin
            ua = ra;                // zero-extended into a 32-bit integer
            ub = rb;
            sa = to_signed(ra);
            sb = to_signed(rb);
            r = ZERO; c = 1'b0; v = 1'b0; ill = 1'b0;
            case (op)
                OP_ADD: begin
                    full = ua + ub;     r = full;   c = (full >= (1 << W));
                    sfull = sa + sb;    v = signed_out_of_range(sfull);
                end
                OP_SUB: begin
                    full = ua - ub;     r = full;   c = (ua >= ub);     // 1 = no borrow
                    sfull = sa - sb;    v = signed_out_of_range(sfull);
                end
                OP_INC: begin
                    full = ua + 1;      r = full;   c = (full >= (1 << W));
                    sfull = sa + 1;     v = signed_out_of_range(sfull);
                end
                OP_DEC: begin
                    full = ua - 1;      r = full;   c = (ua >= 1);
                    sfull = sa - 1;     v = signed_out_of_range(sfull);
                end
                OP_NEG: begin
                    full = 0 - ua;      r = full;   c = (ua == 0);
                    sfull = 0 - sa;     v = signed_out_of_range(sfull);
                end
                OP_SLTU: r = (ua < ub) ? ONE : ZERO;
                OP_SLT:  r = (sa < sb) ? ONE : ZERO;
                OP_EQ:   r = (ua == ub) ? ONE : ZERO;

                OP_AND:  for (i = 0; i < W; i = i + 1) r[i] = ra[i] & rb[i];
                OP_OR:   for (i = 0; i < W; i = i + 1) r[i] = ra[i] | rb[i];
                OP_XOR:  for (i = 0; i < W; i = i + 1) r[i] = ra[i] ^ rb[i];
                OP_NOT:  for (i = 0; i < W; i = i + 1) r[i] = !ra[i];
                OP_NAND: for (i = 0; i < W; i = i + 1) r[i] = !(ra[i] & rb[i]);
                OP_NOR:  for (i = 0; i < W; i = i + 1) r[i] = !(ra[i] | rb[i]);
                OP_XNOR: for (i = 0; i < W; i = i + 1) r[i] = (ra[i] == rb[i]);

                // Shifts: result bit i comes from source bit i -/+ amount.
                OP_SLL:
                    for (i = 0; i < W; i = i + 1)
                        if (i - ub >= 0) r[i] = ra[i - ub];
                OP_SRL:
                    for (i = 0; i < W; i = i + 1)
                        if (i + ub < W) r[i] = ra[i + ub];
                OP_SRA:
                    for (i = 0; i < W; i = i + 1)
                        if (i + ub < W) r[i] = ra[i + ub];
                        else            r[i] = ra[W-1];
                OP_ROL: begin
                    amt = ub % W;
                    for (i = 0; i < W; i = i + 1) r[i] = ra[(i - amt + W) % W];
                end
                OP_ROR: begin
                    amt = ub % W;
                    for (i = 0; i < W; i = i + 1) r[i] = ra[(i + amt) % W];
                end

                OP_PASSA: r = ra;
                OP_PASSB: r = rb;
                OP_CLR:   r = ZERO;
                default:  ill = 1'b1;
            endcase
            z = !ill && (r == ZERO);
            n = !ill && r[W-1];
            ref_alu = {ill, n, z, v, c, r};
        end
    endfunction

    function [8*5-1:0] mnemonic;
        input [4:0] op;
        begin
            case (op)
                OP_ADD:   mnemonic = "ADD";   OP_SUB:   mnemonic = "SUB";
                OP_INC:   mnemonic = "INC";   OP_DEC:   mnemonic = "DEC";
                OP_NEG:   mnemonic = "NEG";   OP_SLTU:  mnemonic = "SLTU";
                OP_SLT:   mnemonic = "SLT";   OP_EQ:    mnemonic = "EQ";
                OP_AND:   mnemonic = "AND";   OP_OR:    mnemonic = "OR";
                OP_XOR:   mnemonic = "XOR";   OP_NOT:   mnemonic = "NOT";
                OP_NAND:  mnemonic = "NAND";  OP_NOR:   mnemonic = "NOR";
                OP_XNOR:  mnemonic = "XNOR";  OP_SLL:   mnemonic = "SLL";
                OP_SRL:   mnemonic = "SRL";   OP_SRA:   mnemonic = "SRA";
                OP_ROL:   mnemonic = "ROL";   OP_ROR:   mnemonic = "ROR";
                OP_PASSA: mnemonic = "PASSA"; OP_PASSB: mnemonic = "PASSB";
                OP_CLR:   mnemonic = "CLR";
                default:  mnemonic = "ILLEG";
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Scoreboard and counters
    // ------------------------------------------------------------------
    integer cycles_checked, checks_failed, txn_count, model_failures;
    reg              exp_known;     // becomes 1 at the first reset edge
    reg              exp_valid;
    reg  [VW-1:0]    exp_vec;
    reg  [4:0]       exp_op;        // transaction whose data is on the outputs
    reg  [W-1:0]     exp_a, exp_b;
    integer          exp_txn;
    reg  [8*12-1:0]  exp_section;
    reg  [8*12-1:0]  section;       // set by the stimulus code

    // Coverage-style event counters (not formal functional coverage).
    integer op_hits    [0:31];
    integer carry1     [0:31];
    integer carry0     [0:31];
    integer ovf_hits   [0:31];
    integer zero_class [0:3];
    integer shift_bin  [0:24];      // (opcode[2:0] * 5) + amount bin
    integer add_ovf_pos, add_ovf_neg, sub_ovf_pos, sub_ovf_neg;
    integer cov_reset_valid, cov_reset_mid, cov_b2b, cov_gap1, cov_gap_long, cov_hold;
    integer idle_run;
    reg     prev_accept;

    integer k;
    initial begin
        cycles_checked = 0; checks_failed = 0; txn_count = 0; model_failures = 0;
        exp_known = 1'b0; exp_valid = 1'b0; exp_vec = {VW{1'b0}};
        exp_op = 5'd0; exp_a = ZERO; exp_b = ZERO; exp_txn = 0;
        exp_section = "none"; section = "init";
        for (k = 0; k < 32; k = k + 1) begin
            op_hits[k] = 0; carry1[k] = 0; carry0[k] = 0; ovf_hits[k] = 0;
        end
        for (k = 0; k < 4; k = k + 1)  zero_class[k] = 0;
        for (k = 0; k < 25; k = k + 1) shift_bin[k] = 0;
        add_ovf_pos = 0; add_ovf_neg = 0; sub_ovf_pos = 0; sub_ovf_neg = 0;
        cov_reset_valid = 0; cov_reset_mid = 0; cov_b2b = 0;
        cov_gap1 = 0; cov_gap_long = 0; cov_hold = 0;
        idle_run = 0; prev_accept = 1'b0;
    end

    function integer amount_bin;     // -1: amount not in a tracked bin
        input [W-1:0] amt;
        begin
            if      (amt == 0)     amount_bin = 0;
            else if (amt == 1)     amount_bin = 1;
            else if (amt == W - 1) amount_bin = 2;
            else if (amt == W)     amount_bin = 3;
            else if (amt > W)      amount_bin = 4;
            else                   amount_bin = -1;
        end
    endfunction

    task count_transaction;
        input [4:0]    op;
        input [W-1:0]  ta;
        input [W-1:0]  tb_;
        input [VW-1:0] e;
        integer bin;
        begin
            op_hits[op] = op_hits[op] + 1;
            if (e[W])   carry1[op] = carry1[op] + 1;
            else        carry0[op] = carry0[op] + 1;
            if (e[W+1]) ovf_hits[op] = ovf_hits[op] + 1;
            if (e[W+2]) zero_class[op[4:3]] = zero_class[op[4:3]] + 1;
            if (op == OP_ADD && e[W+1] && !ta[W-1]) add_ovf_pos = add_ovf_pos + 1;
            if (op == OP_ADD && e[W+1] &&  ta[W-1]) add_ovf_neg = add_ovf_neg + 1;
            if (op == OP_SUB && e[W+1] && !ta[W-1]) sub_ovf_pos = sub_ovf_pos + 1;
            if (op == OP_SUB && e[W+1] &&  ta[W-1]) sub_ovf_neg = sub_ovf_neg + 1;
            if (op[4:3] == CLASS_SHIFT && op[2:0] < 5) begin
                bin = amount_bin(tb_);
                if (bin >= 0) shift_bin[op[2:0] * 5 + bin] = shift_bin[op[2:0] * 5 + bin] + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        // 1. Model the output registers at this edge (inputs are stable:
        //    the stimulus changed them on the previous falling edge).
        if (rst_n === 1'b0) begin
            if (valid_in === 1'b1) cov_reset_valid = cov_reset_valid + 1;
            if (exp_known && exp_valid) cov_reset_mid = cov_reset_mid + 1;
            exp_known   = 1'b1;
            exp_valid   = 1'b0;
            exp_vec     = {VW{1'b0}};
            exp_op      = 5'd0;
            exp_a       = ZERO;
            exp_b       = ZERO;
            exp_txn     = 0;
            exp_section = "reset";
            prev_accept = 1'b0;
            idle_run    = 0;
        end else if (exp_known) begin
            exp_valid = (valid_in === 1'b1);
            if (exp_valid) begin
                txn_count   = txn_count + 1;
                exp_vec     = ref_alu(opcode, a, b);
                exp_op      = opcode;
                exp_a       = a;
                exp_b       = b;
                exp_txn     = txn_count;
                exp_section = section;
                count_transaction(opcode, a, b, exp_vec);
                if (prev_accept)    cov_b2b = cov_b2b + 1;
                if (idle_run == 1)  cov_gap1 = cov_gap1 + 1;
                if (idle_run >= 3)  cov_gap_long = cov_gap_long + 1;
                idle_run    = 0;
                prev_accept = 1'b1;
            end else begin
                if (prev_accept) cov_hold = cov_hold + 1;
                idle_run    = idle_run + 1;
                prev_accept = 1'b0;
            end
        end

        // 2. Check the DUT once its registers have updated.
        #1;
        if (exp_known) begin
            cycles_checked = cycles_checked + 1;
            if (valid_out !== exp_valid ||
                {illegal_op, negative, zero, overflow, carry, result} !== exp_vec) begin
                checks_failed = checks_failed + 1;
                if (checks_failed <= MAX_REPORT) begin
                    $display("FAIL check %0d at %0d ns: txn #%0d [%0s] %0s (%b) a=0x%h b=0x%h%0s",
                             cycles_checked, $time, exp_txn, exp_section, mnemonic(exp_op),
                             exp_op, exp_a, exp_b, exp_valid ? "" : "  (output should be held/reset)");
                    $display("    expected: valid_out=%b result=0x%h C=%b V=%b Z=%b N=%b ILL=%b",
                             exp_valid, exp_vec[W-1:0], exp_vec[W], exp_vec[W+1],
                             exp_vec[W+2], exp_vec[W+3], exp_vec[W+4]);
                    $display("    actual  : valid_out=%b result=0x%h C=%b V=%b Z=%b N=%b ILL=%b",
                             valid_out, result, carry, overflow, zero, negative, illegal_op);
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Stimulus helpers
    // ------------------------------------------------------------------
    task cycle;
        input         rst;
        input         vld;
        input [4:0]   op;
        input [W-1:0] ta;
        input [W-1:0] tb_;
        begin
            @(negedge clk);
            rst_n    = rst;
            valid_in = vld;
            if (vld) begin
                opcode = op; a = ta; b = tb_;
            end else begin
                // Unknown data while idle proves the DUT ignores it.
                opcode = 5'bx; a = {W{1'bx}}; b = {W{1'bx}};
            end
        end
    endtask

    task send;
        input [4:0]   op;
        input [W-1:0] ta;
        input [W-1:0] tb_;
        begin
            cycle(1'b1, 1'b1, op, ta, tb_);
        end
    endtask

    task idle;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) cycle(1'b1, 1'b0, 5'd0, ZERO, ZERO);
        end
    endtask

    // Hand-computed expectation: checks the reference model itself against
    // values written from the specification, then sends the transaction so
    // the scoreboard checks the DUT against the (now validated) model.
    task golden;
        input [4:0]   op;
        input [W-1:0] ta;
        input [W-1:0] tb_;
        input [W-1:0] r;
        input c, v, z, n;
        reg [VW-1:0] got;
        begin
            got = ref_alu(op, ta, tb_);
            if (got !== {1'b0, n, z, v, c, r}) begin
                model_failures = model_failures + 1;
                $display("MODEL FAIL %0s a=0x%h b=0x%h: model {N,Z,V,C,result}=%b,%b,%b,%b,0x%h spec=%b,%b,%b,%b,0x%h",
                         mnemonic(op), ta, tb_, got[W+3], got[W+2], got[W+1], got[W], got[W-1:0],
                         n, z, v, c, r);
            end
            send(op, ta, tb_);
        end
    endtask

    // Random helpers. $random(seed) returns a signed 32-bit value; masking
    // the sign bit keeps the modulo results non-negative.
    integer seed;
    function integer urand;
        input integer limit;
        begin
            urand = ($random(seed) & 32'h7fff_ffff) % limit;
        end
    endfunction

    reg [W-1:0] corner [0:9];
    reg [W-1:0] alt;                // 0101...01 pattern
    reg [4:0]   legal_ops   [0:31];
    reg [4:0]   illegal_ops [0:31];
    integer     n_legal, n_illegal;
    reg [VW-1:0] tmp_vec;

    // 25% of operands come from the corner set: a uniform draw would almost
    // never produce SMAX, SMIN or ALL1, so overflow cases would be rare.
    function [W-1:0] rand_operand;
        input integer dummy;
        integer idx;
        begin
            idx = urand(10);
            if (urand(4) == 0) rand_operand = corner[idx];
            else               rand_operand = $random(seed);
        end
    endfunction

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    reg [8*256-1:0] vcd_file;
    integer i, j, op_i, holes;
    reg [W-1:0] amounts [0:6];
    reg [W-1:0] shift_src [0:4];
    reg [W-1:0] ra, rb;
    reg rst_r, vld_r;
    reg [4:0] op_r;
    integer pick_ill, pick_leg;

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = SEED;
        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_alu);
        end
        $display("tb_alu: DATA_WIDTH=%0d USE_RCA=%0d NUM_RANDOM=%0d seed=%0d",
                 W, USE_RCA, NUM_RANDOM, seed);

        for (i = 0; i < W; i = i + 1) alt[i] = (i % 2 == 0);
        corner[0] = ZERO;     corner[1] = ONE;       corner[2] = ONE + ONE;
        corner[3] = SMAX;     corner[4] = SMIN;      corner[5] = SMIN + ONE;
        corner[6] = ALL1;     corner[7] = ALL1 - ONE;
        corner[8] = alt;      corner[9] = ~alt;

        n_legal = 0; n_illegal = 0;
        for (i = 0; i < 32; i = i + 1) begin
            tmp_vec = ref_alu(i[4:0], ZERO, ZERO);
            if (tmp_vec[W+4]) begin illegal_ops[n_illegal] = i[4:0]; n_illegal = n_illegal + 1; end
            else              begin legal_ops[n_legal]     = i[4:0]; n_legal   = n_legal + 1;   end
        end
        if (n_legal != 23 || n_illegal != 9) begin
            $display("MODEL FAIL: expected 23 legal / 9 illegal opcodes, model has %0d / %0d",
                     n_legal, n_illegal);
            model_failures = model_failures + 1;
        end

        // ---------------- D. Reset and interface ----------------------
        // Drive reset from time 0 so the first rising edge resets the DUT.
        section = "D:reset";
        rst_n = 1'b0; valid_in = 1'b0; opcode = OP_ADD; a = ZERO; b = ZERO;
        cycle(1'b0, 1'b1, OP_ADD, ONE, ONE);          // reset must beat valid_in
        cycle(1'b0, 1'b0, OP_ADD, ZERO, ZERO);
        section = "D:b2b";
        send(OP_ADD, SMAX, ONE);
        send(OP_SUB, ONE + ONE, ONE);
        send(OP_XOR, alt, ALL1);
        send(OP_PASSB, ZERO, SMIN);
        section = "D:gap";
        idle(1);                                      // outputs must hold PASSB
        send(OP_INC, ALL1, ZERO);
        idle(3);
        send(OP_NOT, alt, ZERO);
        idle(5);
        section = "D:reset-mid";
        send(OP_DEC, ZERO, ZERO);
        cycle(1'b0, 1'b1, OP_ADD, ONE, ONE);          // reset with a pending request
        send(OP_ADD, ONE, ONE);
        cycle(1'b0, 1'b0, OP_ADD, ZERO, ZERO);
        cycle(1'b0, 1'b0, OP_ADD, ZERO, ZERO);
        send(5'b01_111, ALL1, ALL1);                  // illegal right after reset
        idle(1);

        // ---------------- B. Arithmetic golden vectors ----------------
        // Expectations written by hand from the spec (section 3.3), with the
        // W=10 values (0x1FF, 0x200, 0x3FF) expressed as SMAX/SMIN/ALL1.
        //                    result         C     V     Z     N
        section = "B:golden";
        golden(OP_ADD, SMAX, ONE,   SMIN,          1'b0, 1'b1, 1'b0, 1'b1);
        golden(OP_ADD, ALL1, ONE,   ZERO,          1'b1, 1'b0, 1'b1, 1'b0);
        golden(OP_ADD, SMIN, SMIN,  ZERO,          1'b1, 1'b1, 1'b1, 1'b0);
        golden(OP_ADD, ALL1, ALL1,  ALL1 - ONE,    1'b1, 1'b0, 1'b0, 1'b1);
        golden(OP_ADD, ZERO, ZERO,  ZERO,          1'b0, 1'b0, 1'b1, 1'b0);
        golden(OP_SUB, SMIN, ONE,   SMAX,          1'b1, 1'b1, 1'b0, 1'b0);
        golden(OP_SUB, SMAX, ALL1,  SMIN,          1'b0, 1'b1, 1'b0, 1'b1);
        golden(OP_SUB, ZERO, ONE,   ALL1,          1'b0, 1'b0, 1'b0, 1'b1);
        golden(OP_SUB, ONE,  ONE,   ZERO,          1'b1, 1'b0, 1'b1, 1'b0);
        golden(OP_SUB, ZERO, ZERO,  ZERO,          1'b1, 1'b0, 1'b1, 1'b0);
        golden(OP_INC, SMAX, ZERO,  SMIN,          1'b0, 1'b1, 1'b0, 1'b1);
        golden(OP_INC, ALL1, ZERO,  ZERO,          1'b1, 1'b0, 1'b1, 1'b0);
        golden(OP_DEC, ZERO, ZERO,  ALL1,          1'b0, 1'b0, 1'b0, 1'b1);
        golden(OP_DEC, SMIN, ZERO,  SMAX,          1'b1, 1'b1, 1'b0, 1'b0);
        golden(OP_DEC, ONE,  ZERO,  ZERO,          1'b1, 1'b0, 1'b1, 1'b0);
        golden(OP_NEG, SMIN, ZERO,  SMIN,          1'b0, 1'b1, 1'b0, 1'b1);
        golden(OP_NEG, ZERO, ZERO,  ZERO,          1'b1, 1'b0, 1'b1, 1'b0);
        golden(OP_NEG, ONE,  ZERO,  ALL1,          1'b0, 1'b0, 1'b0, 1'b1);
        golden(OP_SLT,  SMIN, ONE,  ONE,           1'b0, 1'b0, 1'b0, 1'b0);  // -min < 1 although min-1 wraps
        golden(OP_SLTU, SMIN, ONE,  ZERO,          1'b0, 1'b0, 1'b1, 1'b0);
        golden(OP_SLT,  ONE, SMIN,  ZERO,          1'b0, 1'b0, 1'b1, 1'b0);
        golden(OP_SLTU, ONE, SMIN,  ONE,           1'b0, 1'b0, 1'b0, 1'b0);
        golden(OP_SLT,  ALL1, ZERO, ONE,           1'b0, 1'b0, 1'b0, 1'b0);  // -1 < 0
        golden(OP_SLTU, ALL1, ZERO, ZERO,          1'b0, 1'b0, 1'b1, 1'b0);
        golden(OP_EQ,   alt, alt,   ONE,           1'b0, 1'b0, 1'b0, 1'b0);
        golden(OP_EQ,   alt, ~alt,  ZERO,          1'b0, 1'b0, 1'b1, 1'b0);
        golden(OP_SRA,  SMIN, ONE,  SMIN | (SMIN >> 1), 1'b0, 1'b0, 1'b0, 1'b1);
        golden(OP_SRA,  SMIN, ALL1, ALL1,          1'b0, 1'b0, 1'b0, 1'b1);
        golden(OP_SRL,  SMIN, ONE,  SMIN >> 1,     1'b0, 1'b0, 1'b0, 1'b0);
        golden(OP_ROL,  SMIN, ONE,  ONE,           1'b0, 1'b0, 1'b0, 1'b0);
        golden(OP_ROR,  ONE,  ONE,  SMIN,          1'b0, 1'b0, 1'b0, 1'b1);
        golden(OP_ROL,  ONE,  W + 1,          ONE + ONE, 1'b0, 1'b0, 1'b0, 1'b0);  // W+1 mod W = 1
        golden(OP_CLR,  ALL1, ALL1, ZERO,          1'b0, 1'b0, 1'b1, 1'b0);
        golden(OP_NOT,  ZERO, ALL1, ALL1,          1'b0, 1'b0, 1'b0, 1'b1);
        idle(2);

        // ---------------- A. Directed: every opcode x corner operands --
        // All 32 codes, so the 9 illegal ones are hit with every operand pair.
        section = "A:directed";
        for (op_i = 0; op_i < 32; op_i = op_i + 1)
            for (i = 0; i < 10; i = i + 1)
                for (j = 0; j < 10; j = j + 1)
                    send(op_i[4:0], corner[i], corner[j]);
        idle(2);

        // ---------------- C. Shifts and rotates -----------------------
        section = "C:shift";
        amounts[0] = ZERO;        amounts[1] = ONE;
        amounts[2] = W - 1;       amounts[3] = W;
        amounts[4] = W + 1;       amounts[5] = 2 * W;
        amounts[6] = ALL1;
        shift_src[0] = SMIN | ONE; shift_src[1] = alt;  shift_src[2] = ~alt;
        shift_src[3] = SMAX;       shift_src[4] = ALL1;
        for (op_i = OP_SLL; op_i <= OP_ROR; op_i = op_i + 1)
            for (i = 0; i < 5; i = i + 1)
                for (j = 0; j < 7; j = j + 1)
                    send(op_i[4:0], shift_src[i], amounts[j]);
        // Every rotate amount 0 .. 2^W-1 for one asymmetric source value,
        // which exercises every stage of the mod-W rotator.
        for (i = 0; i < (1 << W) && i < 4096; i = i + 1) begin
            send(OP_ROL, SMIN | ONE | (ONE << 2), i);
            send(OP_ROR, SMIN | ONE | (ONE << 2), i);
        end
        idle(2);

        // ---------------- E. Constrained random ------------------------
        section = "E:random";
        for (i = 0; i < NUM_RANDOM; i = i + 1) begin
            rst_r = (urand(512) != 0);                // rare random reset
            vld_r = (urand(4) != 0);                  // ~75% valid
            pick_ill = urand(n_illegal);
            pick_leg = urand(n_legal);
            if (urand(10) == 0) op_r = illegal_ops[pick_ill];   // ~10% illegal
            else                op_r = legal_ops[pick_leg];
            ra = rand_operand(0);
            rb = rand_operand(0);
            cycle(rst_r, vld_r, op_r, ra, rb);
        end
        idle(3);

        // ---------------- Summary -------------------------------------
        @(negedge clk);
        report_and_finish;
    end

    // Watchdog: a hang must fail, not run forever.
    initial begin
        #((NUM_RANDOM + 20000) * 100);
        $display("FAIL: watchdog timeout");
        $display("TEST FAILED (timeout)");
        $stop;
    end

    task require;
        input [8*40-1:0] name;
        input integer    count;
        begin
            if (count == 0) begin
                $display("  HOLE: %0s", name);
                holes = holes + 1;
            end
        end
    endtask

    task report_and_finish;
        integer o;
        begin
            holes = 0;
            $display("");
            $display("---------------- event counters (not formal coverage) ----------------");
            for (o = 0; o < 32; o = o + 1)
                $display("  op %b %-5s : %6d txns   C=1:%6d   V=1:%6d", o[4:0], mnemonic(o[4:0]),
                         op_hits[o], carry1[o], ovf_hits[o]);
            $display("  ADD overflow pos+pos->neg %0d, neg+neg->pos %0d", add_ovf_pos, add_ovf_neg);
            $display("  SUB overflow pos-neg->neg %0d, neg-pos->pos %0d", sub_ovf_pos, sub_ovf_neg);
            $display("  SUB borrow (C=0) %0d, no borrow (C=1) %0d", carry0[OP_SUB], carry1[OP_SUB]);
            $display("  zero results: arith %0d logic %0d shift %0d move %0d",
                     zero_class[0], zero_class[1], zero_class[2], zero_class[3]);
            $display("  shift amount bins [0, 1, W-1, W, >W]:");
            for (o = 0; o < 5; o = o + 1)
                $display("    %-5s %5d %5d %5d %5d %5d", mnemonic({2'b10, o[2:0]}),
                         shift_bin[o*5], shift_bin[o*5+1], shift_bin[o*5+2],
                         shift_bin[o*5+3], shift_bin[o*5+4]);
            $display("  interface: reset-with-valid %0d, reset-mid-stream %0d, back-to-back %0d,",
                     cov_reset_valid, cov_reset_mid, cov_b2b);
            $display("             gap=1 %0d, gap>=3 %0d, hold-after-txn %0d",
                     cov_gap1, cov_gap_long, cov_hold);

            // Required events: a zero count means the test silently stopped
            // exercising something, so it fails the run.
            for (o = 0; o < 32; o = o + 1) require("opcode executed", op_hits[o]);
            for (o = 0; o < 5; o = o + 1) begin       // ADD SUB INC DEC NEG
                require("arith carry=1", carry1[o]);
                require("arith carry=0", carry0[o]);
            end
            require("ADD overflow", ovf_hits[OP_ADD]);  require("SUB overflow", ovf_hits[OP_SUB]);
            require("INC overflow", ovf_hits[OP_INC]);  require("DEC overflow", ovf_hits[OP_DEC]);
            require("NEG overflow", ovf_hits[OP_NEG]);
            require("ADD ovf pos", add_ovf_pos);        require("ADD ovf neg", add_ovf_neg);
            require("SUB ovf pos", sub_ovf_pos);        require("SUB ovf neg", sub_ovf_neg);
            for (o = 0; o < 4; o = o + 1)  require("zero result per class", zero_class[o]);
            for (o = 0; o < 25; o = o + 1) require("shift amount bin", shift_bin[o]);
            require("reset with valid_in", cov_reset_valid);
            require("reset mid-stream", cov_reset_mid);
            require("back-to-back", cov_b2b);
            require("gap of 1", cov_gap1);
            require("gap of >=3", cov_gap_long);
            require("hold after txn", cov_hold);

            $display("-----------------------------------------------------------------------");
            $display("cycles checked %0d, transactions %0d, check failures %0d, model failures %0d, holes %0d",
                     cycles_checked, txn_count, checks_failed, model_failures, holes);
            if (checks_failed == 0 && model_failures == 0 && holes == 0 && cycles_checked > 0) begin
                $display("TEST PASSED");
                $finish;
            end else begin
                $display("TEST FAILED (%0d check failures, %0d model failures, %0d holes)",
                         checks_failed, model_failures, holes);
                $stop;
            end
        end
    endtask
endmodule
