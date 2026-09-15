`timescale 1ns / 1ps
// 5-stage pipelined RV32I core: IF | ID | EX | MEM | WB
// Forwarding (EX bypass network), branch flushing, write-first register file.
// No load-use stall needed: dmem's combinational read plus a MEM-stage writeback
// mux make load data forwardable in time (guarded by a regression test).
// Memory-mapped UART at 0x1000 (write = transmit) / 0x1004 (read = busy flag).
// Instruction memory has a write port so a bootloader can load programs at runtime.
module core_pipelined #(
    parameter int CLK_FREQ  = 12_000_000,   // must match the actual clock, or baud breaks
    parameter int BAUD_RATE = 115_200
) (
    input  logic        clk,
    input  logic        rst,
    // bootloader write port into instruction memory
    input  logic        imem_we,
    input  logic [31:0] imem_waddr,
    input  logic [31:0] imem_wdata,
    // serial output
    output logic        uart_tx_pin,
    // debug taps
    output logic [31:0] debug_pc,
    output logic [31:0] debug_wb_data,
    output logic [4:0]  debug_wb_rd,
    output logic        debug_wb_reg_write
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
    
    //uart
    logic uart_sel;
    logic [31:0] mem_read_data;
    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;
    logic        dmem_we;
    

    //WRITEBACK SIGNALS
    logic [31:0] wb_data;
    logic [4:0]  wb_rd;
    logic        wb_reg_write;
    
    //FORWARDING SIGNALS
    logic [1:0] fwd_a;
    logic [1:0] fwd_b;
    logic [31:0] data_fwd_a;
    logic [31:0] data_fwd_b;

    //FLUSH SIGNAL
    logic       flush;

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
        .clk(clk),
        .addr(pc_addr),
        .inst(inst),
        .we(imem_we),
        .waddr(imem_waddr),
        .wdata(imem_wdata)
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
        if (rst || flush) begin
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
        if (rst || flush) begin
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
    assign br_eq  = (data_fwd_a == data_fwd_b);
    assign br_lt  = ($signed(data_fwd_a) < $signed(data_fwd_b));
    assign br_ltu = (data_fwd_a < data_fwd_b);

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
    
    //intermediate signal
    assign branch_taken  = exe_branch & branch_cond;
    //adder
    assign branch_target = exe_pc_addr + exe_imm;
    assign take_pc_rel   = branch_taken | exe_jmp;
    //adder
    assign jalr_target = (data_fwd_a + exe_imm) & ~32'd1;

    assign flush = take_pc_rel | exe_jmpr;
    
     // forwarding mux for ALU operand A
    always_comb begin
        case (fwd_a)
            2'b01:   data_fwd_a = mem_wb_data;    // forward from MEM (newer)
            2'b10:   data_fwd_a = wb_data;        // forward from WB
            default: data_fwd_a = exe_rs1_data;   // no hazard: use the register value
        endcase
    end

    // forwarding mux for ALU operand B
    always_comb begin
        case (fwd_b)
            2'b01:   data_fwd_b = mem_wb_data;    // forward from MEM (newer)
            2'b10:   data_fwd_b = wb_data;        // forward from WB
            default: data_fwd_b = exe_rs2_data;   // no hazard: use the register value
        endcase
    end

    // alu_b mux
    assign alu_b = exe_alu_src ? exe_imm : data_fwd_b;

    //alu instantiation
    alu u_alu (
        .ctrl(exe_alu_op),
        .a(data_fwd_a),
        .b(alu_b),
        .res(alu_result)
    );

    //combinational forwarding logic alu
    always_comb begin
    // operand A
    fwd_a = 2'b00;
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == exe_rs1))
            fwd_a = 2'b01;
        else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == exe_rs1))
            fwd_a = 2'b10;
    
        // operand B - same logic, exe_rs2 instead of exe_rs1
        fwd_b = 2'b00;
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == exe_rs2))
            fwd_b = 2'b01;
        else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == exe_rs2))
            fwd_b = 2'b10;
    end
    
    

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
            mem_rs2_data      <= data_fwd_b;
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

    //instantiate date memory
    dmem u_dmem (
        .clk(clk),
        .addr(mem_alu_result),
        .w_e(dmem_we),
        .w_data(mem_rs2_data),
        .r_data(mem_rdata),
        .boot_we(imem_we),
        .boot_waddr(imem_waddr),
        .boot_wdata(imem_wdata)
    );

    // 5-to-1 writeback mux, resolved here so MEM/WB carries only the result
    assign mem_wb_data = (mem_jmp | mem_jmpr) ? mem_pc_plus4       // jumps: return address
                       : mem_mem_read         ? mem_read_data          // loads: memory data
                       : mem_lui              ? mem_imm            // LUI: the immediate
                       : mem_auipc            ? mem_branch_target  // AUIPC: pc + imm
                       :                        mem_alu_result;    // everything else
    
    //instantiate uart
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_tx_pin), .tx_busy(tx_busy)
    );
    
    assign mem_read_data = uart_sel ? {31'd0, tx_busy} : mem_rdata;
    assign dmem_we  = mem_mem_write & ~uart_sel;    // normal store -> dmem
    assign tx_start = mem_mem_write &  uart_sel;    // store to UART range -> transmit
    assign tx_data  = mem_rs2_data[7:0];            // the byte (low 8 bits)
    assign uart_sel = (mem_alu_result[31:12] != 20'd0);   // address >= 0x1000 -> device, not memory
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
    
    // Debug outputs: anchor the design so synthesis can't optimise it away.
    // Without observable outputs, nothing the core computes escapes the module,
    // so the entire netlist is dead logic and gets deleted.
    assign debug_pc           = pc_addr;
    assign debug_wb_data      = wb_data;
    assign debug_wb_rd        = wb_rd;
    assign debug_wb_reg_write = wb_reg_write;

endmodule