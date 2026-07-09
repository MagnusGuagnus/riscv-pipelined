----------------------------------------------------------------------------------
-- Module Name: uart_tx - Behavioral
-- Description: Trasmettitore UART asincrono, frame 8N1 (8 dati, no parity, 1 stop).
--   Parametrizzato via generic CLK_HZ e BAUD per facilitare la simulazione
--   (default 100 MHz / 115200 baud → BAUD_DIV = 868 cicli/bit).
--
--   Architettura:
--     - FSM a 4 stati: IDLE → START → DATA → STOP → IDLE
--     - Un solo stato "DATA" copre i 8 bit dati grazie a un bit_idx interno
--     - Shift register a 8 bit per i dati (LSB first, shift right)
--     - Baud counter conta da 0 a BAUD_DIV-1 e dà il "tick" di avanzamento
--     - tx_busy = '1' durante tutto il frame (start + dati + stop)
--
--   Interfaccia con la CPU (vista dal memory_map):
--     - tx_start: impulso di 1 ciclo per avviare la trasmissione
--     - tx_data : byte da trasmettere (latched al rising_edge in cui parte la TX)
--     - tx_pin  : linea seriale verso il chip USB-UART (poi pin esterno FPGA)
--     - tx_busy : '1' mentre la UART sta trasmettendo. Esposto come UART_STATUS
--                 bit 0 invertito (la CPU legge "ready" = NOT busy).
--
--   tx_start viene ignorato se la UART è già busy (no buffer interno: serve polling).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    generic (
        -- Frequenza clock di sistema in Hz. Default = 100 MHz (Nexys4 DDR).
        CLK_HZ : integer := 100_000_000;
        -- Baud rate target. Default = 115200, standard PuTTY/TeraTerm/screen.
        BAUD   : integer := 115_200
    );
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        tx_data  : in  std_logic_vector(7 downto 0);
        tx_start : in  std_logic;
        tx_pin   : out std_logic;
        tx_busy  : out std_logic
    );
end uart_tx;

architecture Behavioral of uart_tx is
    --------------------------------------------------------------------
    -- Costante derivata dai generic: numero di cicli di clock per ogni
    -- bit della linea seriale. A 100 MHz / 115200 baud = 868.
    -- In simulazione si può istanziare il modulo con BAUD = 25_000_000
    -- e ottenere BAUD_DIV = 4 → simulazione 200x più veloce.
    --------------------------------------------------------------------
    constant BAUD_DIV : integer := CLK_HZ / BAUD;

    -- Tipo della FSM
    type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
    signal state : state_t := S_IDLE;

    -- Shift register per i bit dati (LSB first → shift right)
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Contatore di quale bit dati stiamo trasmettendo (0..7)
    signal bit_idx : integer range 0 to 7 := 0;

    -- Contatore baud rate. Si dimensiona automaticamente in base a BAUD_DIV.
    -- range 0 to BAUD_DIV-1 permette al sintetizzatore di scegliere il minimo
    -- numero di bit (es. 10 bit per BAUD_DIV=868, 2 bit per BAUD_DIV=4).
    signal baud_cnt : integer range 0 to BAUD_DIV-1 := 0;

begin

    --------------------------------------------------------------------
    -- Unico process sincrono per FSM + datapath.
    --   Pattern: tutto registrato al rising_edge del clock.
    --   tx_pin è registrato (passa attraverso un flip-flop) per evitare
    --   glitch combinatori sulla linea seriale, che il PC interpreterebbe
    --   come bit spuri.
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Reset sincrono: torna in IDLE, linea TX a riposo ('1').
                state     <= S_IDLE;
                tx_pin    <= '1';
                tx_busy   <= '0';
                shift_reg <= (others => '0');
                bit_idx   <= 0;
                baud_cnt  <= 0;
            else
                case state is

                    ----------------------------------------------------
                    -- IDLE: linea a riposo. Aspetta tx_start.
                    ----------------------------------------------------
                    when S_IDLE =>
                        tx_pin  <= '1';
                        tx_busy <= '0';

                        if tx_start = '1' then
                            -- Carica il byte nello shift register
                            shift_reg <= tx_data;
                            -- Azzera contatori
                            baud_cnt  <= 0;
                            bit_idx   <= 0;
                            -- Inizia subito il bit di start: linea a '0'
                            tx_pin    <= '0';
                            tx_busy   <= '1';
                            state     <= S_START;
                        end if;

                    ----------------------------------------------------
                    -- START: tx_pin tenuto a '0' per BAUD_DIV cicli.
                    --   Quando baud_cnt raggiunge BAUD_DIV-1 si avanza
                    --   al primo bit dati.
                    ----------------------------------------------------
                    when S_START =>
                        tx_pin  <= '0';
                        tx_busy <= '1';

                        if baud_cnt = BAUD_DIV - 1 then
                            baud_cnt <= 0;
                            -- Carica il primo bit dati (LSB) sul tx_pin
                            tx_pin   <= shift_reg(0);
                            -- Shift right: il prossimo bit da emettere si
                            -- troverà in shift_reg(0) al ciclo dopo
                            shift_reg <= '0' & shift_reg(7 downto 1);
                            bit_idx   <= 0;
                            state     <= S_DATA;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- DATA: tx_pin = shift_reg(0). Ogni BAUD_DIV cicli
                    --   shifta a destra e incrementa bit_idx. Al bit 7
                    --   passa allo stato STOP.
                    ----------------------------------------------------
                    when S_DATA =>
                        tx_busy <= '1';
                        -- tx_pin resta al valore che era stato impostato
                        -- alla transizione precedente (o S_START → primo bit,
                        -- o S_DATA → bit successivo). NON lo riassegno qui
                        -- altrimenti durante BAUD_DIV-1 cicli "ricalcolerei"
                        -- shift_reg(0) che è già stato shiftato.

                        if baud_cnt = BAUD_DIV - 1 then
                            baud_cnt <= 0;
                            if bit_idx = 7 then
                                -- Finiti gli 8 bit dati → vai a STOP
                                tx_pin <= '1';     -- stop bit
                                state  <= S_STOP;
                            else
                                -- Avanza al bit dati successivo
                                tx_pin    <= shift_reg(0);
                                shift_reg <= '0' & shift_reg(7 downto 1);
                                bit_idx   <= bit_idx + 1;
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- STOP: tx_pin tenuto a '1' per BAUD_DIV cicli, poi
                    --   torna in IDLE.
                    ----------------------------------------------------
                    when S_STOP =>
                        tx_pin  <= '1';
                        tx_busy <= '1';   -- ancora busy durante il stop bit

                        if baud_cnt = BAUD_DIV - 1 then
                            baud_cnt <= 0;
                            tx_busy  <= '0';
                            state    <= S_IDLE;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
