----------------------------------------------------------------------------------
-- Testbench: tb_switch_wave
--
-- Pensato per GENERARE LA WAVEFORM "switch -> LED echo" da mettere nel report.
-- Usa PROGRAM_F (PROGRAM_SEL = 5): in loop legge GPIO_SW e lo scrive su
-- GPIO_LED. A differenza di tb_cpu_pipelined_periph (che tiene sw_in fisso),
-- qui CAMBIO sw_in piu' volte, cosi' in waveform si vede led_out INSEGUIRE
-- gli switch con qualche ciclo di ritardo (latenza pipeline + read periferico).
--
-- Cosa guardare:
--   * sw_in   : lo stimolo (0x1234 -> 0x00FF -> 0xAA55 -> 0xFFFF).
--   * led_out : segue sw_in dopo pochi cicli.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_switch_wave is
end tb_switch_wave;

architecture sim of tb_switch_wave is
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

    uut: entity work.cpu_top_pipelined
        generic map ( CLK_HZ => 100_000_000, BAUD => 115_200, PROGRAM_SEL => 5 )
        port map (
            clk => clk, reset => reset, uart_tx_pin => uart_tx_pin,
            led_out => led_out, sw_in => sw_in,
            dbg_pc => dbg_pc, dbg_instr => dbg_instr, dbg_state => dbg_state,
            dbg_alu_result => dbg_alu_result, dbg_mem_out => dbg_mem_out,
            dbg_rd_value => dbg_rd_value
        );

    clk <= not clk after 5 ns;   -- 100 MHz

    -- Stimolo degli switch: cambia nel tempo per mostrare l'echo che insegue.
    stim: process
    begin
        reset <= '1';  sw_in <= x"0000";
        wait for 25 ns;
        reset <= '0';
        wait for 150 ns;  sw_in <= x"1234";   -- primo valore
        wait for 200 ns;  sw_in <= x"00FF";   -- cambia
        wait for 200 ns;  sw_in <= x"AA55";   -- cambia
        wait for 200 ns;  sw_in <= x"FFFF";   -- tutti accesi
        wait for 200 ns;
        report "tb_switch_wave: fine simulazione, cattura led_out che insegue sw_in"
            severity note;
        wait;
    end process;

end sim;
