----------------------------------------------------------------------------------
-- Testbench: tb_hello_wave
--
-- Pensato per GENERARE LA WAVEFORM "Hello su UART" da mettere nel report.
-- Usa PROGRAM_H (PROGRAM_SEL = 7): per ogni carattere fa polling di
-- UART_STATUS bit0 (ready) e poi scrive su UART_DATA -> parte un frame 8N1.
--
-- TRUCCO PER LA SIMULAZIONE: imposto BAUD = 25_000_000 cosi'
-- BAUD_DIV = CLK_HZ/BAUD = 4. Ogni frame dura 10 bit x 4 cicli = 40 cicli,
-- invece dei ~8680 cicli del baud reale (115200). Cosi' tutta la stringa
-- "Hello" sta in pochi microsecondi ed e' leggibile in waveform.
-- (Sulla scheda il baud resta 115200: il valore qui e' solo per la sim.)
--
-- Cosa guardare nella waveform:
--   * uart_tx_pin : la linea seriale. A riposo '1'; per ogni carattere vedi
--                   start('0') + 8 bit dati (LSB first) + stop('1').
--   * led_out     : 0x0F all'avvio (CPU viva), 0x55 a fine stringa.
--   * dbg_instr   : l'istruzione in decode (si vede la sw su UART_DATA).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_hello_wave is
end tb_hello_wave;

architecture sim of tb_hello_wave is
    signal clk            : std_logic := '0';
    signal reset          : std_logic := '1';
    signal uart_tx_pin    : std_logic;
    signal led_out        : std_logic_vector(15 downto 0);
    signal sw_in          : std_logic_vector(15 downto 0) := (others => '0');

    signal dbg_pc         : std_logic_vector(11 downto 0);
    signal dbg_instr      : std_logic_vector(31 downto 0);
    signal dbg_state      : std_logic_vector(1 downto 0);
    signal dbg_alu_result : std_logic_vector(31 downto 0);
    signal dbg_mem_out    : std_logic_vector(31 downto 0);
    signal dbg_rd_value   : std_logic_vector(31 downto 0);
begin

    -- BAUD veloce (25 Mbaud) -> BAUD_DIV = 4, frame corto per la waveform.
    uut: entity work.cpu_top_pipelined
        generic map ( CLK_HZ => 100_000_000, BAUD => 25_000_000, PROGRAM_SEL => 7 )
        port map (
            clk => clk, reset => reset, uart_tx_pin => uart_tx_pin,
            led_out => led_out, sw_in => sw_in,
            dbg_pc => dbg_pc, dbg_instr => dbg_instr, dbg_state => dbg_state,
            dbg_alu_result => dbg_alu_result, dbg_mem_out => dbg_mem_out,
            dbg_rd_value => dbg_rd_value
        );

    clk <= not clk after 5 ns;   -- 100 MHz

    stim: process
    begin
        reset <= '1';
        wait for 25 ns;
        reset <= '0';
        -- abbastanza per inviare "Hello" (5 frame da ~40 cicli) + LED finale
        wait for 6 us;
        assert led_out = x"0055"
            report "HELLO WAVE: led_out finale atteso 0x0055 (fine stringa)"
            severity warning;
        report "tb_hello_wave: fine simulazione, cattura la waveform di uart_tx_pin"
            severity note;
        wait;
    end process;

end sim;
