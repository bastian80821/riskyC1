`timescale 1ns / 1ps

//instruction memory module

module imem (
    input logic [31:0] addr,
    output logic [31:0] inst
    );

    (* rom_style = "block" *) logic [31:0] imem [0:255];   // 256 words of instruction memory for small test program

    //currently used to load a program
    initial begin
    for (int i = 0; i < 256; i++) imem[i] = 32'd0;
        $readmemh("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/alu_test.hex", imem); //ABSOLUTE PATH
    end


    assign inst = imem[addr[9:2]]; //uses address to read memory and assign instruction

endmodule
