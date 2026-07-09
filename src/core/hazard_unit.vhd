----------------------------------------------------------------------------------
-- Module Name: hazard_unit - Behavioral
--
-- Combinazionale. Gestisce gli hazard non risolvibili dal solo forwarding,
-- inserendo uno stall di 1 ciclo quando necessario.
--
-- CASO 1 — LOAD-USE HAZARD
-- ========================
-- L'istruzione in ID/EX e' una LW e l'istruzione che sta in IF/ID (in decode)
-- usa lo stesso rd come rs1 o rs2.
--
-- Sequenza esempio:
--   ciclo  1     2     3     4     5
--          IF=LW
--          ID=LW IF=ADD          (qui ADD vuole leggere rd di LW come rs1)
--                ID=ADD EX=LW
--                        ?       ADD vorrebbe iniziare EX al ciclo 4 ma
--                                rd di LW non e' ancora pronto (lo sara'
--                                solo a fine MEM, cioe' ciclo 4)
--
-- Soluzione: stalliamo IF/ID per 1 ciclo, e iniettiamo una NOP in ID/EX,
-- cosi' al ciclo 5 ADD entra in EX e per quel momento il valore di LW
-- e' disponibile nel pipeline register MEM/WB (e il forwarding lo prende
-- da li').
--
-- COSA FA L'OUTPUT "stall":
--   stall = '1' -> il PC e il pipeline register IF/ID NON si aggiornano
--                  (restano congelati per 1 ciclo)
--                  + il pipeline register ID/EX viene caricato con NOP
--                  (cosi' si propaga una "bolla" attraverso EX/MEM/WB)
--   stall = '0' -> pipeline avanza normalmente
--
-- ALTRE COSE CHE QUESTO MODULO NON GESTISCE
-- =========================================
-- - Control hazard (branch taken): gestito separatamente dal flush nel top
--   pipelined, perche' richiede di invalidare anche stadi gia' avanzati.
-- - RAW hazard normale (non load-use): gestito dal forwarding_unit.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hazard_unit is
    port (
        -- Pipeline register ID/EX
        idex_is_load : in std_logic;                       -- '1' se istruzione in EX e' una LW
        idex_rd      : in std_logic_vector(4 downto 0);    -- rd dell'istruzione in EX

        -- Pipeline register IF/ID (istruzione in decode adesso)
        ifid_rs1 : in std_logic_vector(4 downto 0);
        ifid_rs2 : in std_logic_vector(4 downto 0);

        -- Output: '1' per congelare la pipeline per 1 ciclo
        stall : out std_logic
    );
end hazard_unit;

architecture Behavioral of hazard_unit is
begin

    stall <= '1' when (idex_is_load = '1'
                   and idex_rd /= "00000"
                   and (idex_rd = ifid_rs1 or idex_rd = ifid_rs2))
        else '0';

end Behavioral;
