`timescale 1ns / 1ps

//instantiates and wires all components

module core (

    input logic clk,
    input logic rst
    
    );
    
    //internal wires
    
    //fetch
    logic [31:0] pc_addr;
    logic [31:0] next_pc;
    logic [31:0] inst;
   
    //decoder outputs
    logic [4:0] rd;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic reg_write;
    logic [3:0] alu_op;
    logic alu_src;
    logic [2:0] imm_sel;
    logic branch;
    logic [2:0] func3;
    logic mem_read;
    logic mem_write;
    
    // datapath
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm;
    logic [31:0] alu_b;
    logic [31:0] alu_result;
    logic branch_taken;
    logic branch_cond;
    logic [31:0]branch_target;
    logic jmp;
    logic jmpr;
    logic [31:0] jalr_target;
    logic [31:0] pc_plus4;
    logic [31:0] wb_data;
    logic        take_pc_rel;
    logic [31:0] mem_rdata;
    
    
    // dedicated branch comparator
    
    logic br_eq, br_lt, br_ltu;          
    
    assign br_eq  = (rs1_data == rs2_data);                    // equal?
    assign br_lt  = ($signed(rs1_data) < $signed(rs2_data));   // less than (signed)
    assign br_ltu = (rs1_data < rs2_data);                     // less than (unsigned)
    assign pc_plus4    = pc_addr + 32'd4;
    
    
    //branch logic
    always_comb begin
        case (func3)
            3'b000:  branch_cond =  br_eq;    // beq
            3'b001:  branch_cond = ~br_eq;    // bne
            3'b100:  branch_cond =  br_lt;    // blt
            3'b101:  branch_cond = ~br_lt;    // bge   (>= is NOT <)
            3'b110:  branch_cond =  br_ltu;   // bltu
            3'b111:  branch_cond = ~br_ltu;   // bgeu
            default: branch_cond = 1'b0;
        endcase
    end
    
    //branch is branch flag from op code, branch cond determines if condition is met
    assign branch_taken = branch & branch_cond;
    assign branch_target = pc_addr + imm;
    
    //jumps
    
    assign take_pc_rel = branch_taken | jmp;    // true for normal jals and branching, flase for jalr
    assign jalr_target = (rs1_data + imm) & ~32'd1;             // return address for jalr
    
    
    assign next_pc = take_pc_rel ? branch_target : (jmpr? jalr_target : pc_plus4); //go to branch address, jal address or increment normally
    assign wb_data = (jmp | jmpr) ? pc_plus4       // jumps: save return address
               : mem_read     ? mem_rdata      // loads: data from memory
               :                alu_result;    // everything else: ALU output
    
    
    //instantiate pc
    pc u_pc (
        .clk(clk),  //clc and reset need to be wired up as well!!
        .rst(rst),
        .next_pc(next_pc),
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
        .rd_data(wb_data)
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
        .func3(func3), 
        .func7(),
        .reg_write(reg_write),
        .imm_sel(imm_sel),
        .alu_op(alu_op),
        .alu_src(alu_src),
        .branch(branch),
        .jmp(jmp),
        .jmpr(jmpr),
        .mem_read(mem_read),
        .mem_write(mem_write)
        
    );
    
    imm_gen u_imm_gen(
        .inst(inst),
        .ctrl(imm_sel),
        .imm(imm)
    );
    
    dmem u_dmem(
        .clk(clk), 
        .addr(alu_result),
        .w_e(mem_write),
        .w_data(rs2_data), //memory writes to rs2
        .r_data(mem_rdata)
        
    );
    
    //mux to select between immediate and rs2 for alu input
    assign alu_b = alu_src ? imm : rs2_data;
    
    
    
endmodule