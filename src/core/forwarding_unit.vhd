----------------------------------------------------------------------------------
-- Module Name: forwarding_unit - Behavioral
--
-- Combinazionale. Risolve i data hazard di tipo RAW (Read After Write)
-- nella pipeline 5-stage, evitando di dover stallare.
--
-- IDEA: se l'istruzione in EX (che sta calcolando A op B) ha rs1 o rs2
-- che coincide con il rd di una istruzione PIU' AVANTI nella pipeline
-- (in EX/MEM o MEM/WB), allora il valore "fresco" non si trova nel
-- regfile (che ha solo i valori writeback completati) ma in uno dei
-- pipeline register intermedi. Il forwarding instrada il valore corretto
-- direttamente all'input dell'ALU bypassando il regfile.
--
-- 3 sorgenti per ciascun operando ALU:
--   00 = valore letto dal regfile (default, niente hazard)
--   01 = valore proveniente dal pipeline register EX/MEM (= ALU result
--        dell'istruzione precedente, ancora in MEM stage)
--   10 = valore proveniente dal pipeline register MEM/WB (= valore del
--        writeback dell'istruzione 2 passi avanti: puo' essere ALU result
--        gia' propagato o mem_out di una LW)
--
-- PRIORITA': EX/MEM ha priorita' su MEM/WB. Cioe' se ENTRAMBI scrivono
-- nello stesso rd, l'istruzione piu' recente (EX/MEM) e' quella corretta.
--
-- ECCEZIONE x0: non si forwarda mai verso o da x0 (sempre 0).
--
-- NB: il load-use hazard (LW seguito subito da istr che usa rd) NON e'
-- risolvibile da solo forwarding perche' il dato del LW non e' pronto
-- alla fine di EX (la lettura DMEM avviene in MEM). Quel caso e' gestito
-- dal modulo separato hazard_unit (che inserisce 1 ciclo di stall).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity forwarding_unit is
    port (
        -- Pipeline register ID/EX: istruzione in esecuzione
        idex_rs1 : in std_logic_vector(4 downto 0);
        idex_rs2 : in std_logic_vector(4 downto 0);

        -- Pipeline register EX/MEM: istruzione precedente
        exmem_rd       : in std_logic_vector(4 downto 0);
        exmem_regwrite : in std_logic;

        -- Pipeline register MEM/WB: istruzione due passi avanti
        memwb_rd       : in std_logic_vector(4 downto 0);
        memwb_regwrite : in std_logic;

        -- Selettori per i mux degli operandi ALU (2 bit ciascuno)
        --   00 = dal regfile, 01 = da EX/MEM, 10 = da MEM/WB
        fwd_a : out std_logic_vector(1 downto 0);
        fwd_b : out std_logic_vector(1 downto 0)
    );
end forwarding_unit;

architecture Behavioral of forwarding_unit is
begin

    --------------------------------------------------------------------
    -- Selettore per l'operando A (= rs1 dell'istruzione in EX)
    --------------------------------------------------------------------
    fwd_a <= "01" when (exmem_regwrite = '1'
                    and exmem_rd /= "00000"
                    and exmem_rd = idex_rs1)
        else "10" when (memwb_regwrite = '1'
                    and memwb_rd /= "00000"
                    and memwb_rd = idex_rs1)
        else "00";

    --------------------------------------------------------------------
    -- Selettore per l'operando B (= rs2 dell'istruzione in EX)
    --------------------------------------------------------------------
    fwd_b <= "01" when (exmem_regwrite = '1'
                    and exmem_rd /= "00000"
                    and exmem_rd = idex_rs2)
        else "10" when (memwb_regwrite = '1'
                    and memwb_rd /= "00000"
                    and memwb_rd = idex_rs2)
        else "00";

end Behavioral;
