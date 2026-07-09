----------------------------------------------------------------------------------
-- Module Name: data_memory - Behavioral
-- Description: Data Memory secondo la spec del prof (slide 20).
--   - BRAM sincrona 4096 × 32 bit (16 kB).
--   - Indirizzo: 12 bit (word-level), arriva da alu_pre_result[13:2].
--   - Lettura sincrona: il dato esce 1 ciclo dopo che addr è applicato.
--     L'uso di alu_pre_result (combinatorio, no latch) come addr permette
--     di nascondere questa latenza tra EXECUTE e MEM/WB.
--   - Scrittura sincrona quando we='1' (solo durante MEM/WB se Store).
--   - Inizializzata a tutti zeri.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity data_memory is
    port (
        clk      : in  std_logic;
        we       : in  std_logic;                       -- write enable
        addr     : in  std_logic_vector(11 downto 0);   -- word address, 12 bit = 4096 word
        din      : in  std_logic_vector(31 downto 0);   -- dato da scrivere (per SW)
        dout     : out std_logic_vector(31 downto 0)    -- dato letto (per LW)
    );
end data_memory;

architecture Behavioral of data_memory is
    type ram_t is array (0 to 4095) of std_logic_vector(31 downto 0);

    --------------------------------------------------------------------
    -- Inizializzazione DMEM (necessaria per Hello World):
    --   word 0..2  → indirizzi delle periferiche memory-mapped, usati come
    --                "base address" nel programma Hello World per aggirare
    --                il limite di 12 bit signed dell'immediato di lw/sw.
    --   word 4..8  → caratteri ASCII della stringa "Hello", una word ciascuno
    --                (i byte alti restano 0; la UART prende solo gli 8 bit bassi).
    --   resto      → zero.
    --
    -- Nota: il programma di test del core NON legge questi valori, perché
    -- prima sovrascrive DMEM[0] con la sua sw. Quindi la stessa inizializzazione
    -- va bene per entrambi i programmi (test del core e Hello).
    --------------------------------------------------------------------
    constant DATA_INIT : ram_t := (
        0 => x"00010000",   -- &UART_DATA
        1 => x"00010004",   -- &UART_STATUS
        2 => x"00010008",   -- &GPIO_LED
        4 => x"00000048",   -- 'H' (ASCII)
        5 => x"00000065",   -- 'e'
        6 => x"0000006C",   -- 'l'
        7 => x"0000006C",   -- 'l'
        8 => x"0000006F",   -- 'o'
        others => (others => '0')
    );

    signal mem : ram_t := DATA_INIT;
begin
    -- BRAM sincrona single-port, pattern Vivado:
    -- in same-cycle write & read sullo stesso indirizzo, il read ritorna il
    -- valore VECCHIO (read-first behavior). Per noi va bene perché non
    -- scriviamo e leggiamo nello stesso ciclo (read in MEM/WB, write in MEM/WB
    -- ma di istruzioni diverse).
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem(to_integer(unsigned(addr))) <= din;
            end if;
            dout <= mem(to_integer(unsigned(addr)));
        end if;
    end process;
end Behavioral;
