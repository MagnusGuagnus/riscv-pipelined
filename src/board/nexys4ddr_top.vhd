----------------------------------------------------------------------------------
-- Module Name : nexys4ddr_top - Behavioral
--
-- Wrapper di board: e' il top di SINTESI verso la scheda Nexys4 DDR. Adatta il
-- core (board-agnostic) ai vincoli fisici della scheda e fa solo tre cose:
--
--   1. Inverte la polarita' del reset: il bottone "CPU RESET" e' attivo-basso
--      (a riposo '1', premuto '0'), mentre il core vuole reset attivo-alto.
--   2. Sceglie il programma da eseguire con il generic PROGRAM_SEL.
--   3. Lascia "open" le porte di debug del core (non servono pin fisici): la
--      sintesi le elimina con la dead-code elimination.
--
-- Tenere il core separato dal wrapper rende il core portabile su altre board
-- (basta un nuovo "<board>_top.vhd") e lascia i testbench liberi di istanziare
-- direttamente il core con le sue porte di debug.
--
-- Pin fisici (associati in constraints/NEXYS4DDR.xdc):
--   clk         -> E3  (oscillatore 100 MHz on-board)
--   cpu_resetn  -> C12 (bottone CPU RESET, active-low)
--   uart_tx_pin -> D4  (TX verso il chip USB-UART, 115200 8N1)
--   led_out     -> LD0..LD15 (16 LED)
--   sw_in       -> SW0..SW15 (16 switch)
--
-- PROGRAM_SEL (vedi instr_memory.vhd per la lista completa):
--   7 = Hello su UART (demo principale)   5 = echo switch->LED
--   8 = running light                     9 = interattivo switch + UART
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity nexys4ddr_top is
    port (
        clk         : in  std_logic;                       -- 100 MHz (pin E3)
        cpu_resetn  : in  std_logic;                       -- reset active-low (pin C12)
        uart_tx_pin : out std_logic;                       -- UART TX (pin D4)
        led_out     : out std_logic_vector(15 downto 0);   -- 16 LED
        sw_in       : in  std_logic_vector(15 downto 0)    -- 16 switch
    );
end nexys4ddr_top;

architecture Behavioral of nexys4ddr_top is
    signal reset_int : std_logic;
begin

    -- Reset: bottone attivo-basso -> reset attivo-alto per il core.
    reset_int <= not cpu_resetn;

    -- Core pipelined a 5 stadi. Cambiare PROGRAM_SEL per scegliere la demo.
    u_cpu: entity work.cpu_top_pipelined
        generic map (
            CLK_HZ      => 100_000_000,
            BAUD        =>     115_200,
            PROGRAM_SEL =>           7   -- Hello su UART (demo principale)
        )
        port map (
            clk            => clk,
            reset          => reset_int,
            uart_tx_pin    => uart_tx_pin,
            led_out        => led_out,
            sw_in          => sw_in,
            -- porte di debug non usate in sintesi
            dbg_pc         => open,
            dbg_instr      => open,
            dbg_state      => open,
            dbg_alu_result => open,
            dbg_mem_out    => open,
            dbg_rd_value   => open
        );

end Behavioral;
