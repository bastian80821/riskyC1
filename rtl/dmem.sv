`timescale 1ns / 1ps
// Data memory, 1024 words (4 KB), with a second write port for the bootloader.
//
// The bootloader mirrors the loaded image into BOTH imem and dmem at the same
// addresses. riscyC1 is a Harvard machine - separate instruction and data
// address spaces both starting at 0 - so without mirroring, a program's .data
// section would be written into imem where loads could never reach it.
module dmem (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        w_e,
    input  logic [31:0] w_data,
    output logic [31:0] r_data,
    // bootloader port (takes priority; the core is held in reset during load)
    input  logic        boot_we,
    input  logic [31:0] boot_waddr,
    input  logic [31:0] boot_wdata
);
    logic [31:0] dmem [0:1023];

    initial begin
        for (int i = 0; i < 1024; i++) dmem[i] = 32'd0;
    end

    always_ff @(posedge clk) begin
        if (boot_we)   dmem[boot_waddr[11:2]] <= boot_wdata;
        else if (w_e)  dmem[addr[11:2]]       <= w_data;
    end

    assign r_data = dmem[addr[11:2]];
endmodule
