`timescale 1ns / 1ps

module alu(
    //purely combinational, no clock
    
    input logic [31:0] a, //data input 1
    input logic [31:0] b, //data input 2
    input logic [3:0] ctrl, //control signal, selects operation 
    
    output logic [31:0] res //output result
    
    );
    
    //operation encoding
    localparam logic [3:0] ALU_ADD = 4'd0;    //0 is add
    localparam logic [3:0] ALU_SUB = 4'd1;    //1 is sub
    localparam logic [3:0] ALU_AND = 4'd2;    //2 is and
    localparam logic [3:0] ALU_OR = 4'd3;    //3 is or
    localparam logic [3:0] ALU_XOR = 4'd4;    //4 is xor
    localparam logic [3:0] ALU_SLL = 4'd5;    //5 is shift left
    localparam logic [3:0] ALU_SRL = 4'd6;    //6 is shift right
    localparam logic [3:0] ALU_SRA = 4'd7;    //7 is arithmetic right shift
    localparam logic [3:0] ALU_SLT = 4'd8;    //8 is set less than 
    localparam logic [3:0] ALU_SLTU = 4'd9;    //9 is set less than unsigned
    
    
    always_comb begin
    case (ctrl)
        ALU_ADD: res = a + b; 
        ALU_SUB: res = a - b;
        ALU_AND: res = a & b;
        ALU_OR: res = a | b;
        ALU_XOR: res = a ^ b;
        ALU_SLL: res = a << b[4:0]; //shifting by max of 32 bits which is b[4:0]
        ALU_SRL: res = a >> b[4:0]; //shifting by max of 32 bits which is b[4:0]
        ALU_SRA: res = $signed(a) >>> b[4:0]; //cast makes a signed first
        ALU_SLT: res = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
        ALU_SLTU: res = (a < b) ? 32'd1 : 32'd0;
 
        default: res = '0;   // REQUIRED - prevents an inferred latch
    endcase
end
    
endmodule