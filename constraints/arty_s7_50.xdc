## Minimal per-project XDC for the Arty S7-50 (blink).
## Copied from boards/Arty-S7-50-Master.xdc and renamed to match the design's ports.

## 12 MHz user clock (pin F14)
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -name sys_clk -period 83.333 -waveform {0 41.667} [get_ports { clk }];

## 4 green LEDs
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];  # LD2
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];  # LD3
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];  # LD4
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];  # LD5

## Configuration bank voltage (3.3 V on this board)
set_property CFGBVS VCCO        [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
