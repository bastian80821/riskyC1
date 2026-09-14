`timescale 1ns / 1ps
// Hardware bootloader: receives a program over UART and writes it into instruction
// memory, then releases the core to run.
//
// Protocol (host -> board), all little-endian:
//   1. 4 bytes: word count N
//   2. N*4 bytes: the program, one 32-bit instruction per 4 bytes
//   3. bootloader asserts core_run and stops listening
//
// The core is held in reset for the whole load, so there is no contention on imem:
// the bootloader owns the write port during boot, the core owns the read port after.
module bootloader (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  rx_data,
    input  logic        rx_valid,
    output logic        imem_we,
    output logic [31:0] imem_waddr,
    output logic [31:0] imem_wdata,
    output logic        core_run,      // high once loading is complete
    output logic        loading        // high while receiving (for a status LED)
);
    typedef enum logic [1:0] {GET_LEN, GET_PROG, DONE} state_t;
    state_t state;

    logic [1:0]  byte_idx;     // which byte of the current word (0-3)
    logic [31:0] word_buf;     // assembling one 32-bit word
    logic [31:0] word_count;   // how many words the host says it will send
    logic [31:0] words_got;

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
            imem_we <= 1'b0;                        // default: no write

            if (rx_valid) begin
                // shift the new byte into the top of the word buffer.
                // little-endian: first byte received is the least significant.
                word_buf <= {rx_data, word_buf[31:8]};

                if (byte_idx == 2'd3) begin
                    byte_idx <= '0;
                    case (state)
                        GET_LEN: begin
                            word_count <= {rx_data, word_buf[31:8]};
                            state      <= GET_PROG;
                        end
                        GET_PROG: begin
                            imem_we    <= 1'b1;
                            imem_waddr <= words_got << 2;        // word index -> byte address
                            imem_wdata <= {rx_data, word_buf[31:8]};
                            words_got  <= words_got + 1;
                            if (words_got + 1 == word_count)
                                state <= DONE;
                        end
                        default: ;
                    endcase
                end else
                    byte_idx <= byte_idx + 1;
            end
        end
    end
endmodule
