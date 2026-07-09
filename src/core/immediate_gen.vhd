----------------------------------------------------------------------------------
-- Module Name: immediate_gen - Behavioral
-- Description: Estrae e sign-extende l'immediato in base al tipo di istruzione
--   imm_type:
--     000 I-type
--     001 S-type
--     010 B-type
--     011 U-type
--     100 J-type
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity immediate_gen is
    port (
        instr     : in  std_logic_vector(31 downto 0);
        imm_type  : in  std_logic_vector(2 downto 0);
        imm_out   : out std_logic_vector(31 downto 0)
    );
end immediate_gen;

architecture Behavioral of immediate_gen is
begin
    process(instr, imm_type)
    begin
        case imm_type is
            when "000" =>  -- I-type: imm[11:0] = instr[31:20]
                imm_out <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));
            when "001" =>  -- S-type: imm[11:5]=instr[31:25], imm[4:0]=instr[11:7]
                imm_out <= std_logic_vector(resize(
                    signed(instr(31 downto 25) & instr(11 downto 7)), 32));
            when "010" =>  -- B-type: imm[12|10:5|4:1|11], LSB=0
                imm_out <= std_logic_vector(resize(signed(
                    instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0'
                ), 32));
            when "011" =>  -- U-type: imm[31:12] = instr[31:12], imm[11:0]=0
                imm_out <= instr(31 downto 12) & x"000";
            when "100" =>  -- J-type: imm[20|10:1|11|19:12], LSB=0x
                imm_out <= std_logic_vector(resize(signed(
                    instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0'
                ), 32));
            when others =>
                imm_out <= (others => '0');
        end case;
    end process;
end Behavioral;
