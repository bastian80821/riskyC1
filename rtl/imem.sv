`timescale 1ns / 1ps
// Instruction memory, 1024 words (4 KB), with a bootloader write port.
//
// The write port is what makes the contents unknown at synthesis time, forcing
// Vivado to build a general-purpose core rather than specialising the datapath
// to one baked-in program.
module imem (
    input  logic        clk,
    input  logic        we,
    input  logic [31:0] waddr,
    input  logic [31:0] wdata,
    input  logic [31:0] addr,
    output logic [31:0] inst
);
    logic [31:0] imem [0:1023];

    initial begin
        for (int i = 0; i < 1024; i++) imem[i] = 32'd0;
    end

    // addr[11:2] : drop the low 2 bits (byte -> word index), 10 bits for 1024 words
    always_ff @(posedge clk) begin
        if (we) imem[waddr[11:2]] <= wdata;
    end

    assign inst = imem[addr[11:2]];
endmodule
