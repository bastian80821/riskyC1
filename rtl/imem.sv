`timescale 1ns / 1ps

//instruction memory module

module imem (
    input logic [31:0] addr,
    output logic [31:0] inst
    );

    logic [31:0] imem [0:255];   // 256 words of instruction memory for small test program

    //currently used to load a program
    initial begin
    imem[0] = 32'h02A00093;  // addi x1, x0, 42    x1 = 42
    imem[1] = 32'h00800113;  // addi x2, x0, 8     x2 = 8
    imem[2] = 32'h00112023;  // sw   x1, 0(x2)     mem[8] = 42
    imem[3] = 32'h00012183;  // lw   x3, 0(x2)     x3 = mem[8]
    imem[4] = 32'h00000013;  // nop
    end


    assign inst = imem[addr[9:2]]; //uses address to read memory and assign instruction

endmodule
