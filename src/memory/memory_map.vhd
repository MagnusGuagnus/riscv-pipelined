----------------------------------------------------------------------------------
-- Module Name: memory_map - Behavioral
-- Description: Bus memory-mapped della CPU. Istanzia DMEM + UART_TX + GPIO e
--   fa il routing in base ad alcuni bit dell'indirizzo (pipeline 5-stadi).
--
--   Memory map (autoritativa):
--     DMEM        0x0000_0000 - 0x0000_3FFF   (16 kB, BRAM)   bit[16]=0
--     UART_DATA   0x0001_0000  (W)            bit[16]=1, bit[3]=0, bit[2]=0
--     UART_STATUS 0x0001_0004  (R, bit0=ready)               bit[16]=1, bit[3]=0, bit[2]=1
--     GPIO_LED    0x0001_0008  (W)            bit[16]=1, bit[3]=1, bit[2]=0
--     GPIO_SW     0x0001_000C  (R)            bit[16]=1, bit[3]=1, bit[2]=1
--
--   LATENZA DI LETTURA UNIFORME (1 ciclo) — importante per la pipeline
--   ================================================================
--   La DMEM e' BRAM a lettura sincrona: il dato esce 1 ciclo dopo l'indirizzo.
--   Perche' il modulo abbia UNA sola latenza di lettura, anche il path di
--   lettura delle periferiche (UART_STATUS / GPIO_SW) e' portato a 1 ciclo:
--   i selettori d'indirizzo e i valori periferici vengono REGISTRATI di 1
--   ciclo (snapshot al momento in cui l'indirizzo e' applicato) e usati dal
--   mux di dout. L'indirizzo e' applicato in MEM e il dato e' letto in WB:
--   cosi' TUTTE le letture (DMEM e periferiche) sono valide insieme in WB, e
--   usando l'output register della DMEM come registro MEM/WB il dato di load
--   (e di periferica) arriva al ciclo giusto.
--   Il WRITE routing resta combinatorio sull'indirizzo CORRENTE: lo store
--   committa nel ciclo in cui l'indirizzo e' applicato (stadio MEM/EXECUTE).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity memory_map is
    generic (
        CLK_HZ : integer := 100_000_000;
        BAUD   : integer := 115_200
    );
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        addr     : in  std_logic_vector(31 downto 0);   -- alu_pre_result
        we       : in  std_logic;                        -- mem_we
        din      : in  std_logic_vector(31 downto 0);    -- rs2_value
        dout     : out std_logic_vector(31 downto 0);    -- mem_out verso il regfile
        uart_tx_pin : out std_logic;
        led_out     : out std_logic_vector(15 downto 0);
        sw_in       : in  std_logic_vector(15 downto 0)
    );
end memory_map;

architecture Behavioral of memory_map is
    -- Selettori combinatori (per il WRITE routing, sull'indirizzo corrente)
    signal sel_periph    : std_logic;
    signal sel_uart_gpio : std_logic;
    signal sel_reg       : std_logic;

    -- Snapshot REGISTRATO dei selettori (per il READ mux, allineato alla BRAM)
    signal sel_periph_q    : std_logic := '0';
    signal sel_uart_gpio_q : std_logic := '0';
    signal sel_reg_q       : std_logic := '0';

    -- Routing del write enable (mutuamente esclusivi)
    signal dmem_we       : std_logic;
    signal uart_tx_start : std_logic;
    signal gpio_we       : std_logic;

    -- Segnali interni di interconnessione
    signal dmem_dout     : std_logic_vector(31 downto 0);
    signal uart_tx_busy  : std_logic;
    signal gpio_sw_value : std_logic_vector(15 downto 0);

    -- Valori periferici REGISTRATI di 1 ciclo (snapshot lettura, latenza = DMEM)
    signal uart_status_q : std_logic := '0';
    signal gpio_sw_q     : std_logic_vector(15 downto 0) := (others => '0');
begin

    --------------------------------------------------------------------
    -- 1) Address decoder combinatorio (usato per il WRITE routing)
    --------------------------------------------------------------------
    sel_periph    <= addr(16);
    sel_uart_gpio <= addr(3);
    sel_reg       <= addr(2);

    --------------------------------------------------------------------
    -- 2) Distribuzione del write enable (sull'indirizzo corrente).
    --   Al massimo uno di questi 3 e' '1' in un dato ciclo.
    --------------------------------------------------------------------
    dmem_we <= we when sel_periph = '0' else '0';

    uart_tx_start <= we when (sel_periph    = '1'
                          and sel_uart_gpio = '0'
                          and sel_reg       = '0') else '0';

    gpio_we <= we when (sel_periph    = '1'
                    and sel_uart_gpio = '1'
                    and sel_reg       = '0') else '0';

    --------------------------------------------------------------------
    -- 3) DMEM (lettura sincrona: dout 1 ciclo dopo l'indirizzo)
    --------------------------------------------------------------------
    u_dmem: entity work.data_memory
        port map (
            clk  => clk,
            we   => dmem_we,
            addr => addr(13 downto 2),
            din  => din,
            dout => dmem_dout
        );

    --------------------------------------------------------------------
    -- 4) UART TX
    --------------------------------------------------------------------
    u_uart: entity work.uart_tx
        generic map ( CLK_HZ => CLK_HZ, BAUD => BAUD )
        port map (
            clk      => clk,
            reset    => reset,
            tx_data  => din(7 downto 0),
            tx_start => uart_tx_start,
            tx_pin   => uart_tx_pin,
            tx_busy  => uart_tx_busy
        );

    --------------------------------------------------------------------
    -- 5) GPIO
    --------------------------------------------------------------------
    u_gpio: entity work.gpio
        port map (
            clk      => clk,
            reset    => reset,
            we       => gpio_we,
            din      => din(15 downto 0),
            led_out  => led_out,
            sw_in    => sw_in,
            sw_value => gpio_sw_value
        );

    --------------------------------------------------------------------
    -- 6) Snapshot di lettura REGISTRATO.
    --   Registra di 1 ciclo i selettori e i valori periferici, cosi' il mux
    --   di dout (sotto) ha la stessa latenza della DMEM (1 ciclo). E' cio'
    --   che permette alla pipeline di leggere le periferiche in WB col valore
    --   corretto.
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sel_periph_q    <= '0';
                sel_uart_gpio_q <= '0';
                sel_reg_q       <= '0';
                uart_status_q   <= '0';
                gpio_sw_q       <= (others => '0');
            else
                sel_periph_q    <= sel_periph;
                sel_uart_gpio_q <= sel_uart_gpio;
                sel_reg_q       <= sel_reg;
                uart_status_q   <= not uart_tx_busy;   -- bit0 = ready
                gpio_sw_q       <= gpio_sw_value;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- 7) Mux di dout (read path) — tutto a latenza 1 ciclo, selettori
    --   registrati. DMEM gia' registrata internamente; periferiche
    --   registrate al punto 6.
    --------------------------------------------------------------------
    dout <= dmem_dout
              when sel_periph_q = '0'
       else (31 downto 1 => '0') & uart_status_q
              when (sel_periph_q = '1' and sel_uart_gpio_q = '0' and sel_reg_q = '1')
       else x"0000" & gpio_sw_q
              when (sel_periph_q = '1' and sel_uart_gpio_q = '1' and sel_reg_q = '1')
       else (others => '0');

end Behavioral;
