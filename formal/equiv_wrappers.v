`timescale 1ns / 1ps
`default_nettype none

// Wrappers used only by the Yosys equivalence proofs (scripts/equiv_*.ys).
// They give the two configurations distinct module names so `miter` can
// compare them; they are not part of the synthesizable design.

// Behavioral reference for the ripple-carry adder.
module adder_ref #(
    parameter WIDTH = 10
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             cin,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);
    assign {cout, sum} = {1'b0, a} + {1'b0, b} + {{WIDTH{1'b0}}, cin};
endmodule

module rca_10 (
    input  wire [9:0] a,
    input  wire [9:0] b,
    input  wire       cin,
    output wire [9:0] sum,
    output wire       cout
);
    ripple_carry_adder #(.WIDTH(10)) u (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout));
endmodule

module ref_10 (
    input  wire [9:0] a,
    input  wire [9:0] b,
    input  wire       cin,
    output wire [9:0] sum,
    output wire       cout
);
    adder_ref #(.WIDTH(10)) u (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout));
endmodule

// The two full ALU configurations, ports identical.
`define ALU_WRAPPER(NAME, RCA)                                              \
module NAME (                                                               \
    input  wire       clk, rst_n, valid_in,                                 \
    input  wire [9:0] a, b,                                                 \
    input  wire [4:0] opcode,                                               \
    output wire       valid_out,                                            \
    output wire [9:0] result,                                               \
    output wire       carry, overflow, zero, negative, illegal_op           \
);                                                                          \
    alu_top #(.DATA_WIDTH(10), .USE_RCA(RCA)) u (                           \
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .a(a), .b(b),        \
        .opcode(opcode), .valid_out(valid_out), .result(result),            \
        .carry(carry), .overflow(overflow), .zero(zero),                    \
        .negative(negative), .illegal_op(illegal_op));                      \
endmodule

`ALU_WRAPPER(alu_behav, 0)
`ALU_WRAPPER(alu_struct, 1)

`default_nettype wire
