`timescale 1ns / 1ps
// UART integration test: loads a program that prints "HI\n" over the memory-mapped
// UART, decodes the serial output, and traces every memory-stage access so the
// hardware/software interaction is visible.
module uart_hello_tb;

    localparam int CPB = 100_000_000 / 115_200;   // 868 cycles per bit

    logic clk = 0;
    logic rst = 1;
    logic uart_tx_pin;
    int   errors = 0;

    core_pipelined dut (
        .clk(clk),
        .rst(rst),
        .uart_tx_pin(uart_tx_pin)
        // debug_* outputs left unconnected
    );

    always #5 clk = ~clk;

    // ---------------- UART receiver ----------------
    // Watches the tx pin exactly as a terminal would: wait for the start bit,
    // sample the middle of each data bit, reassemble LSB-first.
    int rx_count = 0;
    logic [7:0] rx_bytes [0:15];

    initial begin
        logic [7:0] b;
        forever begin
            @(negedge uart_tx_pin);
            repeat (CPB + CPB/2) @(posedge clk);
            for (int i = 0; i < 8; i++) begin
                b[i] = uart_tx_pin;
                repeat (CPB) @(posedge clk);
            end
            $display("  [%0t] RX byte: 0x%02h", $time, b);
            if (rx_count < 16) rx_bytes[rx_count] = b;
            rx_count++;
        end
    end

    // ---------------- memory-stage trace ----------------
    // Prints every cycle in which the MEM stage performs a load or a store.
    initial begin
        @(negedge rst);
        forever begin
            @(posedge clk);
            if (dut.mem_mem_write || dut.mem_mem_read)
                $display("  MEM  pc=%0d  memW=%b memR=%b  addr=0x%08h  uart_sel=%b  tx_start=%b  tx_data=0x%02h  busy=%b",
                         dut.pc_addr, dut.mem_mem_write, dut.mem_mem_read,
                         dut.mem_alu_result, dut.uart_sel, dut.tx_start,
                         dut.tx_data, dut.tx_busy);
        end
    end

    // ---------------- main ----------------
    initial begin
        $display("\n===== UART hello test =====\n");

        for (int i = 0; i < 256; i++) dut.u_imem.imem[i] = 32'd0;
        $readmemh("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/hello_test.hex",
                  dut.u_imem.imem);

        repeat (4) @(posedge clk);
        rst = 0;

        repeat (40000) @(posedge clk);

        $display("\n  Received %0d bytes:", rx_count);
        for (int i = 0; i < rx_count && i < 16; i++)
            $display("    [%0d] 0x%02h", i, rx_bytes[i]);

        if (rx_count == 3 && rx_bytes[0] == 8'h48
                          && rx_bytes[1] == 8'h49
                          && rx_bytes[2] == 8'h0A)
            $display("\n===== PASS: core transmitted H, I, newline =====\n");
        else begin
            $display("\n===== FAIL: expected 0x48 0x49 0x0A =====\n");
            errors++;
        end

        $finish;
    end
endmodule
