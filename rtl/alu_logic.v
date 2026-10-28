`timescale 1ns / 1ps
`default_nettype none

// alu_logic -- bitwise operations. Purely combinational, no flags.
module alu_logic #(
    parameter DATA_WIDTH = 10
) (
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [4:0]            opcode,
    output reg  [DATA_WIDTH-1:0] result
);
    `include "alu_opcodes.vh"

    always @(*) begin
        case (opcode)
            OP_AND:  result = a & b;
            OP_OR:   result = a | b;
            OP_XOR:  result = a ^ b;
            OP_NOT:  result = ~a;
            OP_NAND: result = ~(a & b);
            OP_NOR:  result = ~(a | b);
            OP_XNOR: result = ~(a ^ b);
            default: result = {DATA_WIDTH{1'b0}};
        endcase
    end
endmodule

`default_nettype wire
