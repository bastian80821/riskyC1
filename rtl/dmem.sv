`timescale 1ns / 1ps
// Data memory, 1024 words (4 KB), with byte-granular writes.
//
// Byte enables (w_strb) let sb/sh write part of a word without disturbing the
// rest. A word is stored as four independently-writable lanes.
//
// The bootloader port mirrors the loaded image into this memory as well as
// imem: riscyC1 is a Harvard machine with separate instruction and data address
// spaces both starting at 0, so without mirroring a program's .data section
// would land in imem where loads could never reach it.
module dmem (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic [3:0]  w_strb,      // per-byte write enable
    input  logic [31:0] w_data,
    output logic [31:0] r_data,
    // bootloader port (takes priority; the core is held in reset during load)
    input  logic        boot_we,
    input  logic [31:0] boot_waddr,
    input  logic [31:0] boot_wdata
);
    logic [7:0] mem0 [0:1023];
    logic [7:0] mem1 [0:1023];
    logic [7:0] mem2 [0:1023];
    logic [7:0] mem3 [0:1023];

    initial begin
        for (int i = 0; i < 1024; i++) begin
            mem0[i] = 8'd0; mem1[i] = 8'd0; mem2[i] = 8'd0; mem3[i] = 8'd0;
        end
    end

    logic [9:0] widx, bidx, ridx;
    assign widx = addr[11:2];
    assign bidx = boot_waddr[11:2];
    assign ridx = addr[11:2];

    always_ff @(posedge clk) begin
        if (boot_we) begin
            mem0[bidx] <= boot_wdata[7:0];
            mem1[bidx] <= boot_wdata[15:8];
            mem2[bidx] <= boot_wdata[23:16];
            mem3[bidx] <= boot_wdata[31:24];
        end else begin
            if (w_strb[0]) mem0[widx] <= w_data[7:0];
            if (w_strb[1]) mem1[widx] <= w_data[15:8];
            if (w_strb[2]) mem2[widx] <= w_data[23:16];
            if (w_strb[3]) mem3[widx] <= w_data[31:24];
        end
    end

    assign r_data = {mem3[ridx], mem2[ridx], mem1[ridx], mem0[ridx]};
endmodule
