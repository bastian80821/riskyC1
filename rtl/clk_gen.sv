`timescale 1ns / 1ps
// Clock generator: multiplies the Arty S7's 12 MHz oscillator up to a faster
// system clock using the FPGA's MMCM (Mixed-Mode Clock Manager).
//
// The MMCM works by running an internal VCO at a high frequency and dividing
// down. On Spartan-7 -1 the VCO must stay within roughly 600-1200 MHz:
//
//     VCO   = 12 MHz * CLKFBOUT_MULT_F / DIVCLK_DIVIDE = 12 * 62.5 / 1 = 750 MHz
//     clk_o = VCO / CLKOUT0_DIVIDE_F                   = 750 / 10     = 75 MHz
//
// 75 MHz leaves margin below the design's ~94 MHz timing closure. Raise
// CLKOUT0_DIVIDE_F to slow down, lower it to speed up (8 gives 93.75 MHz, which
// is right at the limit).
//
// `locked` goes high once the MMCM has stabilised; hold the design in reset
// until then, since the output clock is not trustworthy before that.
module clk_gen (
    input  logic clk_in,      // 12 MHz from the board
    output logic clk_out,     // multiplied system clock
    output logic locked
);
    logic clk_fb, clk_fb_buf, clk_out_raw;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (83.333),     // 12 MHz
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (58.250),     // VCO = 12 * 58.333 = 700 MHz
        .CLKOUT0_DIVIDE_F   (10.000),     // 700 / 10 = 70 MHz     // 75 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_in),
        .CLKFBIN  (clk_fb_buf),
        .CLKFBOUT (clk_fb),
        .CLKOUT0  (clk_out_raw),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0),
        .CLKOUT1  (), .CLKOUT2  (), .CLKOUT3 (), .CLKOUT4 (),
        .CLKOUT5  (), .CLKOUT6  (), .CLKOUT0B(), .CLKOUT1B(),
        .CLKOUT2B (), .CLKOUT3B (), .CLKFBOUTB()
    );

    // feedback and output clocks must go through global clock buffers
    BUFG u_fb  (.I(clk_fb),      .O(clk_fb_buf));
    BUFG u_out (.I(clk_out_raw), .O(clk_out));
endmodule
