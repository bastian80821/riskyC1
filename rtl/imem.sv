`timescale 1ns / 1ps
// Instruction memory with a write port for the bootloader.
// The write port is what makes the contents UNKNOWN at synthesis time, which is
// what forces Vivado to build a general-purpose core rather than specialising
// the datapath to one baked-in program.
module imem (
    input  logic        clk,
    input  logic        we,
    input  logic [31:0] waddr,
    input  logic [31:0] wdata,
    input  logic [31:0] addr,
    output logic [31:0] inst
);
    logic [31:0] imem [0:255];

    initial begin
        for (int i = 0; i < 256; i++) imem[i] = 32'd0;
    end

    always_ff @(posedge clk) begin
        if (we) imem[waddr[9:2]] <= wdata;
    end

    assign inst = imem[addr[9:2]];
endmodule
