`timescale 1ns / 1ps

//fetches memory at instruction address and feeds actual instructions to the decoder

module imem (
    input logic [31:0] addr,
    output logic [31:0] inst
    );

    logic [31:0] imem [0:255];   // 256 words of instruction memory for small test program

    initial begin
        imem[0] = 32'h00500093;  // addi x1, x0, 5
        imem[1] = 32'h00300113;  // addi x2, x0, 3
        imem[2] = 32'h002081B3;  // add  x3, x1, x2
        imem[3] = 32'h40208233;  // sub  x4, x1, x2
    end


    assign inst = imem[addr[9:2]]; //uses address to read memory and assign instruction

endmodule
