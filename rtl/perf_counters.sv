`timescale 1ns / 1ps
// Memory-mapped performance counters.
//
// riscyC1 has no CSRs, so mcycle/minstret are not available. These counters
// expose the same information through the I/O address space:
//
//   0x1008  cycles retired since reset
//   0x100C  instructions retired since reset
//
// IPC = instret / cycles. A program reads both, and the difference between two
// readings measures a region of interest.
module perf_counters (
    input  logic        clk,
    input  logic        rst,
    input  logic        instr_retired,   // one instruction completed this cycle
    output logic [31:0] cycle_count,
    output logic [31:0] instret_count
);
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count   <= 32'd0;
            instret_count <= 32'd0;
        end else begin
            cycle_count <= cycle_count + 32'd1;
            if (instr_retired) instret_count <= instret_count + 32'd1;
        end
    end
endmodule
