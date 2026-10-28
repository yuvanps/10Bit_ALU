`timescale 1ns / 1ps
`default_nettype none

// ripple_carry_adder -- WIDTH full adders chained through carry vector c.
// c[0] is the carry-in and c[WIDTH] the carry-out, so {cout, sum} is the exact
// WIDTH+1-bit value of a + b + cin.
module ripple_carry_adder #(
    parameter WIDTH = 10
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             cin,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);
    wire [WIDTH:0] c;

    assign c[0] = cin;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_bit
            full_adder u_fa (
                .a    (a[i]),
                .b    (b[i]),
                .cin  (c[i]),
                .sum  (sum[i]),
                .cout (c[i+1])
            );
        end
    endgenerate

    assign cout = c[WIDTH];
endmodule

`default_nettype wire
