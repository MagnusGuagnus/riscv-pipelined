----------------------------------------------------------------------------------
-- Module Name: alu - Behavioral
-- Description: ALU 32-bit secondo la spec del prof (slide 18 del PDF guidelines)
--   Encoding alu_opcode (3 bit):
--     000  ADD
--     001  ADDU  (somma unsigned, comportamento bitwise identico ad ADD a 32 bit)
--     010  SUB
--     100  EXOR  (XOR)
--     110  OR
--     111  AND
--   Uscite:
--     alu_pre_result: combinatoria, disponibile subito (per indirizzare DMEM
--                     un ciclo prima del normale, "latency hiding")
--     alu_result:     versione registrata (latched) di alu_pre_result, allineata
--                     alla fine della fase EXECUTE
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alu is
    port (
        clk            : in  std_logic;
        a              : in  std_logic_vector(31 downto 0);
        b              : in  std_logic_vector(31 downto 0);
        alu_opcode     : in  std_logic_vector(2 downto 0);
        alu_pre_result : out std_logic_vector(31 downto 0);
        alu_result     : out std_logic_vector(31 downto 0)
    );
end alu;

architecture Behavioral of alu is
    signal pre : std_logic_vector(31 downto 0);
begin
    -- Logica combinatoria
    process(a, b, alu_opcode)
    begin
        case alu_opcode is
            when "000" => pre <= std_logic_vector(unsigned(a) + unsigned(b));   -- ADD
            when "001" => pre <= std_logic_vector(unsigned(a) + unsigned(b));   -- ADDU (idem ADD a 32 bit)
            when "010" => pre <= std_logic_vector(unsigned(a) - unsigned(b));   -- SUB
            when "100" => pre <= a xor b;                                       -- EXOR
            when "110" => pre <= a or b;                                        -- OR
            when "111" => pre <= a and b;                                       -- AND
            when others => pre <= (others => '0');
        end case;
    end process;

    alu_pre_result <= pre;

    -- Latch sincrono: alu_result = pre del ciclo precedente
    process(clk)
    begin
        if rising_edge(clk) then
            alu_result <= pre;
        end if;
    end process;
end Behavioral;
