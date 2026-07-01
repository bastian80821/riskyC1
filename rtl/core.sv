`timescale 1ns / 1ps

//instantiates and wires all components

module core (

    input logic clk,
    input logic rst
    
    );
    
    //internal wires
    
    //fetch
    logic [31:0] pc_addr;
    logic [31:0] inst;
   
    //decoder outputs
    logic [4:0] rd;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic reg_write;
    logic [3:0] alu_op;
    logic alu_src;
    logic [2:0] imm_sel;
    
    // datapath
    logic [31:0] rs1_data;
    logic [31:0] rs2_data ;
    logic [31:0] imm ;
    logic [31:0] alu_b ;
    logic [31:0] alu_result ;
    
    //instantiate pc
    pc u_pc (
        .clk(clk),  //clc and reset need to be wired up as well!!
        .rst(rst),
        .pc (pc_addr)
    );
    
    //instantiate imem
    imem u_imem (
        .addr (pc_addr),  //wire input
        .inst (inst)      //wire output
    );
    
    register_file u_register_file (
        .clk(clk),
        .rs1_addr(rs1),
        .rs2_addr(rs2),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .rd_we(reg_write),
        .rd_addr(rd),
        .rd_data(alu_result)
    );
    
    alu u_alu (
        .ctrl(alu_op),
        .a(rs1_data),
        .b(alu_b),
        .res(alu_result)
    );
    
    decoder u_decoder (
        .inst(inst),
        .opc(), //decoder extracts these fields, but not routetet anywhere yet 
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),  
        .func3(), 
        .func7(),
        .reg_write(reg_write),
        .imm_sel(imm_sel),
        .alu_op(alu_op),
        .alu_src(alu_src)
        
    );
    
    imm_gen u_imm_gen(
        .inst(inst),
        .ctrl(imm_sel),
        .imm(imm)
    );
    
    
    
    //mux to select between immediate and rs2 for alu input
    assign alu_b = alu_src ? imm : rs2_data;
    
    
    
endmodule