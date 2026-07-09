----------------------------------------------------------------------------------
-- Testbench: tb_memory_map
-- Verifica il routing dell'address decoder + le 3 periferiche istanziate
-- (DMEM, UART, GPIO) viste dalla CPU.
--
-- Strategia:
--   Istanzia memory_map con BAUD_DIV=4 (CLK_HZ=100M, BAUD=25M) per simulare
--   veloce.
--   Pilota addr/we/din come se fossimo nello stato MEM/WB della CPU, e
--   verifica che le scritture/letture finiscano nel posto giusto.
--
-- Test:
--   1. Reset, verifica dout=0 e led_out=0
--   2. DMEM write+read: sw 0x12345678 in DMEM[0], poi lw e verifica dout
--   3. GPIO_LED write: sw 0x0000_ABCD in GPIO_LED → led_out=0xABCD
--   4. GPIO_SW read: sw_in=0x55AA → dopo 2 cicli sync, dout=0x000055AA
--   5. UART_STATUS read (idle): dout bit 0 = 1 (ready, non busy)
--   6. UART_DATA write: kick della UART con byte 0x41, verifica che
--      uart_tx_pin scenda a '0' (start bit) e che il bit 0 di dout
--      (UART_STATUS) torni a 0 (busy) durante la trasmissione.
--   7. Write su indirizzo read-only (UART_STATUS, 0x10004): verifica che
--      la UART NON parta (sw silenziosamente ignorata).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_memory_map is
end tb_memory_map;

architecture sim of tb_memory_map is
    constant CLK_PERIOD : time := 10 ns;

    -- Segnali DUT
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal addr        : std_logic_vector(31 downto 0) := (others => '0');
    signal we          : std_logic := '0';
    signal din         : std_logic_vector(31 downto 0) := (others => '0');
    signal dout        : std_logic_vector(31 downto 0);
    signal uart_tx_pin : std_logic;
    signal led_out     : std_logic_vector(15 downto 0);
    signal sw_in       : std_logic_vector(15 downto 0) := (others => '0');

begin
    uut: entity work.memory_map
        generic map (
            CLK_HZ => 100_000_000,
            BAUD   =>  25_000_000   -- → BAUD_DIV = 4
        )
        port map (
            clk         => clk,
            reset       => reset,
            addr        => addr,
            we          => we,
            din         => din,
            dout        => dout,
            uart_tx_pin => uart_tx_pin,
            led_out     => led_out,
            sw_in       => sw_in
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim: process
    begin
        ----------------------------------------------------------------
        -- 1) Reset
        ----------------------------------------------------------------
        reset <= '1';
        wait for 3 * CLK_PERIOD;
        reset <= '0';
        wait for CLK_PERIOD;

        -- Dopo reset: led_out = 0x0000, uart in IDLE (tx_pin='1', status ready)
        assert led_out = x"0000"
            report "[1] led_out dopo reset" severity error;
        assert uart_tx_pin = '1'
            report "[1] uart_tx_pin idle ('1')" severity error;
        report "[1] Reset OK" severity note;

        ----------------------------------------------------------------
        -- 2) DMEM: scrivi 0x12345678 in DMEM[word 0]
        --    Indirizzo byte 0x00000000, word index 0.
        ----------------------------------------------------------------
        addr <= x"00000000";
        din  <= x"12345678";
        we   <= '1';
        wait for CLK_PERIOD;
        we   <= '0';
        wait for CLK_PERIOD / 4;

        -- Ora leggi: presenta addr ma we='0'.
        -- La BRAM è sincrona, dout esce 1 ciclo dopo addr applicato.
        addr <= x"00000000";
        we   <= '0';
        wait for CLK_PERIOD;
        wait for CLK_PERIOD / 4;
        assert dout = x"12345678"
            report "[2] DMEM read-after-write" severity error;
        report "[2] DMEM write+read OK" severity note;

        ----------------------------------------------------------------
        -- 3) GPIO_LED: scrivi 0xABCD su 0x00010008
        ----------------------------------------------------------------
        addr <= x"00010008";
        din  <= x"0000ABCD";
        we   <= '1';
        wait for CLK_PERIOD;
        we   <= '0';
        wait for CLK_PERIOD / 4;
        assert led_out = x"ABCD"
            report "[3] led_out dopo sw su GPIO_LED" severity error;
        report "[3] GPIO_LED write OK" severity note;

        ----------------------------------------------------------------
        -- 4) GPIO_SW: applica sw_in=0x55AA, attendi 2 cicli (sync),
        --    poi leggi 0x0001000C → dout dovrebbe essere 0x000055AA.
        ----------------------------------------------------------------
        sw_in <= x"55AA";
        wait for 2 * CLK_PERIOD;   -- attesa propagazione synchronizer

        addr <= x"0001000C";
        we   <= '0';
        wait for CLK_PERIOD;
        wait for CLK_PERIOD / 4;
        assert dout = x"000055AA"
            report "[4] dout su lettura GPIO_SW" severity error;
        report "[4] GPIO_SW read OK" severity note;

        ----------------------------------------------------------------
        -- 5) UART_STATUS quando UART è idle → bit 0 = '1' (ready)
        ----------------------------------------------------------------
        addr <= x"00010004";
        we   <= '0';
        wait for CLK_PERIOD;
        wait for CLK_PERIOD / 4;
        assert dout = x"00000001"
            report "[5] UART_STATUS idle (atteso 0x00000001 = ready)"
            severity error;
        report "[5] UART_STATUS idle OK" severity note;

        ----------------------------------------------------------------
        -- 6) UART_DATA: scrivi 0x41 ('A') → la UART parte.
        --    Dopo l'attivazione, uart_tx_pin va a '0' (start bit) e
        --    UART_STATUS bit 0 diventa '0' (busy).
        ----------------------------------------------------------------
        addr <= x"00010000";
        din  <= x"00000041";    -- 'A'
        we   <= '1';
        wait for CLK_PERIOD;
        we   <= '0';
        wait for CLK_PERIOD / 4;

        -- Adesso la UART è partita: tx_pin='0' (start), tx_busy='1'.
        assert uart_tx_pin = '0'
            report "[6] uart_tx_pin dovrebbe essere '0' (start bit)"
            severity error;

        -- Leggi UART_STATUS, deve essere busy (bit 0 = 0)
        addr <= x"00010004";
        wait for CLK_PERIOD;
        wait for CLK_PERIOD / 4;
        assert dout = x"00000000"
            report "[6] UART_STATUS dovrebbe essere busy (0x0)"
            severity error;
        report "[6] UART_DATA write + UART parte OK" severity note;

        -- Aspetta fine trasmissione: 10 bit * BAUD_DIV(4) = 40 cicli = 400 ns
        wait for 50 * CLK_PERIOD;

        -- A questo punto la UART dovrebbe essere tornata idle
        addr <= x"00010004";
        wait for CLK_PERIOD;
        wait for CLK_PERIOD / 4;
        assert dout = x"00000001"
            report "[6] UART_STATUS dovrebbe essere ready dopo TX"
            severity error;
        assert uart_tx_pin = '1'
            report "[6] uart_tx_pin dovrebbe essere '1' (idle) dopo TX"
            severity error;
        report "[6] UART torna in idle dopo TX OK" severity note;

        ----------------------------------------------------------------
        -- 7) Write su UART_STATUS (read-only) → deve essere ignorata.
        --    Tentiamo sw su 0x10004 con din diverso. La UART NON deve
        --    partire (tx_pin resta '1', tx non busy).
        ----------------------------------------------------------------
        addr <= x"00010004";
        din  <= x"FFFFFFFF";
        we   <= '1';
        wait for CLK_PERIOD;
        we   <= '0';
        wait for CLK_PERIOD / 4;

        assert uart_tx_pin = '1'
            report "[7] sw su UART_STATUS deve essere ignorata (tx_pin resta '1')"
            severity error;

        addr <= x"00010004";
        wait for CLK_PERIOD;
        wait for CLK_PERIOD / 4;
        assert dout = x"00000001"
            report "[7] UART_STATUS deve restare ready (sw ignorata)"
            severity error;
        report "[7] Write su read-only ignorata OK" severity note;

        ----------------------------------------------------------------
        report "tb_memory_map: tutti i test completati senza errori"
            severity note;
        wait;
    end process;
end sim;
