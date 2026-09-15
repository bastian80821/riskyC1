`timescale 1ns / 1ps
// Top level for the Arty S7-50.
//
// An MMCM multiplies the board's 12 MHz oscillator up to the system clock. Set
// USE_MMCM to 0 to run directly from the 12 MHz oscillator instead (simpler,
// and useful for bring-up); CLK_FREQ must match whichever is selected, or the
// UART baud timing will be wrong.
module top #(
    parameter bit USE_MMCM  = 1,
    parameter int CLK_FREQ  = 69_900_000,   // must match the actual clock
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,            // 12 MHz, pin F14
    input  logic       rst_btn,        // active-high push button, BTN0
    input  logic       uart_rx_pin,    // from the USB-UART bridge
    output logic       uart_tx_pin,    // to the USB-UART bridge
    output logic [3:0] led
);
    logic sys_clk, mmcm_locked;

    generate
        if (USE_MMCM) begin : g_mmcm
            clk_gen u_clk (.clk_in(clk), .clk_out(sys_clk), .locked(mmcm_locked));
        end else begin : g_direct
            assign sys_clk     = clk;
            assign mmcm_locked = 1'b1;
        end
    endgenerate

    // hold everything in reset until the clock is stable
    logic sys_rst;
    assign sys_rst = rst_btn | ~mmcm_locked;

    logic        rx_valid;
    logic [7:0]  rx_data;
    logic        imem_we;
    logic [31:0] imem_waddr, imem_wdata;
    logic        core_run, loading;

    // the core stays in reset until the bootloader has finished loading
    logic core_rst;
    assign core_rst = sys_rst | ~core_run;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(sys_clk), .rst(sys_rst), .rx(uart_rx_pin),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    bootloader u_boot (
        .clk(sys_clk), .rst(sys_rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .core_run(core_run), .loading(loading)
    );

    core_pipelined #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_core (
        .clk(sys_clk), .rst(core_rst),
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .uart_tx_pin(uart_tx_pin),
        .debug_pc(), .debug_wb_data(), .debug_wb_rd(), .debug_wb_reg_write()
    );

    // LD2 loading, LD3 running, LD4 MMCM locked
    assign led = {1'b0, mmcm_locked, core_run, loading};
endmodule
