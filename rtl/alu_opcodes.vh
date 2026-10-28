// alu_opcodes.vh -- opcode and operation-class encodings.
//
// Verilog-2001 has no packages, so shared constants live in this file and are
// `include'd *inside* each module body. Every including module gets its own
// scoped localparam copies; nothing is placed in the global `define namespace.
//
// Encoding: opcode[4:3] selects the operation class, opcode[2:0] the operation
// within the class. Codes not listed here are illegal (see alu_top.v).
//
// Each includer uses only some of these constants; the meta-comments below
// stop Verilator from warning about the unused ones.

/* verilator lint_off UNUSEDPARAM */

localparam [1:0] CLASS_ARITH = 2'b00;
localparam [1:0] CLASS_LOGIC = 2'b01;
localparam [1:0] CLASS_SHIFT = 2'b10;
localparam [1:0] CLASS_MOVE  = 2'b11;

// Arithmetic and compare
localparam [4:0] OP_ADD   = 5'b00_000;
localparam [4:0] OP_SUB   = 5'b00_001;
localparam [4:0] OP_INC   = 5'b00_010;
localparam [4:0] OP_DEC   = 5'b00_011;
localparam [4:0] OP_NEG   = 5'b00_100;
localparam [4:0] OP_SLTU  = 5'b00_101;
localparam [4:0] OP_SLT   = 5'b00_110;
localparam [4:0] OP_EQ    = 5'b00_111;

// Bitwise logic (5'b01_111 is illegal)
localparam [4:0] OP_AND   = 5'b01_000;
localparam [4:0] OP_OR    = 5'b01_001;
localparam [4:0] OP_XOR   = 5'b01_010;
localparam [4:0] OP_NOT   = 5'b01_011;
localparam [4:0] OP_NAND  = 5'b01_100;
localparam [4:0] OP_NOR   = 5'b01_101;
localparam [4:0] OP_XNOR  = 5'b01_110;

// Shifts and rotates (5'b10_101 .. 5'b10_111 are illegal)
localparam [4:0] OP_SLL   = 5'b10_000;
localparam [4:0] OP_SRL   = 5'b10_001;
localparam [4:0] OP_SRA   = 5'b10_010;
localparam [4:0] OP_ROL   = 5'b10_011;
localparam [4:0] OP_ROR   = 5'b10_100;

// Data movement (5'b11_011 .. 5'b11_111 are illegal)
localparam [4:0] OP_PASSA = 5'b11_000;
localparam [4:0] OP_PASSB = 5'b11_001;
localparam [4:0] OP_CLR   = 5'b11_010;
/* verilator lint_on UNUSEDPARAM */
