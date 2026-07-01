`timescale 1ns / 1ps

module register_file_tb;
    // 1. Signals to drive and observe the DUT
    logic        clk;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] rs1_data, rs2_data, rd_data;
    logic        rd_we;
    int          errors = 0;

    // 2. Instantiate and wire register_file
    register_file dut (
        .clk(clk), .rs1_addr(rs1_addr), .rs1_data(rs1_data),
        .rs2_addr(rs2_addr), .rs2_data(rs2_data),
        .rd_we(rd_we), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    // 3. Clock generator: 10 ns period, toggling every 5 ns
    initial clk = 0;
    always #5 clk = ~clk;

    // 4. Reusable helper: drive a write across one clock edge
    task write_reg(input [4:0] a, input [31:0] d);
        @(negedge clk); rd_we = 1; rd_addr = a; rd_data = d;
        @(posedge clk);              // the write commits here
        @(negedge clk); rd_we = 0;
    endtask

    // 5. Reusable helper: read a register and check it against expected
    task check(input [4:0] a, input [31:0] exp, input string nm);
        rs1_addr = a; #1;            // the #1 lets the combinational read settle
        if (rs1_data !== exp) begin
            $display("FAIL %s: x%0d=0x%08h exp 0x%08h", nm, a, rs1_data, exp);
            errors++;
        end else
            $display("PASS %s: x%0d=0x%08h", nm, a, rs1_data);
    endtask

    // 6. The actual test sequence
    initial begin
        rd_we=0; rd_addr=0; rd_data=0; rs1_addr=0; rs2_addr=0;

        // write then read back
        write_reg(5'd1,  32'hDEAD_BEEF);
        write_reg(5'd2,  32'h1234_5678);
        write_reg(5'd31, 32'hFFFF_FFFF);
        check(5'd1,  32'hDEAD_BEEF, "rw x1");
        check(5'd2,  32'h1234_5678, "rw x2");
        check(5'd31, 32'hFFFF_FFFF, "rw x31");

        // x0 must stay zero even after an attempted write
        write_reg(5'd0, 32'hAAAA_AAAA);
        check(5'd0, 32'h0, "x0 zero");

        // write-enable low must block the write
        @(negedge clk); rd_we=0; rd_addr=5'd5; rd_data=32'hCAFEF00D;
        @(posedge clk); @(negedge clk);
        check(5'd5, 32'h0, "we=0 blocks");

        // both read ports work at once
        rs1_addr=5'd1; rs2_addr=5'd2; #1;
        if (rs1_data!==32'hDEADBEEF || rs2_data!==32'h12345678) begin
            $display("FAIL dual read"); errors++;
        end else $display("PASS dual read");

        if (errors==0) $display("\n==== ALL TESTS PASSED ====");
        else           $display("\n==== %0d FAILED ====", errors);
        $finish;
    end
endmodule