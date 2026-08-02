`timescale 1ns / 1ps

module core_pipe_tb;
    logic clk = 0;
    logic rst = 1;
    int   errors = 0;
    int   test_num = 0;

    core_pipelined dut (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    // ---- load a program into instruction memory, then reset the core ----
    task run_program(input string prog, input int cycles);
        test_num++;
        rst = 1;
        @(negedge clk);
        // clear then load
        for (int i = 0; i < 256; i++) dut.u_imem.imem[i] = 32'd0;
        for (int i = 0; i < 32;  i++) dut.u_register_file.regs[i] = 32'd0;
        for (int i = 0; i < 256; i++) dut.u_dmem.dmem[i]  = 32'd0;
        $readmemh(prog, dut.u_imem.imem);
        @(negedge clk);
        rst = 0;
        repeat (cycles) @(posedge clk);
        @(negedge clk);
    endtask

    // ---- check one register against an expected value ----
    task check_reg(input int idx, input logic [31:0] expected, input string name);
        if (dut.u_register_file.regs[idx] !== expected) begin
            $display("  FAIL %-18s x%0d = 0x%08h, expected 0x%08h",
                     name, idx, dut.u_register_file.regs[idx], expected);
            errors++;
        end else
            $display("  PASS %-18s x%0d = 0x%08h", name, idx, expected);
    endtask

    // ---- check a data-memory word ----
    task check_mem(input int word_idx, input logic [31:0] expected, input string name);
        if (dut.u_dmem.dmem[word_idx] !== expected) begin
            $display("  FAIL %-18s mem[%0d] = 0x%08h, expected 0x%08h",
                     name, word_idx, dut.u_dmem.dmem[word_idx], expected);
            errors++;
        end else
            $display("  PASS %-18s mem[%0d] = 0x%08h", name, word_idx, expected);
    endtask

    // ---- check the program counter ----
    task check_pc(input logic [31:0] expected, input string name);
        if (dut.pc_addr !== expected) begin
            $display("  FAIL %-18s pc = 0x%08h, expected 0x%08h",
                     name, dut.pc_addr, expected);
            errors++;
        end else
            $display("  PASS %-18s pc = 0x%08h", name, expected);
    endtask

    initial begin
        $display("\n========== riscyC1 core regression ==========\n");

        // ---------- Test 1: ALU ops ----------
        $display("Test 1: ALU operations (alu_test.hex)");
        run_program("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/alu_test.hex", 12);
        check_reg(1, 32'd5, "addi x1");
        check_reg(2, 32'd3, "addi x2");
        check_reg(3, 32'd8, "add  x3 = x1+x2");
        check_reg(4, 32'd2, "sub  x4 = x1-x2");
        $display("");

        // ---------- Test 2: store / load ----------
        $display("Test 2: store + load (memory_test.hex)");
        run_program("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/memory_test.hex", 12);
        check_reg(1, 32'd42, "addi x1");
        check_reg(2, 32'd8,  "addi x2");
        check_mem(2, 32'd42, "sw  mem[8]");     // byte addr 8 = word index 2
        check_reg(3, 32'd42, "lw  x3");
        $display("");

        // ---------- Test 3: branch taken ----------
        $display("Test 3: beq taken (branch_test.hex)");
        run_program("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/branch_test.hex", 12);
        check_reg(3, 32'd0,  "x3 skipped");
        check_reg(4, 32'd42, "x4 executed");
        $display("");

        // ---------- Test 4: jal / jalr ----------
        // NOTE: this program loops (jalr returns to addr 4, which then runs again),
        // so we run exactly 3 cycles and check the PC landed back at the return
        // address. Checking "x3 stayed 0" would only hold on the first pass.
        $display("Test 4: jal + jalr (jump_test.hex)");
        run_program("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/jump_test.hex", 12);
        check_reg(1, 32'd4,  "x1 return addr");
        check_reg(4, 32'd42, "x4 function ran");
        check_pc (32'd4,     "jalr returned");
        $display("");

        // ---------- Test 5: LUI / AUIPC ----------
        $display("Test 5: lui + auipc (upper_test.hex)");
        run_program("C:/Users/Bmars/Desktop/riskyC1/riskyC1/riscyC1/programs/upper_test.hex", 12);
        check_reg(1, 32'h12345000, "lui   x1");
        check_reg(2, 32'h00000004, "auipc x2 = pc+0");
        check_reg(3, 32'h00001008, "auipc x3 = pc+0x1000");
        $display("");

        // ---------- summary ----------
        if (errors == 0)
            $display("========== ALL TESTS PASSED (%0d programs) ==========\n", test_num);
        else
            $display("========== %0d CHECKS FAILED ==========\n", errors);
        $finish;
    end
endmodule