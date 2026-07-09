----------------------------------------------------------------------------------
-- Testbench: tb_data_memory
-- Verifica:
--   - Inizializzazione a zero
--   - Scrittura sincrona (we='1')
--   - Lettura sincrona con latenza di 1 ciclo
--   - Più scritture su indirizzi diversi
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_data_memory is
end tb_data_memory;

architecture sim of tb_data_memory is
    signal clk  : std_logic := '0';
    signal we   : std_logic := '0';
    signal addr : std_logic_vector(11 downto 0) := (others => '0');
    signal din  : std_logic_vector(31 downto 0) := (others => '0');
    signal dout : std_logic_vector(31 downto 0);
begin
    uut: entity work.data_memory
        port map (
            clk  => clk,
            we   => we,
            addr => addr,
            din  => din,
            dout => dout
        );

    clk <= not clk after 5 ns;

    stim: process
    begin
        wait for 7 ns;

        ------------------------------------------------------------------
        -- 1) Lettura iniziale: tutto zero
        ------------------------------------------------------------------
        we   <= '0';
        addr <= x"000";
        wait for 10 ns;
        assert dout = x"00000000"
            report "DMEM[0] all'init dovrebbe essere 0" severity error;

        ------------------------------------------------------------------
        -- 2) Scrittura DMEM[0] = 0x12345678
        ------------------------------------------------------------------
        addr <= x"000";
        din  <= x"12345678";
        we   <= '1';
        wait for 10 ns;
        we <= '0';
        -- Rileggi: dovrebbe essere 0x12345678 dopo 1 ciclo
        wait for 10 ns;
        assert dout = x"12345678"
            report "DMEM[0] dopo write dovrebbe essere 0x12345678" severity error;

        ------------------------------------------------------------------
        -- 3) Scrittura DMEM[5] = 0xDEADBEEF
        ------------------------------------------------------------------
        addr <= x"005";
        din  <= x"DEADBEEF";
        we   <= '1';
        wait for 10 ns;
        we <= '0';
        wait for 10 ns;
        assert dout = x"DEADBEEF"
            report "DMEM[5] dovrebbe essere 0xDEADBEEF" severity error;

        ------------------------------------------------------------------
        -- 4) Rileggi DMEM[0]: deve essere ancora 0x12345678
        ------------------------------------------------------------------
        addr <= x"000";
        wait for 20 ns;  -- 2 cicli per stabilizzare
        assert dout = x"12345678"
            report "DMEM[0] deve essere ancora 0x12345678 (non sovrascritto)" severity error;

        ------------------------------------------------------------------
        -- 5) DMEM[4095] (estremo del range): scrivi e rileggi
        ------------------------------------------------------------------
        addr <= x"FFF";  -- 4095 in hex
        din  <= x"CAFEBABE";
        we   <= '1';
        wait for 10 ns;
        we <= '0';
        wait for 10 ns;
        assert dout = x"CAFEBABE"
            report "DMEM[4095] dovrebbe essere 0xCAFEBABE" severity error;

        ------------------------------------------------------------------
        -- 6) Sovrascrittura DMEM[0] con 0xAAAAAAAA
        ------------------------------------------------------------------
        addr <= x"000";
        din  <= x"AAAAAAAA";
        we   <= '1';
        wait for 10 ns;
        we <= '0';
        wait for 10 ns;
        assert dout = x"AAAAAAAA"
            report "DMEM[0] sovrascritto dovrebbe essere 0xAAAAAAAA" severity error;

        report "tb_data_memory: tutti i casi verificati" severity note;
        wait;
    end process;
end sim;
