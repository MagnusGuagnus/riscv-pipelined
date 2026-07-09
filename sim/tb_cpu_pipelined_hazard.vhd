----------------------------------------------------------------------------------
-- Testbench: tb_cpu_pipelined_hazard
--
-- Verifica AUTO-CHECKING degli hazard della pipeline a 5 stadi, usando
-- PROGRAM_E (PROGRAM_SEL = 4) della instr_memory.
--
-- A differenza di tb_cpu_pipelined (che controlla solo il PC e lascia la
-- correttezza dei dati alle waveform), questo TB verifica il RISULTATO:
-- PROGRAM_E accumula una firma e la scrive su GPIO_LED. La firma e' corretta
-- solo se forwarding, load-use stall, branch (preso e non preso) e jal-link
-- funzionano tutti. Quindi un singolo assert su led_out copre tutti i casi.
--
--   Firma attesa : led_out = 0x004F  (= 79)
--   PC finale    : 0x040 (jal self-loop alla istr 16)
--
-- Se un hazard e' rotto, la firma cambia (es. bne erroneamente preso -> 0x4A,
-- branch non preso -> include 255, link rotto -> x8 != 44) e l'assert FALLISCE.
--
-- Tempistica: clock 10 ns. 17 istruzioni + 1 stall + 2 flush (beq) + 2 flush
-- (jal istr 10) + fill pipeline ~ 30 cicli. 400 ns danno margine abbondante.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_cpu_pipelined_hazard is
end tb_cpu_pipelined_hazard;

architecture sim of tb_cpu_pipelined_hazard is
    signal clk            : std_logic := '0';
    signal reset          : std_logic := '1';

    signal uart_tx_pin    : std_logic;
    signal led_out        : std_logic_vector(15 downto 0);
    signal sw_in          : std_logic_vector(15 downto 0) := (others => '0');

    signal dbg_pc         : std_logic_vector(11 downto 0);
    signal dbg_instr      : std_logic_vector(31 downto 0);
    signal dbg_state      : std_logic_vector(1 downto 0);
    signal dbg_alu_result : std_logic_vector(31 downto 0);
    signal dbg_mem_out    : std_logic_vector(31 downto 0);
    signal dbg_rd_value   : std_logic_vector(31 downto 0);

    constant EXPECTED_LED : std_logic_vector(15 downto 0) := x"004F";
begin

    --------------------------------------------------------------------
    -- DUT: CPU pipelined con il programma hazard-test (PROGRAM_SEL=4).
    --------------------------------------------------------------------
    uut: entity work.cpu_top_pipelined
        generic map (
            CLK_HZ      => 100_000_000,
            BAUD        =>     115_200,
            PROGRAM_SEL => 4
        )
        port map (
            clk            => clk,
            reset          => reset,
            uart_tx_pin    => uart_tx_pin,
            led_out        => led_out,
            sw_in          => sw_in,
            dbg_pc         => dbg_pc,
            dbg_instr      => dbg_instr,
            dbg_state      => dbg_state,
            dbg_alu_result => dbg_alu_result,
            dbg_mem_out    => dbg_mem_out,
            dbg_rd_value   => dbg_rd_value
        );

    -- Clock 100 MHz
    clk <= not clk after 5 ns;

    --------------------------------------------------------------------
    -- Stimolo + verifica
    --------------------------------------------------------------------
    stim: process
    begin
        -- 1) Reset per 2 cicli
        reset <= '1';
        wait for 25 ns;

        assert dbg_pc = x"000"
            report "Dopo reset, PC deve essere 0"
            severity failure;

        -- 2) Rilascio reset e lascio girare la pipeline
        reset <= '0';
        wait for 400 ns;

        -- 3) VERIFICA PRINCIPALE: la firma sui LED.
        --    Corretta solo se TUTTI gli hazard si comportano bene.
        assert led_out = EXPECTED_LED
            report "HAZARD TEST FALLITO: led_out diverso da 0x004F atteso. " &
                   "Un hazard (forwarding/stall/branch/jal-link) e' rotto."
            severity failure;

        -- 4) Verifica secondaria: il fetch PC oscilla nel self-loop del jal
        --    finale. Con branch risolto in EX, dbg_pc (= pc_if di fetch) corre
        --    avanti e viene ridiretto a 0x040 ad ogni giro (il commit resta a
        --    0x040). Accetto quindi la finestra di oscillazione 0x040..0x04C
        --    invece di un valore esatto: la firma sui LED e' il check vero.
        assert (dbg_pc = x"040" or dbg_pc = x"044"
             or dbg_pc = x"048" or dbg_pc = x"04C")
            report "PC fuori dal self-loop del jal finale (atteso 0x040-0x04C)"
            severity failure;

        report "tb_cpu_pipelined_hazard: PASS - firma 0x004F corretta, " &
               "forwarding + stall + branch + jal-link OK"
            severity note;

        wait;
    end process;

end sim;
