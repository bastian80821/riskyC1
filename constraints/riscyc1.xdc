## Constraints for riscyC1 on the Digilent Arty S7-50
## Pin assignments taken from Digilent's Arty-S7-50 master XDC.

## 12 MHz user clock (pin F14, Sch=uclk)
## 12 MHz user clock (pin F14) -- deliberately over-constrained to find fmax
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -name sys_clk -period 10.616 [get_ports { clk }];

## Reset - BTN0 (Sch=btn[0])
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { rst_btn }];

## USB-UART bridge
## uart_rx_pin is the FPGA's RX  = the bridge's TX output
## uart_tx_pin is the FPGA's TX  = the bridge's RX input
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }];
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }];

## Status LEDs
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];  # LD2
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];  # LD3
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];  # LD4
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];  # LD5

## Configuration bank voltage
set_property CFGBVS VCCO        [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
