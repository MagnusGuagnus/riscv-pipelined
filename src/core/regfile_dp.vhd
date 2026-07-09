----------------------------------------------------------------------------------
-- Module Name: regfile_dp - Behavioral
--
-- Register file DUAL-PORT per la CPU pipelined.
-- 32 x 32 bit, x0 hardwired a zero.
--
-- Due porte di lettura indipendenti (rs1 e rs2 letti SIMULTANEAMENTE nello
-- stage ID) piu' una porta di scrittura (write-back nello stage WB).
--
-- Letture asincrone (combinatorie):
--   appena cambi rs1_addr o rs2_addr, l'output cambia nello stesso ciclo.
--   Vivado sintetizza queste letture come distributed RAM (LUT-RAM), che e'
--   esattamente cio' che vogliamo per un regfile a 32 word.
--
-- Scrittura sincrona al rising_edge:
--   se we='1' e wr_addr e' diverso da x0, scrive wr_data in regs(wr_addr).
--
-- Write-before-read same-cycle: la lettura ritorna il valore OLD (lo stato
-- del registro PRIMA del rising_edge). Quindi se nello stesso ciclo facciamo
-- write a x5 e read di x5, leggiamo il vecchio valore. Per la pipeline questo
-- e' OK perche' il forwarding gestisce gli hazard. Per la "internal forward"
-- (= scrivere e leggere lo stesso registro nello stesso ciclo) ci si affida
-- al forwarding_unit a livello pipeline, non al regfile.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity regfile_dp is
    port (
        clk      : in  std_logic;
        -- Write port (sincrono)
        we       : in  std_logic;
        wr_addr  : in  std_logic_vector(4 downto 0);
        wr_data  : in  std_logic_vector(31 downto 0);
        -- Read port 1 (asincrono)
        rs1_addr : in  std_logic_vector(4 downto 0);
        rs1_data : out std_logic_vector(31 downto 0);
        -- Read port 2 (asincrono)
        rs2_addr : in  std_logic_vector(4 downto 0);
        rs2_data : out std_logic_vector(31 downto 0)
    );
end regfile_dp;

architecture Behavioral of regfile_dp is
    type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
    -- Inizializzazione a zero: indispensabile per simulazione deterministica.
    -- In sintesi Vivado distribuisce in LUT-RAM senza problemi.
    signal regs : reg_array_t := (others => (others => '0'));
begin

    --------------------------------------------------------------------
    -- Scrittura sincrona. x0 e' read-only (qualunque sw a x0 viene
    -- ignorata, in conformita' con la spec RISC-V).
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' and wr_addr /= "00000" then
                regs(to_integer(unsigned(wr_addr))) <= wr_data;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Letture asincrone con bypass x0 -> 0 (hardwired).
    --------------------------------------------------------------------
    -- Write-FIRST: Necessario perche' le
    -- letture sono asincrone: senza questo bypass un valore appena caricato e
    -- riscritto in WB verrebbe letto vecchio dall'istruzione in ID.
    rs1_data <= (others => '0') when rs1_addr = "00000"
                else wr_data when (we = '1' and wr_addr = rs1_addr)
                else regs(to_integer(unsigned(rs1_addr)));

    rs2_data <= (others => '0') when rs2_addr = "00000"
                else wr_data when (we = '1' and wr_addr = rs2_addr)
                else regs(to_integer(unsigned(rs2_addr)));

end Behavioral;
