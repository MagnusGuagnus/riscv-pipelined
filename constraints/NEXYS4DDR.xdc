################################################################################
# NEXYS4DDR.xdc — Constraint file per il progetto RISC-V multi-cycle (Fase 3)
#
# Board:  Digilent Nexys4 DDR (Rev. C)
# Part :  xc7a100tcsg324-1  (Artix-7 XC7A100T)
# Top  :  nexys4ddr_top  (set as top in Vivado prima di Synthesis)
#         IMPORTANTE: il top di sintesi è il WRAPPER nexys4ddr_top,
#         non cpu_top. Il wrapper fa l'adattamento board-specific
#         (inversione reset, scollegamento dbg_*, forza PROGRAM_SEL=1).
#         Vedi src/board/nexys4ddr_top.vhd per i dettagli.
#
# Port mapping verso il top di sintesi nexys4ddr_top:
#   clk          ← oscillatore 100 MHz on-board (PIN E3)
#   cpu_resetn   ← bottone rosso CPU RESET (PIN C12, active-LOW)
#   uart_tx_pin  → ponte USB-UART FT2232HQ (PIN D4) → /dev/ttyUSBx sul PC
#   led_out[15:0] → 16 LED bianchi della board
#   sw_in[15:0]   ← 16 slide switch della board
#
# Note sul reset:
#   Il bottone CPU_RESETN tira la linea a GND quando premuto. Nel wrapper
#   (nexys4ddr_top.vhd) c'è un'unica inversione: reset_int <= not cpu_resetn,
#   e cpu_top con tutti i suoi sotto-moduli usa "reset" attivo-alto.
#
# Note sul pin UART:
#   D4 è il pin che la FPGA pilota in OUTPUT verso il chip USB-UART. Sul
#   master XDC Digilent si chiama "UART_RXD_OUT" perché il nome è dal
#   punto di vista del chip USB (è il suo RX). Per noi è TX.
#
# Note sui banchi I/O:
#   sw[8] e sw[9] (PIN T8, U8) sono nel banco 34 alimentato a 1.8V,
#   quindi richiedono IOSTANDARD LVCMOS18. Tutti gli altri pin sono nei
#   banchi 14/15/35 a 3.3V → LVCMOS33.
################################################################################

################################################################################
# 1) Clock 100 MHz on-board (oscillatore al quarzo)
################################################################################
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

################################################################################
# 2) Reset attivo-basso (bottone rosso "CPU RESET" sul bordo superiore)
################################################################################
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { cpu_resetn }];

################################################################################
# 3) UART TX verso il chip USB-UART (FT2232HQ) → terminale PC a 115200 8N1
################################################################################
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }];

################################################################################
# 4) 16 LED (LD0..LD15) — output da cpu_top.led_out
################################################################################
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led_out[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led_out[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led_out[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led_out[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led_out[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led_out[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led_out[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led_out[7] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led_out[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led_out[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led_out[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led_out[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led_out[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led_out[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led_out[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led_out[15] }];

################################################################################
# 5) 16 Slide Switches (SW0..SW15) — input verso cpu_top.sw_in
#    ATTENZIONE: SW8 e SW9 sono nel banco I/O 34 (1.8V) → IOSTANDARD LVCMOS18
################################################################################
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { sw_in[0] }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { sw_in[1] }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { sw_in[2] }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { sw_in[3] }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { sw_in[4] }];
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { sw_in[5] }];
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { sw_in[6] }];
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { sw_in[7] }];
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS18 } [get_ports { sw_in[8] }];
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS18 } [get_ports { sw_in[9] }];
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { sw_in[10] }];
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { sw_in[11] }];
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { sw_in[12] }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { sw_in[13] }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { sw_in[14] }];
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { sw_in[15] }];

################################################################################
# 6) Configurazione del bitstream (best-practice per Nexys4 DDR)
#    - SPI x4 a 33 MHz: caricamento veloce da QSPI flash (se mai si vorrà
#      programmare la flash invece che la SRAM JTAG)
#    - Pull-up sui pin non usati: evita ingressi flottanti
################################################################################
set_property CFGBVS VCCO          [current_design]
set_property CONFIG_VOLTAGE 3.3   [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33          [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP       [current_design]
