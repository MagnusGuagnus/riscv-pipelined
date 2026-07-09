----------------------------------------------------------------------------------
-- Testbench: tb_instr_memory
-- Verifica che le 5 istruzioni del programma di test precaricato vengano lette
-- correttamente. Tiene conto della latenza di 1 ciclo della BRAM.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_instr_memory is
end tb_instr_memory;

architecture sim of tb_instr_memory is
    signal clk         : std_logic := '0';
    signal addr        : std_logic_vector(9 downto 0) := (others => '0');
    signal instruction : std_logic_vector(31 downto 0);
begin
    uut: entity work.instr_memory
        port map (
            clk         => clk,
            addr        => addr,
            instruction => instruction
        );

    clk <= not clk after 5 ns;

    stim: process
    begin
        wait for 7 ns;  -- offset rispetto al rising_edge

        -- Leggi istruzione 0: addi x1, x0, 5  = 0x00500093
        addr <= "0000000000";  -- word 0
        wait for 10 ns;        -- 1 ciclo di clock per la latenza BRAM
        assert instruction = x"00500093"
            report "addr=0: dovrebbe essere 0x00500093 (addi x1,x0,5)" severity error;

        -- Leggi istruzione 1: addi x2, x0, 3  = 0x00300113
        addr <= "0000000001";
        wait for 10 ns;
        assert instruction = x"00300113"
            report "addr=1: dovrebbe essere 0x00300113 (addi x2,x0,3)" severity error;

        -- Leggi istruzione 2: add x3, x1, x2  = 0x002081B3
        addr <= "0000000010";
        wait for 10 ns;
        assert instruction = x"002081B3"
            report "addr=2: dovrebbe essere 0x002081B3 (add x3,x1,x2)" severity error;

        -- Leggi istruzione 3: sw x3, 0(x0)  = 0x00302023
        addr <= "0000000011";
        wait for 10 ns;
        assert instruction = x"00302023"
            report "addr=3: dovrebbe essere 0x00302023 (sw x3,0(x0))" severity error;

        -- Leggi istruzione 4: jal x0, 0  = 0x0000006F
        addr <= "0000000100";
        wait for 10 ns;
        assert instruction = x"0000006F"
            report "addr=4: dovrebbe essere 0x0000006F (jal x0,0)" severity error;

        -- Leggi istruzione 5+: dovrebbe essere NOP = 0x00000013
        addr <= "0000000101";
        wait for 10 ns;
        assert instruction = x"00000013"
            report "addr=5: dovrebbe essere NOP 0x00000013" severity error;

        addr <= "0000010000";  -- word 16
        wait for 10 ns;
        assert instruction = x"00000013"
            report "addr=16: dovrebbe essere NOP" severity error;

        report "tb_instr_memory: tutti i casi verificati" severity note;
        wait;
    end process;
end sim;
