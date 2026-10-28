`timescale 1ns / 1ps
`default_nettype none

// alu_arith -- ADD SUB INC DEC NEG SLTU SLT EQ.
//
// Every operation except EQ is computed by ONE shared adder,
//     {cout, sum} = x + y + cin,
// with x, y and cin chosen per opcode:
//
//     op    x   y          cin   note
//     ADD   a   b          0
//     SUB   a   ~b         1     a - b = a + ~b + 1
//     INC   a   0          1
//     DEC   a   all ones   0     a - 1 = a + ~1 + 1 = a + all ones
//     NEG   0   ~a         1     -a = 0 - a = ~a + 1
//     SLTU  a   ~b         1     (same adder setup as SUB)
//     SLT   a   ~b         1     (same adder setup as SUB)
//
// The carry flag is always the adder's carry-out, so for SUB/DEC/NEG
// carry = 1 means "no borrow" (ARM convention).
//
// USE_RCA selects the adder implementation; nothing else in the ALU differs
// between the two configurations.
module alu_arith #(
    parameter DATA_WIDTH = 10,
    parameter USE_RCA    = 0
) (
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [4:0]            opcode,
    output reg  [DATA_WIDTH-1:0] result,
    output reg                   carry,
    output reg                   overflow
);
    `include "alu_opcodes.vh"

    localparam MSB = DATA_WIDTH - 1;

    reg  [DATA_WIDTH-1:0] x;
    reg  [DATA_WIDTH-1:0] y;
    reg                   cin;
    wire [DATA_WIDTH-1:0] sum;
    wire                  cout;

    // Operand selection for the shared adder.
    always @(*) begin
        x   = a;
        y   = b;
        cin = 1'b0;
        case (opcode)
            OP_SUB, OP_SLTU, OP_SLT: begin
                y   = ~b;
                cin = 1'b1;
            end
            OP_INC: begin
                y   = {DATA_WIDTH{1'b0}};
                cin = 1'b1;
            end
            OP_DEC: begin
                y   = {DATA_WIDTH{1'b1}};
            end
            OP_NEG: begin
                x   = {DATA_WIDTH{1'b0}};
                y   = ~a;
                cin = 1'b1;
            end
            default: begin
                // OP_ADD, and opcodes that ignore the adder: x = a, y = b, cin = 0.
            end
        endcase
    end

    generate
        if (USE_RCA != 0) begin : g_rca
            ripple_carry_adder #(.WIDTH(DATA_WIDTH)) u_adder (
                .a    (x),
                .b    (y),
                .cin  (cin),
                .sum  (sum),
                .cout (cout)
            );
        end else begin : g_behavioral
            // Both operands are zero-extended to DATA_WIDTH+1 bits, so the
            // carry-out lands in the extra bit instead of being truncated.
            assign {cout, sum} = {1'b0, x} + {1'b0, y} + {{DATA_WIDTH{1'b0}}, cin};
        end
    endgenerate

    // Signed overflow of x + y + cin: the operands share a sign and the sum's
    // sign differs. This equals (carry into MSB) ^ (carry out of MSB) for any
    // cin, so it is correct for every row of the table above.
    wire adder_overflow = (x[MSB] == y[MSB]) && (sum[MSB] != x[MSB]);

    // For SLT, the sign of a - b alone is wrong when the subtraction
    // overflows (e.g. min_neg - 1 wraps positive); xor-ing with V fixes it.
    wire lt_signed   = sum[MSB] ^ adder_overflow;
    wire lt_unsigned = ~cout;                  // borrow out of a - b

    always @(*) begin
        result   = {DATA_WIDTH{1'b0}};
        carry    = 1'b0;
        overflow = 1'b0;
        case (opcode)
            OP_ADD, OP_SUB, OP_INC, OP_DEC, OP_NEG: begin
                result   = sum;
                carry    = cout;
                overflow = adder_overflow;
            end
            OP_SLTU: result = {{(DATA_WIDTH-1){1'b0}}, lt_unsigned};
            OP_SLT:  result = {{(DATA_WIDTH-1){1'b0}}, lt_signed};
            OP_EQ:   result = {{(DATA_WIDTH-1){1'b0}}, (a == b)};
            default: begin
                // Not an arithmetic opcode: outputs stay zero.
            end
        endcase
    end
endmodule

`default_nettype wire
