`timescale 1ns / 1ps

module alu_tb;
    // 1. Signals to drive and observe the DUT
    logic [31:0] a, b, res;
    logic [3:0] ctrl;
    int          errors = 0;

    // 2. Instantiate and wire register_file
    alu dut (
        .a(a), .b(b), .res(res), .ctrl(ctrl)
    );

    task check(input [31:0] a_in, input [31:0] b_in, input [3:0] op,
           input [31:0] expected, input string name);
    a = a_in; b = b_in; ctrl = op; #1;
    if (res !== expected) begin
        $display("FAIL %s: got 0x%08h expected 0x%08h", name, res, expected);
        errors++;
    end else
        $display("PASS %s: 0x%08h", name, res);
    endtask
    
    initial begin
        // --- simple arithmetic / logic ---
        check(32'd2,  32'd3,  dut.ALU_ADD,  32'd5,        "add");
        check(32'd10, 32'd3,  dut.ALU_SUB,  32'd7,        "sub");
        check(32'd3,  32'd2,  dut.ALU_AND,  32'd2,        "and");
        check(32'd4,  32'd2,  dut.ALU_OR,   32'd6,        "or");
        check(32'hFF00FF00, 32'h0F0F0F0F, dut.ALU_XOR, 32'hF00FF00F, "xor");

        // --- shifts (shift amount = b[4:0]) ---
        check(32'h00000001, 32'd4, dut.ALU_SLL, 32'h00000010, "sll");
        check(32'h00000010, 32'd4, dut.ALU_SRL, 32'h00000001, "srl");

        // --- edge cases
        // SRA vs SRL on the same negative input: sign-fill vs zero-fill
        check(32'hFFFFFFF0, 32'd4, dut.ALU_SRA, 32'hFFFFFFFF, "sra_negative");
        check(32'hFFFFFFF0, 32'd4, dut.ALU_SRL, 32'h0FFFFFFF, "srl_compare");

        // SLT vs SLTU on identical bits: -1 signed vs ~4.29e9 unsigned
        check(32'hFFFFFFFF, 32'd1, dut.ALU_SLT,  32'd1, "slt_signed");   // -1 < 1  -> 1
        check(32'hFFFFFFFF, 32'd1, dut.ALU_SLTU, 32'd0, "sltu_unsigned");// big >= 1 -> 0

        // sanity checks
        check(32'd5, 32'd10, dut.ALU_SLT,  32'd1, "slt_basic");   // 5 < 10 -> 1
        check(32'd10, 32'd5, dut.ALU_SLT,  32'd0, "slt_basic2");  // 10 < 5 -> 0

        // --- summary ---
        if (errors == 0) $display("\n==== ALL TESTS PASSED ====");
        else             $display("\n==== %0d FAILED ====", errors);
        $finish; 
        
    end
    
endmodule