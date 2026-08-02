`timescale 1ns / 1ps

module register_file (
    input  logic       clk,    //clock
    
    input  logic [4:0]  rs1_addr, //32-bit address of which register gets read into port 1
    output logic [31:0] rs1_data, //32-bit wide output of register read into port 1
    
    input  logic [4:0]  rs2_addr, //32-bit address of whcih register gets read into port 2
    output logic [31:0] rs2_data, //32-bit wide output of register read into port 2
    
    input  logic        rd_we, //write enable 
    input  logic [4:0]  rd_addr, //address of register to write to 
    input logic [31:0] rd_data // data to write to register
);
    logic [31:0] regs [0:31]; //32 registers, each 32-bit wide in an array. for example, x5 would be regs[5]
    initial begin
        for (int i = 0; i < 32; i++) regs[i] = 32'd0;   //initialize all registers to 0
    end
    
    always_ff @(posedge clk) begin //write data to registers unless it's at address 00000 (x0)
        if (rd_we && (rd_addr != 5'd0))
            regs[rd_addr] <= rd_data;
    end
    
    // Combinational reads, with write-first bypass: if this cycle's write
    // targets the register being read, return the incoming data instead of
    // the stored value (the stored value doesn't update until the clock edge).
    assign rs1_data = (rs1_addr == 5'd0)                        ? 32'd0
                    : (rd_we && (rd_addr == rs1_addr))          ? rd_data
                    :                                             regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0)                        ? 32'd0
                    : (rd_we && (rd_addr == rs2_addr))          ? rd_data
                    :                                             regs[rs2_addr];
    
endmodule 