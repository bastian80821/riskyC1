`timescale 1ns / 1ps
    //data memory module
module dmem(
    input logic clk, //synchronous writes
    input logic [31:0] addr, //memory address
    input logic w_e,    //register write enable
    input logic [31:0] w_data,  //data written to register 
    output logic [31:0] r_data  // data read from memory
    );
    
    logic [31:0] dmem [0:255]; //1kb DATA memory (256 32-bit words)
    
    initial begin //initialize memory
    for (int i = 0; i < 256; i++) dmem[i] = 32'd0;
    end
    
    //write to memory
    always_ff @(posedge clk) begin
        if(w_e)
            dmem[addr[9:2]]  <= w_data;
    end

    //read from memory
    assign r_data = dmem[addr[9:2]];

endmodule