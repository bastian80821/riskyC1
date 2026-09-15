`timescale 1ns / 1ps
// Hardware bootloader: receives a program over UART and writes it into both
// instruction and data memory, then releases the core.
//
// Protocol (host -> board), little-endian:
//   1. 4 bytes : word count N
//   2. N*4 bytes : the program, one 32-bit instruction per 4 bytes
//
// The bootloader keeps listening after a program has been loaded. Four more
// bytes arriving are interpreted as a new word count, which drops core_run
// (resetting the core) and starts a fresh load. That makes it possible to run
// a suite of test programs back to back without touching the reset button.
module bootloader (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  rx_data,
    input  logic        rx_valid,
    output logic        imem_we,
    output logic [31:0] imem_waddr,
    output logic [31:0] imem_wdata,
    output logic        core_run,      // high once loading is complete
    output logic        loading        // high while receiving
);
    typedef enum logic [1:0] {GET_LEN, GET_PROG, DONE} state_t;
    state_t state;

    logic [1:0]  byte_idx;
    logic [31:0] word_buf;
    logic [31:0] word_count;
    logic [31:0] words_got;

    // the word being assembled, completed by the byte arriving this cycle
    logic [31:0] full_word;
    assign full_word = {rx_data, word_buf[31:8]};

    assign loading  = (state != DONE);
    assign core_run = (state == DONE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= GET_LEN;
            byte_idx   <= '0;
            word_buf   <= '0;
            word_count <= '0;
            words_got  <= '0;
            imem_we    <= 1'b0;
            imem_waddr <= '0;
            imem_wdata <= '0;
        end else begin
            imem_we <= 1'b0;

            if (rx_valid) begin
                word_buf <= full_word;

                if (byte_idx == 2'd3) begin
                    byte_idx <= '0;
                    case (state)
                        GET_LEN: begin
                            word_count <= full_word;
                            words_got  <= '0;
                            state      <= GET_PROG;
                        end
                        GET_PROG: begin
                            imem_we    <= 1'b1;
                            imem_waddr <= words_got << 2;
                            imem_wdata <= full_word;
                            words_got  <= words_got + 1;
                            if (words_got + 1 == word_count)
                                state <= DONE;
                        end
                        DONE: begin
                            // a new word count: reload, which drops core_run
                            word_count <= full_word;
                            words_got  <= '0;
                            state      <= GET_PROG;
                        end
                        default: ;
                    endcase
                end else
                    byte_idx <= byte_idx + 1;
            end
        end
    end
endmodule
