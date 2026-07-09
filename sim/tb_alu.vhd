----------------------------------------------------------------------------------
-- Testbench: tb_alu (versione spec del prof, 6 operazioni, opcode 3 bit)
-- Verifica alu_pre_result (combinatorio) e alu_result (latched, ritardato 1 clk).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_alu is
end tb_alu;

architecture sim of tb_alu is
    signal clk            : std_logic := '0';
    signal a, b           : std_logic_vector(31 downto 0) := (others => '0');
    signal alu_opcode     : std_logic_vector(2 downto 0)  := (others => '0');
    signal alu_pre_result : std_logic_vector(31 downto 0);
    signal alu_result     : std_logic_vector(31 downto 0);
begin
    uut: entity work.alu
        port map (
            clk            => clk,
            a              => a,
            b              => b,
            alu_opcode     => alu_opcode,
            alu_pre_result => alu_pre_result,
            alu_result     => alu_result
        );

    -- clock 100 MHz (period 10 ns)
    clk <= not clk after 5 ns;

    stim: process
    begin
        wait for 7 ns;  -- offset rispetto al rising edge

        -- ADD: 5 + 3 = 8
        a <= x"00000005"; b <= x"00000003"; alu_opcode <= "000";
        wait for 10 ns;
        assert alu_pre_result = x"00000008" report "ADD pre failed" severity error;
        assert alu_result     = x"00000008" report "ADD latched failed" severity error;

        -- ADDU: idem ADD a 32 bit
        a <= x"FFFFFFFF"; b <= x"00000001"; alu_opcode <= "001";
        wait for 10 ns;
        assert alu_pre_result = x"00000000" report "ADDU pre failed" severity error;

        -- SUB: 10 - 7 = 3
        a <= x"0000000A"; b <= x"00000007"; alu_opcode <= "010";
        wait for 10 ns;
        assert alu_pre_result = x"00000003" report "SUB pre failed" severity error;
        assert alu_result     = x"00000003" report "SUB latched failed" severity error;

        -- EXOR
        a <= x"AAAAAAAA"; b <= x"55555555"; alu_opcode <= "100";
        wait for 10 ns;
        assert alu_pre_result = x"FFFFFFFF" report "EXOR pre failed" severity error;

        -- OR
        a <= x"FF00FF00"; b <= x"00FF00FF"; alu_opcode <= "110";
        wait for 10 ns;
        assert alu_pre_result = x"FFFFFFFF" report "OR pre failed" severity error;

        -- AND
        a <= x"FF00FF00"; b <= x"0F0F0F0F"; alu_opcode <= "111";
        wait for 10 ns;
        assert alu_pre_result = x"0F000F00" report "AND pre failed" severity error;

        report "tb_alu (spec del prof) completato senza errori" severity note;
        wait;
    end process;
end sim;
