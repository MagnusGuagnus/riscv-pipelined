----------------------------------------------------------------------------------
-- Testbench: tb_gpio
-- Verifica:
--   1. Dopo reset: led_out = 0x0000, sw_value = 0x0000
--   2. Scrittura LED: we='1' + din=0xABCD → al ciclo dopo led_out=0xABCD
--   3. Write enable disattivo: we='0' + din diverso → led_out resta 0xABCD
--   4. Scrittura LED nuova: we='1' + din=0x1234 → led_out=0x1234
--   5. Synchronizer switch: sw_in=0xBEEF → dopo 2 cicli sw_value=0xBEEF
--      (1 ciclo per FF1, 1 ciclo per FF2 → totale 2 cicli di latenza)
--   6. Cambio switch: sw_in=0xCAFE → dopo 2 cicli sw_value=0xCAFE
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_gpio is
end tb_gpio;

architecture sim of tb_gpio is
    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal reset    : std_logic := '1';
    signal we       : std_logic := '0';
    signal din      : std_logic_vector(15 downto 0) := (others => '0');
    signal led_out  : std_logic_vector(15 downto 0);
    signal sw_in    : std_logic_vector(15 downto 0) := (others => '0');
    signal sw_value : std_logic_vector(15 downto 0);

begin
    uut: entity work.gpio
        port map (
            clk      => clk,
            reset    => reset,
            we       => we,
            din      => din,
            led_out  => led_out,
            sw_in    => sw_in,
            sw_value => sw_value
        );

    -- Clock 100 MHz
    clk <= not clk after CLK_PERIOD / 2;

    stim: process
    begin
        ----------------------------------------------------------------
        -- 1) Reset per qualche ciclo
        ----------------------------------------------------------------
        reset <= '1';
        wait for 3 * CLK_PERIOD;
        reset <= '0';
        wait for CLK_PERIOD;

        assert led_out = x"0000"
            report "[1] led_out dopo reset (atteso 0x0000)" severity error;
        assert sw_value = x"0000"
            report "[1] sw_value dopo reset (atteso 0x0000)" severity error;
        report "[1] Reset OK" severity note;

        ----------------------------------------------------------------
        -- 2) Scrittura LED: we='1' + din=0xABCD
        --    Al rising edge prossimo, led_reg cattura din.
        --    Aspetto 1 ciclo per vedere il risultato su led_out.
        ----------------------------------------------------------------
        din <= x"ABCD";
        we  <= '1';
        wait for CLK_PERIOD;
        we  <= '0';
        -- Subito dopo il fronte led_out è già aggiornato (combinatorio
        -- diretto dall'uscita del registro). Aspetto un mezzo periodo
        -- per evitare race condition nel sampling dell'assert.
        wait for CLK_PERIOD / 4;
        assert led_out = x"ABCD"
            report "[2] led_out dopo scrittura 0xABCD" severity error;
        report "[2] Scrittura LED 0xABCD OK" severity note;

        ----------------------------------------------------------------
        -- 3) Hold con we='0': din cambia ma led_out NON deve cambiare
        ----------------------------------------------------------------
        din <= x"FFFF";   -- valore "civetta", non deve essere catturato
        we  <= '0';
        wait for 3 * CLK_PERIOD;
        assert led_out = x"ABCD"
            report "[3] led_out deve mantenere 0xABCD quando we='0'" severity error;
        report "[3] Hold con we=0 OK" severity note;

        ----------------------------------------------------------------
        -- 4) Scrittura nuova: we='1' + din=0x1234
        ----------------------------------------------------------------
        din <= x"1234";
        we  <= '1';
        wait for CLK_PERIOD;
        we  <= '0';
        wait for CLK_PERIOD / 4;
        assert led_out = x"1234"
            report "[4] led_out dopo scrittura 0x1234" severity error;
        report "[4] Scrittura LED 0x1234 OK" severity note;

        ----------------------------------------------------------------
        -- 5) Synchronizer switch.
        --    Cambio sw_in a 0xBEEF. Al primo rising_edge dopo il cambio,
        --    sw_sync1 cattura 0xBEEF. Al secondo, sw_sync2 = 0xBEEF.
        --    Quindi sw_value vede 0xBEEF dopo 2 cicli di clock.
        ----------------------------------------------------------------
        sw_in <= x"BEEF";
        -- Subito dopo (latenza 0): sw_value ancora vecchio
        wait for CLK_PERIOD / 4;
        assert sw_value /= x"BEEF"
            report "[5] sw_value non deve aggiornare istantaneamente (latenza sync)"
            severity error;
        -- Dopo 1 ciclo: sw_sync1=0xBEEF, sw_sync2=ancora vecchio
        wait for CLK_PERIOD;
        assert sw_value /= x"BEEF"
            report "[5] sw_value dopo 1 ciclo: ancora vecchio (sync 2 stadi)"
            severity error;
        -- Dopo 2 cicli (totale): sw_sync2 = 0xBEEF
        wait for CLK_PERIOD;
        assert sw_value = x"BEEF"
            report "[5] sw_value dopo 2 cicli deve essere 0xBEEF" severity error;
        report "[5] Synchronizer switch 0xBEEF OK (latenza 2 cicli)" severity note;

        ----------------------------------------------------------------
        -- 6) Cambio switch: 0xCAFE
        ----------------------------------------------------------------
        sw_in <= x"CAFE";
        wait for 2 * CLK_PERIOD;
        -- Dopo 2 cicli, sw_value deve essere 0xCAFE
        wait for CLK_PERIOD / 4;
        assert sw_value = x"CAFE"
            report "[6] sw_value dopo 2 cicli deve essere 0xCAFE" severity error;
        report "[6] Switch 0xCAFE propagato OK" severity note;

        ----------------------------------------------------------------
        report "tb_gpio: tutti i test completati senza errori" severity note;
        wait;
    end process;
end sim;
