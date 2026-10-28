`timescale 1ns / 1ps
`default_nettype none

// alu_top -- registered ALU, one-cycle latency, synchronous active-low reset.
//
// At each rising clock edge, in priority order:
//   rst_n == 0    : valid_out, result and all flags clear to 0.
//   valid_in == 1 : a, b, opcode are sampled; after this edge valid_out = 1
//                   and result/flags reflect the sampled transaction.
//   otherwise     : valid_out = 0; result and flags HOLD their values.
//
// Flag rules (docs/specification.md, section 3):
//   zero       = (result == 0)    for legal opcodes
//   negative   = result[MSB]      for legal opcodes
//   carry      = adder carry-out  for ADD SUB INC DEC NEG, else 0
//                (1 means "no borrow" for SUB, DEC and NEG)
//   overflow   = signed overflow  for ADD SUB INC DEC NEG, else 0
//   illegal_op = 1 for unsupported opcodes; result and all other flags are 0
module alu_top #(
    parameter DATA_WIDTH = 10,
    parameter USE_RCA    = 0    // 0: behavioral '+', 1: structural ripple-carry adder
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [4:0]            opcode,
    output reg                   valid_out,
    output reg  [DATA_WIDTH-1:0] result,
    output reg                   carry,
    output reg                   overflow,
    output reg                   zero,
    output reg                   negative,
    output reg                   illegal_op
);
    `include "alu_opcodes.vh"

    // Verilog-2001 has no elaboration-time $error. Instantiating a module
    // that does not exist makes any tool stop with an error naming it.
    generate
        if (DATA_WIDTH < 2) begin : g_param_check
            ERROR_alu_top_DATA_WIDTH_must_be_at_least_2 u_error ();
        end
    endgenerate

    // ------------------------------------------------------------------
    // Execution units
    // ------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] arith_result;
    wire                  arith_carry;
    wire                  arith_overflow;
    wire [DATA_WIDTH-1:0] logic_result;
    wire [DATA_WIDTH-1:0] shift_result;

    alu_arith #(
        .DATA_WIDTH (DATA_WIDTH),
        .USE_RCA    (USE_RCA)
    ) u_arith (
        .a        (a),
        .b        (b),
        .opcode   (opcode),
        .result   (arith_result),
        .carry    (arith_carry),
        .overflow (arith_overflow)
    );

    alu_logic #(.DATA_WIDTH(DATA_WIDTH)) u_logic (
        .a      (a),
        .b      (b),
        .opcode (opcode),
        .result (logic_result)
    );

    alu_shifter #(.DATA_WIDTH(DATA_WIDTH)) u_shifter (
        .a      (a),
        .b      (b),
        .opcode (opcode),
        .result (shift_result)
    );

    // ------------------------------------------------------------------
    // Decode and result selection
    // ------------------------------------------------------------------
    // Listing the legal opcodes (not the illegal ones) makes every code
    // that is not named here illegal by default.
    reg legal;
    always @(*) begin
        case (opcode)
            OP_ADD, OP_SUB, OP_INC, OP_DEC, OP_NEG, OP_SLTU, OP_SLT, OP_EQ,
            OP_AND, OP_OR, OP_XOR, OP_NOT, OP_NAND, OP_NOR, OP_XNOR,
            OP_SLL, OP_SRL, OP_SRA, OP_ROL, OP_ROR,
            OP_PASSA, OP_PASSB, OP_CLR:
                legal = 1'b1;
            default:
                legal = 1'b0;
        endcase
    end

    reg [DATA_WIDTH-1:0] move_result;
    always @(*) begin
        case (opcode)
            OP_PASSA: move_result = a;
            OP_PASSB: move_result = b;
            default:  move_result = {DATA_WIDTH{1'b0}};   // OP_CLR
        endcase
    end

    reg [DATA_WIDTH-1:0] next_result;
    reg                  next_carry;
    reg                  next_overflow;
    always @(*) begin
        next_result   = {DATA_WIDTH{1'b0}};
        next_carry    = 1'b0;
        next_overflow = 1'b0;
        if (legal) begin
            case (opcode[4:3])
                CLASS_ARITH: begin
                    next_result   = arith_result;
                    next_carry    = arith_carry;
                    next_overflow = arith_overflow;
                end
                CLASS_LOGIC: next_result = logic_result;
                CLASS_SHIFT: next_result = shift_result;
                default:     next_result = move_result;   // CLASS_MOVE
            endcase
        end
    end

    // next_result is forced to 0 for illegal opcodes, so negative needs no
    // extra gating; zero does, because an illegal result is 0.
    wire next_zero     = legal & (next_result == {DATA_WIDTH{1'b0}});
    wire next_negative = next_result[DATA_WIDTH-1];

    // ------------------------------------------------------------------
    // Output registers
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out  <= 1'b0;
            result     <= {DATA_WIDTH{1'b0}};
            carry      <= 1'b0;
            overflow   <= 1'b0;
            zero       <= 1'b0;
            negative   <= 1'b0;
            illegal_op <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result     <= next_result;
                carry      <= next_carry;
                overflow   <= next_overflow;
                zero       <= next_zero;
                negative   <= next_negative;
                illegal_op <= ~legal;
            end
        end
    end
endmodule

`default_nettype wire
