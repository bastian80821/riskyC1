`timescale 1ns / 1ps

// Board bring-up: divide the 12 MHz clock down to a ~1 Hz LED blink.
// Confirms the RTL -> synthesis -> implementation -> bitstream -> hardware path.
module blink (
    input  logic       clk,    // 12 MHz user clock, pin F14
    output logic [3:0] led     // 4-bit bus: led[0]=LD2 ... led[3]=LD5
);
    // 12 MHz -> toggle every 6,000,000 cycles ~= 0.5 s -> ~1 Hz blink
    localparam int unsigned HALF = 6_000_000;

    logic [22:0] count   = '0;   // 2^23 = 8.4M, enough to count to 6M
    logic        led_reg = 1'b0;

    always_ff @(posedge clk) begin
        if (count == HALF - 1) begin
            count   <= '0;           // reset counter
            led_reg <= ~led_reg;     // toggle the LED register
        end else begin
            count <= count + 1'b1;   // increment counter
        end
    end

    assign led[0] = led_reg;   // LD2 blinks
    assign led[1] = 1'b0;      // LD3 off
    assign led[2] = 1'b0;      // LD4 off
    assign led[3] = 1'b0;      // LD5 off
endmodule
