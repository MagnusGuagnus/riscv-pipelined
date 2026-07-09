----------------------------------------------------------------------------------
-- Module Name: gpio - Behavioral
-- Description: Periferica GPIO memory-mapped per Nexys4 DDR.
--   - Output: registro 16-bit pilotato dalla CPU (write enable + din).
--             L'uscita led_out è cablata ai 16 LED fisici della scheda.
--   - Input:  16 switch fisici della scheda, letti attraverso un
--             synchronizer a 2 stadi per evitare metastabilità (gli
--             switch sono asincroni rispetto al clock di sistema).
--
--   La CPU vede questo modulo a due indirizzi memory-mapped:
--     GPIO_LED  (0x10008, W)  → din si latcha in led_reg quando we='1'
--     GPIO_SW   (0x1000C, R)  → sw_value si legge sempre (read-only sincr.)
--
--   Larghezza dati: 16 bit. La CPU lavora a 32 bit; sarà compito di
--   memory_map.vhd fare il truncate in scrittura (din <= rs2_value[15:0])
--   e la zero-extension in lettura (mem_out <= x"0000" & sw_value).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity gpio is
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        -- Write side (LED)
        we       : in  std_logic;
        din      : in  std_logic_vector(15 downto 0);
        led_out  : out std_logic_vector(15 downto 0);
        -- Read side (switch)
        sw_in    : in  std_logic_vector(15 downto 0);
        sw_value : out std_logic_vector(15 downto 0)
    );
end gpio;

architecture Behavioral of gpio is
    -- Registro LED: contiene il valore corrente dei 16 LED.
    -- Si aggiorna al rising_edge quando we='1', oppure si azzera al reset.
    signal led_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Synchronizer a 2 stadi per gli switch: due flip-flop in cascata
    -- che assorbono le eventuali transizioni metastabili degli switch
    -- (segnali esterni asincroni).
    signal sw_sync1 : std_logic_vector(15 downto 0) := (others => '0');
    signal sw_sync2 : std_logic_vector(15 downto 0) := (others => '0');

begin

    --------------------------------------------------------------------
    -- Process 1: registro LED.
    --   Pattern classico: load enable + reset sincrono.
    --   we='1' → led_reg cattura din; we='0' → led_reg mantiene il valore.
    --------------------------------------------------------------------
    led_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                led_reg <= (others => '0');
            elsif we = '1' then
                led_reg <= din;
            end if;
        end if;
    end process;

    -- L'uscita led_out è l'uscita del registro. Combinatorio diretto.
    led_out <= led_reg;

    --------------------------------------------------------------------
    -- Process 2: synchronizer 2-FF per gli switch.
    --   FF1 (sw_sync1) può andare metastabile su una transizione "sfigata"
    --   di sw_in, ma ha 1 intero ciclo di clock per stabilizzarsi prima
    --   che FF2 (sw_sync2) lo campioni. sw_sync2 è quindi affidabile
    --   per essere usato dalla CPU.
    --------------------------------------------------------------------
    sync_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sw_sync1 <= (others => '0');
                sw_sync2 <= (others => '0');
            else
                sw_sync1 <= sw_in;
                sw_sync2 <= sw_sync1;
            end if;
        end if;
    end process;

    -- L'uscita verso la CPU è il secondo stadio del synchronizer.
    sw_value <= sw_sync2;

end Behavioral;
