----------------------------------------------------------------------------------
-- Testbench: tb_uart_tx
-- Strategia:
--   Istanzia uart_tx con BAUD_DIV = 4 (CLK_HZ=100M, BAUD=25M) per simulare 200x
--   più veloce della config reale 868 cicli/bit.
--   Con clk_period = 10 ns → bit_period = 40 ns → byte intero (10 bit) = 400 ns.
--
-- Verifiche:
--   1. Dopo reset → IDLE: tx_pin='1', tx_busy='0'.
--   2. Trasmissione di 0x55 = "01010101": verifica bit a bit la sequenza sulla
--      linea tx_pin (start='0', bit0='1', bit1='0', ..., bit7='0', stop='1'),
--      e verifica che tx_busy resti '1' per tutto il frame.
--   3. Dopo il frame, tx_pin='1' e tx_busy='0' (back to IDLE).
--   4. Trasmissione di un secondo byte 0xA5 = "10100101": verifica che il
--      modulo possa essere riusato (non ci sono stati residui).
--   5. tx_start ignorato durante busy: durante la TX di 0xA5, alzo tx_start
--      con tx_data=0x00 e verifico che la sequenza emessa resti quella di 0xA5
--      (no reset/perdita di byte).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_uart_tx is
end tb_uart_tx;

architecture sim of tb_uart_tx is
    --------------------------------------------------------------------
    -- Parametri di simulazione
    --------------------------------------------------------------------
    constant CLK_PERIOD : time    := 10 ns;       -- 100 MHz
    constant BAUD_DIV   : integer := 4;           -- cicli/bit (in sim)
    constant BIT_PERIOD : time    := BAUD_DIV * CLK_PERIOD;  -- 40 ns

    --------------------------------------------------------------------
    -- Segnali DUT
    --------------------------------------------------------------------
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_start : std_logic := '0';
    signal tx_pin   : std_logic;
    signal tx_busy  : std_logic;

begin
    --------------------------------------------------------------------
    -- DUT: UART TX parametrizzata per simulazione veloce.
    --   CLK_HZ=100_000_000, BAUD=25_000_000 → BAUD_DIV = 100M/25M = 4.
    --------------------------------------------------------------------
    uut: entity work.uart_tx
        generic map (
            CLK_HZ => 100_000_000,
            BAUD   =>  25_000_000
        )
        port map (
            clk      => clk,
            reset    => reset,
            tx_data  => tx_data,
            tx_start => tx_start,
            tx_pin   => tx_pin,
            tx_busy  => tx_busy
        );

    -- Clock 100 MHz: period 10 ns, duty 50%.
    clk <= not clk after CLK_PERIOD / 2;

    --------------------------------------------------------------------
    -- Process di stimolo
    --------------------------------------------------------------------
    stim: process
    begin
        ----------------------------------------------------------------
        -- 1) Reset: tieni reset='1' per 3 cicli, poi rilascia.
        --    Dopo il rilascio del reset → IDLE.
        ----------------------------------------------------------------
        reset <= '1';
        wait for 3 * CLK_PERIOD;
        reset <= '0';
        wait for CLK_PERIOD;

        assert tx_pin = '1'
            report "[1] IDLE: tx_pin dovrebbe essere '1' (linea a riposo)"
            severity error;
        assert tx_busy = '0'
            report "[1] IDLE: tx_busy dovrebbe essere '0'"
            severity error;

        report "[1] Reset OK, modulo in IDLE" severity note;

        ----------------------------------------------------------------
        -- 2) Trasmissione di 0x55 = "0101_0101"
        --    LSB first: bit0=1, bit1=0, bit2=1, bit3=0, bit4=1, bit5=0,
        --    bit6=1, bit7=0
        --    Frame atteso sul filo: 0 1 0 1 0 1 0 1 0 1
        --                          (start b0 b1 b2 b3 b4 b5 b6 b7 stop)
        ----------------------------------------------------------------
        tx_data  <= x"55";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        -- A questo punto la FSM ha appena fatto la transizione IDLE → S_START
        -- e tx_pin è andato a '0' (start bit). Mi posiziono al centro
        -- dello slot START per il primo assert.
        wait for BIT_PERIOD / 2;

        assert tx_pin = '0'
            report "[2] start bit (atteso '0')" severity error;
        assert tx_busy = '1'
            report "[2] tx_busy dovrebbe essere '1' durante TX" severity error;

        -- bit 0 = '1'
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[2] bit 0 di 0x55 (atteso '1')" severity error;
        -- bit 1 = '0'
        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[2] bit 1 di 0x55 (atteso '0')" severity error;
        -- bit 2 = '1'
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[2] bit 2 di 0x55 (atteso '1')" severity error;
        -- bit 3 = '0'
        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[2] bit 3 di 0x55 (atteso '0')" severity error;
        -- bit 4 = '1'
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[2] bit 4 di 0x55 (atteso '1')" severity error;
        -- bit 5 = '0'
        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[2] bit 5 di 0x55 (atteso '0')" severity error;
        -- bit 6 = '1'
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[2] bit 6 di 0x55 (atteso '1')" severity error;
        -- bit 7 = '0'
        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[2] bit 7 di 0x55 (atteso '0')" severity error;

        -- stop bit = '1'
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[2] stop bit (atteso '1')" severity error;
        assert tx_busy = '1'
            report "[2] tx_busy deve restare '1' durante lo stop bit"
            severity error;

        -- Fine del frame: aspetta che si torni in IDLE.
        -- Dopo lo slot di STOP la FSM riassegna tx_busy='0' e torna in IDLE.
        wait for BIT_PERIOD;
        assert tx_pin  = '1'
            report "[2] post-TX: tx_pin deve restare '1' in IDLE" severity error;
        assert tx_busy = '0'
            report "[2] post-TX: tx_busy deve tornare '0'" severity error;

        report "[2] TX 0x55 OK" severity note;

        ----------------------------------------------------------------
        -- 3) Trasmissione di un secondo byte 0xA5 = "1010_0101"
        --    Verifica che il modulo riparta pulito dopo il primo byte.
        --    LSB first: bit0=1, bit1=0, bit2=1, bit3=0, bit4=0, bit5=1,
        --    bit6=0, bit7=1
        --
        --    Durante la TX, al bit 3 provo a forzare tx_start con un
        --    tx_data=0x00 diverso → mi aspetto che il modulo IGNORI
        --    il nuovo tx_start (è busy) e continui a emettere 0xA5.
        ----------------------------------------------------------------
        tx_data  <= x"A5";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';
        wait for BIT_PERIOD / 2;  -- centro dello start

        assert tx_pin = '0' report "[3] start bit (atteso '0')" severity error;

        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[3] bit 0 (atteso '1')" severity error;
        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[3] bit 1 (atteso '0')" severity error;
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[3] bit 2 (atteso '1')" severity error;

        -- Tentativo di "interrompere" la TX corrente con un nuovo tx_start
        -- e tx_data diverso. Deve essere ignorato.
        tx_data  <= x"00";
        tx_start <= '1';
        wait for BIT_PERIOD;
        tx_start <= '0';
        -- siamo a circa metà di bit 3 → atteso '0' (bit 3 di 0xA5)
        assert tx_pin = '0'
            report "[3] bit 3 (atteso '0', tx_start interrotto deve essere ignorato)"
            severity error;

        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[3] bit 4 (atteso '0')" severity error;
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[3] bit 5 (atteso '1')" severity error;
        wait for BIT_PERIOD;
        assert tx_pin = '0' report "[3] bit 6 (atteso '0')" severity error;
        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[3] bit 7 (atteso '1')" severity error;

        wait for BIT_PERIOD;
        assert tx_pin = '1' report "[3] stop bit (atteso '1')" severity error;

        wait for BIT_PERIOD;
        assert tx_busy = '0' report "[3] back to IDLE" severity error;

        report "[3] TX 0xA5 OK + tx_start ignorato durante busy" severity note;

        ----------------------------------------------------------------
        -- Fine
        ----------------------------------------------------------------
        report "tb_uart_tx: tutti i test completati senza errori" severity note;
        wait;
    end process;
end sim;
