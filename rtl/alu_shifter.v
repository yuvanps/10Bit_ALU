`timescale 1ns / 1ps
`default_nettype none

// alu_shifter -- SLL SRL SRA ROL ROR. The shift amount is the full unsigned
// value of b.
//
//   SLL/SRL : amount >= DATA_WIDTH gives zero (native Verilog semantics).
//   SRA     : amount >= DATA_WIDTH gives all copies of a[MSB].
//   ROL/ROR : rotate by (b mod DATA_WIDTH).
//
// Rotation without a divider: b = sum(b[k] * 2^k), and rotations add mod
// DATA_WIDTH, so a rotate by b equals stage k rotating by the constant
// (2^k mod DATA_WIDTH) whenever b[k] is set. That is DATA_WIDTH stages of
// constant-wiring plus a 2:1 mux, and works for non-power-of-two widths.
//
// ROR reuses the left rotator: rotr(v, n) = reverse(rotl(reverse(v), n)).
// Bit reversal is free wiring, so only one rotator chain is built.
module alu_shifter #(
    parameter DATA_WIDTH = 10
) (
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [4:0]            opcode,
    output reg  [DATA_WIDTH-1:0] result
);
    `include "alu_opcodes.vh"

    // (2^k) mod m, computed iteratively so it never overflows a 32-bit integer.
    function integer pow2_mod;
        input integer k;
        input integer m;
        integer i;
        begin
            pow2_mod = 1 % m;
            for (i = 0; i < k; i = i + 1)
                pow2_mod = (pow2_mod * 2) % m;
        end
    endfunction

    function [DATA_WIDTH-1:0] reverse_bits;
        input [DATA_WIDTH-1:0] v;
        integer i;
        begin
            for (i = 0; i < DATA_WIDTH; i = i + 1)
                reverse_bits[i] = v[DATA_WIDTH-1-i];
        end
    endfunction

    wire                  is_ror = (opcode == OP_ROR);
    wire [DATA_WIDTH-1:0] a_rev  = reverse_bits(a);

    // All rotator stages packed into one vector: stage k occupies
    // stages[k*DATA_WIDTH +: DATA_WIDTH]; stage 0 is the input and stage
    // DATA_WIDTH the output. A packed vector is used instead of an unpacked
    // array because Yosys turns a wire array into a memory ($mem) cell.
    // split_var: lets Verilator see each slice separately; otherwise it
    // reports a false combinational loop through the vector as a whole.
    wire [(DATA_WIDTH+1)*DATA_WIDTH-1:0] stages /* verilator split_var */;
    assign stages[0 +: DATA_WIDTH] = is_ror ? a_rev : a;

    genvar k;
    generate
        for (k = 0; k < DATA_WIDTH; k = k + 1) begin : g_rot
            localparam integer R = pow2_mod(k, DATA_WIDTH);
            wire [DATA_WIDTH-1:0] in = stages[k*DATA_WIDTH +: DATA_WIDTH];
            // Constant rotate-left by R. When R == 0 the right shift is by
            // DATA_WIDTH, which yields zero, so the stage passes data through.
            wire [DATA_WIDTH-1:0] rotated = (in << R) | (in >> (DATA_WIDTH - R));
            assign stages[(k+1)*DATA_WIDTH +: DATA_WIDTH] = b[k] ? rotated : in;
        end
    endgenerate

    wire [DATA_WIDTH-1:0] rot_out = stages[DATA_WIDTH*DATA_WIDTH +: DATA_WIDTH];

    always @(*) begin
        case (opcode)
            OP_SLL:  result = a << b;
            OP_SRL:  result = a >> b;
            // Every operand of a signed shift must be signed, or Verilog
            // evaluates the expression as unsigned and >>> becomes a logical
            // shift. b, the shift amount, is self-determined and may be unsigned.
            OP_SRA:  result = $signed(a) >>> b;
            OP_ROL:  result = rot_out;
            OP_ROR:  result = reverse_bits(rot_out);
            default: result = {DATA_WIDTH{1'b0}};
        endcase
    end
endmodule

`default_nettype wire
