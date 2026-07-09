----------------------------------------------------------------------------------
-- Testbench: tb_cpu_pipelined_periph
--
-- Verifica il READ di una periferica memory-mapped in pipeline (il punto che
-- restava aperto dopo i fix degli hazard). Usa PROGRAM_F (PROGRAM_SEL = 5):
-- legge GPIO_SW e lo riflette su GPIO_LED.
--
-- Il testbench forza sw_in = 0x1234 e verifica che, dopo l'esecuzione,
-- led_out = 0x1234. Questo passa solo se memory_map ha la latenza di lettura
-- UNIFORME (1 ciclo): con il mux di dout combinatorio (versione precedente)
-- la pipeline leggerebbe la periferica un ciclo troppo tardi e fallirebbe.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_cpu_pipelined_periph is
end tb_cpu_pipelined_periph;

architecture sim of tb_cpu_pipelined_periph is
    signal clk            : std_logic := '0';
    signal reset          : std_logic := '1';
    signal uart_tx_pin    : std_logic;
    signal led_out        : std_logic_vector(15 downto 0);
    signal sw_in          : std_logic_vector(15 downto 0) := x"1234";

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

    clk <= not clk after 5 ns;

    stim: process
    begin
        reset <= '1';
        wait for 25 ns;
        reset <= '0';
        wait for 300 ns;

        assert led_out = x"1234"
            report "PERIPH READ FALLITO: led_out non riflette sw_in (read GPIO_SW rotto)"
            severity failure;

        report "tb_cpu_pipelined_periph: PASS - GPIO_SW letto e riflesso sui LED (led=0x1234)"
            severity note;
        wait;
    end process;

end sim;
