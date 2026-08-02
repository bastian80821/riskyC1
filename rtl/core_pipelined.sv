`timescale 1ns / 1ps
// 5-stage pipelined RV32I core: IF | ID | EX | MEM | WB
// STEP 1: pipeline registers only. No forwarding, no stall detection, no branch
// flushing yet -- data and control hazards are expected to fail.
module core_pipelined (
    input logic clk,
    input logic rst
);

    // **********************************************************
    // INTERNAL WIRES
    // **********************************************************

    //INSTRUCTION FETCH SIGNALS
    logic [31:0] next_pc;      // driven by signals flowing BACKWARD from EX
    logic [31:0] pc_addr;
    logic [31:0] inst;
    logic [31:0] pc_plus4;

    //IF->ID signals
    logic [31:0] id_inst;
    logic [31:0] id_pc_addr;
    logic [31:0] id_pc_plus4;

    //INSTRUCTION DECODE SIGNALS
    logic [4:0]  rd, rs1, rs2;
    logic        reg_write;
    logic [2:0]  imm_sel;      // consumed in ID by imm_gen -- never carried
    logic        jmpr;
    logic        mem_read, mem_write;
    logic        lui, auipc;
    logic        branch, jmp;
    logic [2:0]  func3;
    logic [31:0] rs1_data, rs2_data, imm;
    logic [3:0]  alu_op;
    logic        alu_src;

    //ID->EXE signals
    logic [31:0] exe_rs1_data, exe_rs2_data, exe_imm;
    logic [3:0]  exe_alu_op;
    logic        exe_alu_src;
    logic        exe_branch, exe_jmp;
    logic [2:0]  exe_func3;
    logic [4:0]  exe_rd;
    logic [4:0]  exe_rs1, exe_rs2;     // for the forwarding unit (Step 2)
    logic        exe_reg_write, exe_jmpr;
    logic        exe_mem_read, exe_mem_write;
    logic        exe_lui, exe_auipc;
    logic [31:0] exe_pc_addr, exe_pc_plus4;

    //EXECUTION SIGNALS
    logic [31:0] alu_b, alu_result;
    logic        branch_taken, branch_cond, take_pc_rel;
    logic [31:0] jalr_target, branch_target;
    logic        br_eq, br_lt, br_ltu;

    //EXE->MEM signals
    logic [31:0] mem_alu_result, mem_rs2_data;
    logic [31:0] mem_imm, mem_branch_target, mem_pc_plus4;
    logic        mem_mem_read, mem_mem_write;
    logic        mem_lui, mem_auipc, mem_jmp, mem_jmpr;
    logic        mem_reg_write;
    logic [4:0]  mem_rd;

    //MEMORY ACCESS SIGNALS
    logic [31:0] mem_rdata;
    logic [31:0] mem_wb_data;   // 5-to-1 writeback mux output (resolved in MEM)



    //WRITEBACK SIGNALS
    logic [31:0] wb_data;
    logic [4:0]  wb_rd;
    logic        wb_reg_write;


    // *************************************************************
    // INSTRUCTION FETCH STAGE
    // *************************************************************

    pc u_pc (
        .clk(clk),
        .rst(rst),
        .next_pc(next_pc),
        .pc(pc_addr)
    );

    imem u_imem (
        .addr(pc_addr),
        .inst(inst)
    );

    assign pc_plus4 = pc_addr + 32'd4;

    // NOTE: take_pc_rel / exe_jmpr / branch_target / jalr_target all come
    // BACKWARD from the EX stage -- this is the control-hazard path.
    assign next_pc = take_pc_rel ? branch_target
                   : exe_jmpr    ? jalr_target
                   :               pc_plus4;


    // ********************************************************
    //IF->ID FLIP-FLOPS
    // ********************************************************

    always_ff @(posedge clk) begin
        if (rst) begin
            id_inst     <= 32'd0;
            id_pc_addr  <= 32'd0;
            id_pc_plus4 <= 32'd0;
        end else begin
            id_inst     <= inst;
            id_pc_addr  <= pc_addr;
            id_pc_plus4 <= pc_plus4;
        end
    end


    // *******************************************************
    //INSTRUCTION DECODE STAGE
    // *******************************************************

    decoder u_decoder (
        .inst(id_inst),
        .opc(),
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
        .mem_write(mem_write),
        .lui(lui),
        .auipc(auipc)
    );

    imm_gen u_imm_gen (
        .inst(id_inst),
        .ctrl(imm_sel),
        .imm(imm)
    );

    // read ports are ID-stage; write port comes BACKWARD from WB
    register_file u_register_file (
        .clk(clk),
        .rs1_addr(rs1),
        .rs2_addr(rs2),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .rd_we(wb_reg_write),
        .rd_addr(wb_rd),
        .rd_data(wb_data)
    );


    // ********************************************************
    //ID->EXE FLIP-FLOPS
    // ********************************************************

    always_ff @(posedge clk) begin
        if (rst) begin
            exe_rs1_data  <= 32'd0;
            exe_rs2_data  <= 32'd0;
            exe_imm       <= 32'd0;
            exe_alu_op    <= 4'd0;
            exe_alu_src   <= 1'b0;
            exe_branch    <= 1'b0;
            exe_jmp       <= 1'b0;
            exe_func3     <= 3'd0;
            exe_rd        <= 5'd0;
            exe_rs1       <= 5'd0;
            exe_rs2       <= 5'd0;
            exe_reg_write <= 1'b0;
            exe_jmpr      <= 1'b0;
            exe_mem_read  <= 1'b0;
            exe_mem_write <= 1'b0;
            exe_lui       <= 1'b0;
            exe_auipc     <= 1'b0;
            exe_pc_addr   <= 32'd0;
            exe_pc_plus4  <= 32'd0;
        end else begin
            exe_rs1_data  <= rs1_data;
            exe_rs2_data  <= rs2_data;
            exe_imm       <= imm;
            exe_alu_op    <= alu_op;
            exe_alu_src   <= alu_src;
            exe_branch    <= branch;
            exe_jmp       <= jmp;
            exe_func3     <= func3;
            exe_rd        <= rd;
            exe_rs1       <= rs1;
            exe_rs2       <= rs2;
            exe_reg_write <= reg_write;
            exe_jmpr      <= jmpr;
            exe_mem_read  <= mem_read;
            exe_mem_write <= mem_write;
            exe_lui       <= lui;
            exe_auipc     <= auipc;
            exe_pc_addr   <= id_pc_addr;
            exe_pc_plus4  <= id_pc_plus4;
        end
    end


    //****************************************************
    //EXECUTION STAGE
    //****************************************************

    // branch comparator
    assign br_eq  = (exe_rs1_data == exe_rs2_data);
    assign br_lt  = ($signed(exe_rs1_data) < $signed(exe_rs2_data));
    assign br_ltu = (exe_rs1_data < exe_rs2_data);

    // branch decision
    always_comb begin
        case (exe_func3)
            3'b000:  branch_cond =  br_eq;    // beq
            3'b001:  branch_cond = ~br_eq;    // bne
            3'b100:  branch_cond =  br_lt;    // blt
            3'b101:  branch_cond = ~br_lt;    // bge
            3'b110:  branch_cond =  br_ltu;   // bltu
            3'b111:  branch_cond = ~br_ltu;   // bgeu
            default: branch_cond = 1'b0;
        endcase
    end

    assign branch_taken  = exe_branch & branch_cond;
    assign branch_target = exe_pc_addr + exe_imm;
    assign take_pc_rel   = branch_taken | exe_jmp;
    assign jalr_target   = (exe_rs1_data + exe_imm) & ~32'd1;

    // operand mux
    assign alu_b = exe_alu_src ? exe_imm : exe_rs2_data;

    alu u_alu (
        .ctrl(exe_alu_op),
        .a(exe_rs1_data),
        .b(alu_b),
        .res(alu_result)
    );


    // ********************************************************
    //EXE->MEM FLIP-FLOPS
    // ********************************************************

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_alu_result    <= 32'd0;
            mem_rs2_data      <= 32'd0;
            mem_imm           <= 32'd0;
            mem_branch_target <= 32'd0;
            mem_pc_plus4      <= 32'd0;
            mem_mem_read      <= 1'b0;
            mem_mem_write     <= 1'b0;
            mem_lui           <= 1'b0;
            mem_auipc         <= 1'b0;
            mem_jmp           <= 1'b0;
            mem_jmpr          <= 1'b0;
            mem_reg_write     <= 1'b0;
            mem_rd            <= 5'd0;
        end else begin
            mem_alu_result    <= alu_result;
            mem_rs2_data      <= exe_rs2_data;
            mem_imm           <= exe_imm;
            mem_branch_target <= branch_target;
            mem_pc_plus4      <= exe_pc_plus4;
            mem_mem_read      <= exe_mem_read;
            mem_mem_write     <= exe_mem_write;
            mem_lui           <= exe_lui;
            mem_auipc         <= exe_auipc;
            mem_jmp           <= exe_jmp;
            mem_jmpr          <= exe_jmpr;
            mem_reg_write     <= exe_reg_write;
            mem_rd            <= exe_rd;
        end
    end


    //****************************************************
    //MEMORY STAGE
    //****************************************************

    dmem u_dmem (
        .clk(clk),
        .addr(mem_alu_result),
        .w_e(mem_mem_write),
        .w_data(mem_rs2_data),
        .r_data(mem_rdata)
    );

    // 5-to-1 writeback mux, resolved here so MEM/WB carries only the result
    assign mem_wb_data = (mem_jmp | mem_jmpr) ? mem_pc_plus4       // jumps: return address
                       : mem_mem_read         ? mem_rdata          // loads: memory data
                       : mem_lui              ? mem_imm            // LUI: the immediate
                       : mem_auipc            ? mem_branch_target  // AUIPC: pc + imm
                       :                        mem_alu_result;    // everything else


    // ********************************************************
    //MEM->WB FLIP-FLOPS
    // ********************************************************

    always_ff @(posedge clk) begin
        if (rst) begin
            wb_data      <= 32'd0;
            wb_rd        <= 5'd0;
            wb_reg_write <= 1'b0;
        end else begin
            wb_data      <= mem_wb_data;
            wb_rd        <= mem_rd;
            wb_reg_write <= mem_reg_write;
        end
    end


    //****************************************************
    //WRITEBACK STAGE
    //****************************************************
    // Nothing but wires: wb_data / wb_rd / wb_reg_write are connected
    // directly to the register file's write port up in the ID stage.

endmodule