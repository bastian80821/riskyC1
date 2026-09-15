`timescale 1ns/1ps
module tb_mem;
  logic [2:0] func3; logic [1:0] addr_lo; logic mem_write;
  logic [31:0] store_data, w_data, raw_rdata, load_data; logic [3:0] w_strb;
  int errors=0;
  mem_access dut(.*);

  task automatic chk_store(input [2:0] f3, input [1:0] al, input [31:0] sd,
                           input [3:0] exp_strb, input [31:0] exp_lane, input string n);
    func3=f3; addr_lo=al; mem_write=1; store_data=sd; #1;
    if(w_strb!==exp_strb) begin
      $display("  FAIL %-14s strb=%b expected %b",n,w_strb,exp_strb); errors++; end
    else if (((w_data & {{8{exp_strb[3]}},{8{exp_strb[2]}},{8{exp_strb[1]}},{8{exp_strb[0]}}})
           !== (exp_lane & {{8{exp_strb[3]}},{8{exp_strb[2]}},{8{exp_strb[1]}},{8{exp_strb[0]}}}))) begin
      $display("  FAIL %-14s data=%08h expected %08h in lanes",n,w_data,exp_lane); errors++; end
    else $display("  PASS %-14s strb=%b data=%08h",n,w_strb,w_data);
  endtask

  task automatic chk_load(input [2:0] f3, input [1:0] al, input [31:0] raw,
                          input [31:0] exp, input string n);
    func3=f3; addr_lo=al; mem_write=0; raw_rdata=raw; #1;
    if(load_data!==exp) begin
      $display("  FAIL %-14s got %08h expected %08h",n,load_data,exp); errors++; end
    else $display("  PASS %-14s %08h",n,exp);
  endtask

  initial begin
    $display("\n===== mem_access testbench =====\n");
    $display("stores:");
    chk_store(3'b000,2'd0,32'h000000AB,4'b0001,32'hABABABAB,"sb lane0");
    chk_store(3'b000,2'd1,32'h000000AB,4'b0010,32'hABABABAB,"sb lane1");
    chk_store(3'b000,2'd2,32'h000000AB,4'b0100,32'hABABABAB,"sb lane2");
    chk_store(3'b000,2'd3,32'h000000AB,4'b1000,32'hABABABAB,"sb lane3");
    chk_store(3'b001,2'd0,32'h0000BEEF,4'b0011,32'hBEEFBEEF,"sh low");
    chk_store(3'b001,2'd2,32'h0000BEEF,4'b1100,32'hBEEFBEEF,"sh high");
    chk_store(3'b010,2'd0,32'hDEADBEEF,4'b1111,32'hDEADBEEF,"sw");

    $display("\nloads (signed):");
    chk_load(3'b000,2'd0,32'h000000FF,32'hFFFFFFFF,"lb neg lane0");
    chk_load(3'b000,2'd1,32'h0000FF00,32'hFFFFFFFF,"lb neg lane1");
    chk_load(3'b000,2'd3,32'h7F000000,32'h0000007F,"lb pos lane3");
    chk_load(3'b001,2'd0,32'h0000FFFE,32'hFFFFFFFE,"lh neg low");
    chk_load(3'b001,2'd2,32'h7FFF0000,32'h00007FFF,"lh pos high");

    $display("\nloads (unsigned):");
    chk_load(3'b100,2'd0,32'h000000FF,32'h000000FF,"lbu lane0");
    chk_load(3'b100,2'd2,32'h00FF0000,32'h000000FF,"lbu lane2");
    chk_load(3'b101,2'd0,32'h0000FFFE,32'h0000FFFE,"lhu low");
    chk_load(3'b101,2'd2,32'hFFFF0000,32'h0000FFFF,"lhu high");
    chk_load(3'b010,2'd0,32'hDEADBEEF,32'hDEADBEEF,"lw");

    if(errors==0) $display("\n===== ALL PASS =====\n");
    else $display("\n===== %0d FAILED =====\n",errors);
    $finish;
  end
endmodule
