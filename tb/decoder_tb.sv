`timescale 1ns / 1ps

module decoder_tb;
    // DUT signals
    logic [31:0] inst;
    logic [6:0]  opc;
    logic [4:0]  rd, rs1, rs2;
    logic [2:0]  func3;
    logic [6:0]  func7;
    logic        reg_write;
    logic [2:0]  imm_sel;
    logic [3:0]  alu_op;
    logic        alu_src;
    int          errors = 0;

    decoder dut (
        .inst(inst), .opc(opc), .rd(rd), .rs1(rs1), .rs2(rs2),
        .func3(func3), .func7(func7), .reg_write(reg_write),
        .imm_sel(imm_sel), .alu_op(alu_op), .alu_src(alu_src)
    );

    // Check the four control signals the decoder generates
    task check(input [31:0] inst_in,
               input        exp_rw,
               input        exp_src,
               input [3:0]  exp_alu,
               input [2:0]  exp_imm,
               input string name);
        inst = inst_in; #1;
        if (reg_write !== exp_rw || alu_src !== exp_src ||
            alu_op !== exp_alu || imm_sel !== exp_imm) begin
            $display("FAIL %-10s: inst=0x%08h  rw=%b src=%b alu=%0d imm=%0d  (exp rw=%b src=%b alu=%0d imm=%0d)",
                     name, inst_in, reg_write, alu_src, alu_op, imm_sel,
                     exp_rw, exp_src, exp_alu, exp_imm);
            errors++;
        end else
            $display("PASS %-10s: inst=0x%08h  rw=%b src=%b alu=%0d imm=%0d",
                     name, inst_in, reg_write, alu_src, alu_op, imm_sel);
    endtask

    initial begin
        // op-encodings: ADD=0 SUB=1 AND=2 OR=3 XOR=4 SLL=5 SRL=6 SRA=7 SLT=8 SLTU=9
        // imm: I=0 S=1 B=2 U=3 J=4

        //          instruction    rw src alu imm   name
        // R-type: add/sub prove funct7; srl/sra prove the shift funct7
        check(32'h003100B3, 1, 0, 4'd0, 3'd0, "add");   // add  x1,x2,x3
        check(32'h403100B3, 1, 0, 4'd1, 3'd0, "sub");   // sub  x1,x2,x3
        check(32'h003150B3, 1, 0, 4'd6, 3'd0, "srl");   // srl  x1,x2,x3
        check(32'h403150B3, 1, 0, 4'd7, 3'd0, "sra");   // sra  x1,x2,x3

        // I-ALU
        check(32'h00510093, 1, 1, 4'd0, 3'd0, "addi");  // addi x1,x2,5
        check(32'h00517093, 1, 1, 4'd2, 3'd0, "andi");  // andi x1,x2,5
        check(32'h40315093, 1, 1, 4'd7, 3'd0, "srai");  // srai x1,x2,3

        // Load (I-format)
        check(32'h00812083, 1, 1, 4'd0, 3'd0, "lw");    // lw   x1,8(x2)

        // Store (S-format) - reg_write MUST be 0
        check(32'h00312423, 0, 1, 4'd0, 3'd1, "sw");    // sw   x3,8(x2)

        // Branch (B-format) - reg_write MUST be 0, src register
        check(32'h00208063, 0, 0, 4'd0, 3'd2, "beq");   // beq  x1,x2,0

        // LUI (U-format)
        check(32'h123450B7, 1, 1, 4'd0, 3'd3, "lui");   // lui  x1,0x12345

        // JAL (J-format)
        check(32'h000000EF, 1, 0, 4'd0, 3'd4, "jal");   // jal  x1,0

        if (errors == 0) $display("\n==== ALL TESTS PASSED ====");
        else             $display("\n==== %0d FAILED ====", errors);
        $finish;
    end
endmodule