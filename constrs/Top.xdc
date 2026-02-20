##-----------------------------------------------------------------------------
## Top.xdc (Basys3)
## Reference files:
## - constraint/Basys-3-Master.xdc
## - constraint/UltraTop.xdc
##-----------------------------------------------------------------------------

## Clock (100MHz)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports iClk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports iClk]

## Reset (SW15 used as active-high reset)
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports iRst]

## Buttons
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports iBtnC]
set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports iBtnU]
set_property -dict { PACKAGE_PIN U17  IOSTANDARD LVCMOS33 } [get_ports iBtnD]
set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports iBtnL]
set_property -dict { PACKAGE_PIN T17  IOSTANDARD LVCMOS33 } [get_ports iBtnR]

## Switches
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports iSw0]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports iSw1]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports iSw2]
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports iSw3]

## UART (USB-RS232)
set_property -dict { PACKAGE_PIN B18  IOSTANDARD LVCMOS33 } [get_ports iRx]
set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports oTx]

## HC-SR04 (Pmod JA)
## JA9 -> Trigger, JA10 -> Echo (same mapping used in UltraTop.xdc)
set_property -dict { PACKAGE_PIN H2   IOSTANDARD LVCMOS33 } [get_ports oSr04Trig]
set_property -dict { PACKAGE_PIN G3   IOSTANDARD LVCMOS33 } [get_ports iSr04Echo]

## DHT11 single-wire (Pmod JA1)
set_property -dict { PACKAGE_PIN J1   IOSTANDARD LVCMOS33 } [get_ports ioDht11Data]
set_property PULLUP true [get_ports ioDht11Data]

## 7-Segment Display: oFndFont[0:7] -> CA,CB,CC,CD,CE,CF,CG,DP
set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[0]}]
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[1]}]
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[2]}]
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[3]}]
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[4]}]
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[5]}]
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[6]}]
set_property -dict { PACKAGE_PIN V7   IOSTANDARD LVCMOS33 } [get_ports {oFndFont[7]}]

## 7-Segment Digit Select: oFndCom[0:3]
set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports {oFndCom[0]}]
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports {oFndCom[1]}]
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports {oFndCom[2]}]
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports {oFndCom[3]}]

## Configuration
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
