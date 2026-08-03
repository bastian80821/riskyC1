`timescale 1ns / 1ps
// Self-checking testbench for uart_tx.
// Uses a deliberately small CYCLES_PER_BIT (1 MHz clk / 100k baud = 10 cycles per
// bit) so the simulation runs fast -- at the real 868 cycles/bit a single byte
// would take ~8700 cycles to transmit.
module uart_tx_tb;
    localparam int CLK_FREQ = 1_000_000;
    localparam int BAUD     = 100_000;
    localparam int CPB      = CLK_FREQ / BAUD;   // cycles per bit = 10

    logic       clk = 0, rst = 1, tx_start = 0;
    logic [7:0] tx_data;
    logic       tx, tx_busy;
    int         errors = 0;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD)) dut (
        .clk(clk), .rst(rst), .tx_start(tx_start),
        .tx_data(tx_data), .tx(tx), .tx_busy(tx_busy)
    );

    always #5 clk = ~clk;

    // A UART receiver: wait for the start bit, skip to the middle of each data
    // bit, sample, reassemble the byte LSB-first, then check the stop bit.
    task automatic receive(output logic [7:0] got);
        logic [7:0] b;
        @(negedge tx);                        // falling edge = start bit
        repeat (CPB + CPB/2) @(posedge clk);  // skip start bit, land mid-bit0
        for (int i = 0; i < 8; i++) begin
            b[i] = tx;                        // LSB first
            repeat (CPB) @(posedge clk);
        end
        got = b;
        if (tx !== 1'b1) begin
            $display("  FAIL: stop bit was not high");
            errors++;
        end
    endtask

    task automatic send_and_check(input logic [7:0] val, input string name);
        logic [7:0] got;
        fork
            begin
                @(negedge clk);
                tx_data  = val;
                tx_start = 1;
                @(negedge clk);
                tx_start = 0;
            end
            receive(got);
        join
        if (got !== val) begin
            $display("  FAIL %-10s sent 0x%02h, received 0x%02h", name, val, got);
            errors++;
        end else
            $display("  PASS %-10s 0x%02h", name, val);
        wait (!tx_busy);
        repeat (5) @(posedge clk);
    endtask

    initial begin
        $display("\n===== uart_tx testbench =====\n");
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (3) @(posedge clk);

        if (tx !== 1'b1) begin
            $display("  FAIL idle       line not high before transmission");
            errors++;
        end else
            $display("  PASS idle       line high before transmission");

        send_and_check(8'h48, "H");         // 'H'
        send_and_check(8'h69, "i");         // 'i'
        send_and_check(8'h0A, "newline");
        send_and_check(8'h00, "0x00");      // all data bits low
        send_and_check(8'hFF, "0xFF");      // all data bits high
        send_and_check(8'hA5, "0xA5");      // alternating pattern

        if (errors == 0) $display("\n===== ALL TESTS PASSED =====\n");
        else             $display("\n===== %0d FAILED =====\n", errors);
        $finish;
    end
endmodule
