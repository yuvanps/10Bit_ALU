`timescale 1ns / 1ps

// tb_ripple_carry_adder -- self-checking test of the structural adder.
//
// WIDTH <= 10 : exhaustive, every (a, b, cin) combination (2^(2*WIDTH+1) vectors).
// WIDTH >  10 : directed corner cases plus NUM_RANDOM seeded random vectors.
//
// The expected value is the exact WIDTH+1-bit sum from Verilog's '+' operator,
// with both operands zero-extended so the carry-out cannot be truncated.
// Ends with "TEST PASSED" + $finish or "TEST FAILED" + $stop (run with vvp -N).
module tb_ripple_carry_adder;
    parameter WIDTH      = 10;
    parameter NUM_RANDOM = 200000;
    parameter SEED       = 20261028;
    parameter MAX_REPORT = 20;

    localparam EXHAUSTIVE = (WIDTH <= 10);

    reg  [WIDTH-1:0] a, b;
    reg              cin;
    wire [WIDTH-1:0] sum;
    wire             cout;
    reg  [WIDTH:0]   expected;

    ripple_carry_adder #(.WIDTH(WIDTH)) dut (
        .a    (a),
        .b    (b),
        .cin  (cin),
        .sum  (sum),
        .cout (cout)
    );

    integer vectors, failures, seed;
    integer ia, ib, ic, n;
    reg [WIDTH-1:0] corner [0:5];

    task check;
        begin
            #1;
            expected = {1'b0, a} + {1'b0, b} + {{WIDTH{1'b0}}, cin};
            vectors  = vectors + 1;
            if ({cout, sum} !== expected) begin
                failures = failures + 1;
                if (failures <= MAX_REPORT)
                    $display("FAIL vector %0d: a=0x%h b=0x%h cin=%b expected {cout,sum}=0x%h actual 0x%h",
                             vectors, a, b, cin, expected, {cout, sum});
            end
        end
    endtask

    initial begin
        vectors = 0; failures = 0;
        if (!$value$plusargs("seed=%d", seed)) seed = SEED;
        $display("tb_ripple_carry_adder: WIDTH=%0d mode=%0s", WIDTH,
                 EXHAUSTIVE ? "exhaustive" : "corner+random");

        if (EXHAUSTIVE) begin
            for (ia = 0; ia < (1 << WIDTH); ia = ia + 1)
                for (ib = 0; ib < (1 << WIDTH); ib = ib + 1)
                    for (ic = 0; ic < 2; ic = ic + 1) begin
                        a = ia; b = ib; cin = ic;
                        check;
                    end
        end else begin
            // Corners: a carry rippling through every bit is the worst case.
            corner[0] = {WIDTH{1'b0}};
            corner[1] = {{(WIDTH-1){1'b0}}, 1'b1};
            corner[2] = {WIDTH{1'b1}};
            corner[3] = {1'b0, {(WIDTH-1){1'b1}}};
            corner[4] = {1'b1, {(WIDTH-1){1'b0}}};
            for (ia = 0; ia < WIDTH; ia = ia + 1) corner[5][ia] = ia[0];
            for (ia = 0; ia < 6; ia = ia + 1)
                for (ib = 0; ib < 6; ib = ib + 1)
                    for (ic = 0; ic < 2; ic = ic + 1) begin
                        a = corner[ia]; b = corner[ib]; cin = ic;
                        check;
                    end
            for (n = 0; n < NUM_RANDOM; n = n + 1) begin
                a = $random(seed); b = $random(seed); cin = $random(seed);
                check;
            end
        end

        $display("vectors %0d, failures %0d", vectors, failures);
        if (failures == 0 && vectors > 0) begin
            $display("TEST PASSED");
            $finish;
        end else begin
            $display("TEST FAILED (%0d failures)", failures);
            $stop;
        end
    end
endmodule
