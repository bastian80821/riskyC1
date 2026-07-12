`timescale 1ns / 1ps

//fetches memory at instruction address and feeds actual instructions to the decoder

module imem (
    input logic [31:0] addr,
    output logic [31:0] inst
    );

    logic [31:0] imem [0:255];   // 256 words of instruction memory for small test program

    //currently used to load a program
    initial begin
         imem[0] = 32'h008000EF;  // jal  x1, +8      jump to 8, save return addr (4) in x1
    imem[1] = 32'h06300193;  // addi x3, x0, 99  <-- SKIPPED (jumped over)
    imem[2] = 32'h02A00213;  // addi x4, x0, 42  <-- "the function body"
    imem[3] = 32'h00008067;  // jalr x0, x1, 0   RETURN: jump to address in x1
    imem[4] = 32'h04D00293;  // addi x5, x0, 77  (only reached if return failed)
    end


    assign inst = imem[addr[9:2]]; //uses address to read memory and assign instruction

endmodule
