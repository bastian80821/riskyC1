`timescale 1ns / 1ps

module imm_gen_tb;
    // 1. Signals to drive/observe the DUT
    logic [31:0] inst;
    logic [2:0]  ctrl;
    logic [31:0] imm;
    int          errors = 0;

    // 2. Instantiate the DUT
    imm_gen dut (
        .inst(inst), .ctrl(ctrl), .imm(imm)
    );

    // 3. Self-checking task (combinational: drive, settle, compare)
    task check(input [31:0] inst_in, input [2:0] op,
               input [31:0] expected, input string name);
        inst = inst_in; ctrl = op; #1;
        if (imm !== expected) begin
            $display("FAIL %-14s: inst=0x%08h -> imm=0x%08h, expected 0x%08h",
                     name, inst_in, imm, expected);
            errors++;
        end else
            $display("PASS %-14s: inst=0x%08h -> imm=0x%08h", name, inst_in, imm);
    endtask

    // 4. Test sequence
    initial begin
        // op-code aliases (must match the DUT's localparams)
        localparam logic [2:0] I = 3'd0, S = 3'd1, B = 3'd2, U = 3'd3, J = 3'd4;

        // --- I-type: imm = inst[31:20], sign-extended ---
        check(32'h00A00000, I, 32'h0000000A, "I positive");   // +10
        check(32'hFFF00000, I, 32'hFFFFFFFF, "I negative");   // -1

        // --- S-type: imm = {inst[31:25], inst[11:7]} ---
        check(32'h00000500, S, 32'h0000000A, "S positive");   // +10
        check(32'hFE000F00, S, 32'hFFFFFFFE, "S negative");   // -2

        // --- B-type: scrambled, bit0 = 0 ---
        check(32'h00000800, B, 32'h00000010, "B positive");   // +16
        check(32'hFE000F80, B, 32'hFFFFFFFE, "B negative");   // -2

        // --- U-type: imm = {inst[31:12], 12'b0}, no sign-extend ---
        check(32'h12345ABC, U, 32'h12345000, "U value");

        // --- J-type: scrambled, bit0 = 0 ---
        check(32'h00400000, J, 32'h00000004, "J positive");   // +4
        check(32'hFFFFF000, J, 32'hFFFFFFFE, "J negative");   // -2

        // --- summary ---
        if (errors == 0) $display("\n==== ALL TESTS PASSED ====");
        else             $display("\n==== %0d FAILED ====", errors);
        $finish;
    end
endmodule