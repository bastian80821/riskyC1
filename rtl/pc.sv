`timescale 1ns / 1ps

//the whole point of this module is to output and increment the ADDRESS of the instructions

module pc (
    input  logic       clk,    //clock
    input logic        rst,     //1 bit reset
    input logic[31:0]  next_pc,
    output logic [31:0] pc //instruction address
);



    //register incrementing instructions
    always_ff @(posedge clk) begin
        if(rst)
            pc <= 32'd0;
        else 
            pc <= next_pc;
    end


endmodule 