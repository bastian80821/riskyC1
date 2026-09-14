`timescale 1ns/1ps
module boot_tb;
  localparam int CLK_FREQ=12_000_000, BAUD=115_200;
  localparam int CPB = CLK_FREQ/BAUD;
  logic clk=0, rst_btn=1, uart_rx_pin=1, uart_tx_pin; logic [3:0] led;
  int errors=0, rx_count=0;
  logic [7:0] rx_bytes[0:15];

  top #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD)) dut(.clk(clk),.rst_btn(rst_btn),
    .uart_rx_pin(uart_rx_pin),.uart_tx_pin(uart_tx_pin),.led(led));
  always #5 clk=~clk;

  // host: send one byte down the serial line
  task automatic host_send(input logic [7:0] b);
    uart_rx_pin=0; repeat(CPB) @(posedge clk);            // start bit
    for(int i=0;i<8;i++) begin uart_rx_pin=b[i]; repeat(CPB) @(posedge clk); end
    uart_rx_pin=1; repeat(CPB) @(posedge clk);            // stop bit
    repeat(2) @(posedge clk);
  endtask
  task automatic host_send_word(input logic [31:0] w);
    host_send(w[7:0]); host_send(w[15:8]); host_send(w[23:16]); host_send(w[31:24]);
  endtask

  // terminal: decode whatever the core transmits
  initial begin
    logic [7:0] b;
    forever begin
      @(negedge uart_tx_pin);
      repeat(CPB+CPB/2) @(posedge clk);
      for(int i=0;i<8;i++) begin b[i]=uart_tx_pin; repeat(CPB) @(posedge clk); end
      $display("  [%0t] TERMINAL RX: 0x%02h", $time, b);
      if(rx_count<16) rx_bytes[rx_count]=b; rx_count++;
    end
  end

  logic [31:0] prog [0:13];
  initial begin
    $display("\n===== bootloader end-to-end test =====\n");
    prog[0]=32'h00001137; prog[1]=32'h04800093; prog[2]=32'h00412203; prog[3]=32'hFE021EE3;
    prog[4]=32'h00112023; prog[5]=32'h04900093; prog[6]=32'h00412203; prog[7]=32'hFE021EE3;
    prog[8]=32'h00112023; prog[9]=32'h00A00093; prog[10]=32'h00412203; prog[11]=32'hFE021EE3;
    prog[12]=32'h00112023; prog[13]=32'h0000006F;

    repeat(10) @(posedge clk); rst_btn=0; repeat(10) @(posedge clk);
    $display("  host: sending word count = 14");
    host_send_word(32'd14);
    $display("  host: sending 14 instruction words...");
    for(int i=0;i<14;i++) host_send_word(prog[i]);
    $display("  host: done. core_run=%b", dut.core_run);
    wait(dut.core_run);
    $display("  [%0t] BOOTLOADER DONE - core released\n", $time);

    repeat(400000) @(posedge clk);
    $display("\n  Terminal received %0d bytes:", rx_count);
    for(int i=0;i<rx_count && i<16;i++) $display("    [%0d] 0x%02h", i, rx_bytes[i]);
    if(rx_count==3 && rx_bytes[0]==8'h48 && rx_bytes[1]==8'h49 && rx_bytes[2]==8'h0A)
      $display("\n===== PASS: program loaded over UART and printed HI =====\n");
    else begin $display("\n===== FAIL =====\n"); errors++; end
    $finish;
  end
endmodule
