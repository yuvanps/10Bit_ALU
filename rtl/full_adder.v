`timescale 1ns / 1ps
`default_nettype none

// full_adder -- one-bit full adder written as explicit gate equations.
//   sum  = a ^ b ^ cin
//   cout = majority(a, b, cin) = (a & b) | (cin & (a ^ b))
module full_adder (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    wire p = a ^ b;          // propagate
    wire g = a & b;          // generate

    assign sum  = p ^ cin;
    assign cout = g | (p & cin);
endmodule

`default_nettype wire
