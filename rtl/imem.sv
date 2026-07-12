`timescale 1ns / 1ps

//fetches memory at instruction address and feeds actual instructions to the decoder

module imem (
    input logic [31:0] addr,
    output logic [31:0] inst
    );

    logic [31:0] imem [0:255];   // 256 words of instruction memory for small test program

    //currently used to load a program
    initial begin
        imem[0] = 32'h00500093;  // addi x1, x0, 5
        imem[1] = 32'h00700113;  // addi x2, x0, 7    (5 != 7)
        imem[2] = 32'h00209463;  // bne  x1, x2, +8   should TAKE (values differ)
        imem[3] = 32'h06300193;  // addi x3, x0, 99   <-- should be SKIPPED
        imem[4] = 32'h02A00213;  // addi x4, x0, 42
    end


    assign inst = imem[addr[9:2]]; //uses address to read memory and assign instruction

endmodule
