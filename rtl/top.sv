`timescale 1ns / 1ps
// Top level for the Arty S7-50.
// Wires the bootloader, UART receiver, and pipelined core together and exposes
// the board's physical pins.
module top #(
    parameter int CLK_FREQ  = 12_000_000,   // Arty S7 user clock (pin F14)
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_btn,      // active-high push button
    input  logic       uart_rx_pin,  // from the USB-UART bridge
    output logic       uart_tx_pin,  // to the USB-UART bridge
    output logic [3:0] led
);
    logic        rx_valid;
    logic [7:0]  rx_data;
    logic        imem_we;
    logic [31:0] imem_waddr, imem_wdata;
    logic        core_run, loading;

    // The core is held in reset until the bootloader has finished loading.
    logic core_rst;
    assign core_rst = rst_btn | ~core_run;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst_btn), .rx(uart_rx_pin),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    bootloader u_boot (
        .clk(clk), .rst(rst_btn),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .core_run(core_run), .loading(loading)
    );

    core_pipelined #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_core (
        .clk(clk), .rst(core_rst),
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .uart_tx_pin(uart_tx_pin),
        .debug_pc(), .debug_wb_data(), .debug_wb_rd(), .debug_wb_reg_write()
    );

    // status: LD2 = loading, LD3 = running
    assign led = {2'b00, core_run, loading};
endmodule
