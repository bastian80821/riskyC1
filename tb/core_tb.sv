`timescale 1ns / 1ps
module core_tb;
    logic clk = 0;
    logic rst = 1;

    core dut ( .clk(clk), .rst(rst) );

    always #5 clk = ~clk;    // 10 ns clock

    initial begin
        rst = 1; #12;        // hold reset for one+ cycle
        rst = 0;             // release; core starts fetching
        #50;                 // let it run several cycles
        $finish;
    end
endmodule