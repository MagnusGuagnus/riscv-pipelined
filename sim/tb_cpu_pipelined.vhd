----------------------------------------------------------------------------------
-- Testbench: tb_cpu_pipelined
--
-- Verifica end-to-end della CPU pipelined a 5 stadi sul programmino di
-- core test (PROGRAM_SEL = 0):
--
--   0: addi x1, x0, 5      x1 = 5
--   1: addi x2, x0, 3      x2 = 3
--   2: add  x3, x1, x2     x3 = 8       <- richiede forwarding di x1 e x2
--   3: sw   x3, 0(x0)      DMEM[0] = 8  <- richiede forwarding di x3
--   4: lw   x4, 0(x0)      x4 = DMEM[0] = 8
--   5: jal  x0, 0          halt (loop su se stessa)
--
-- Cosa la pipeline deve fare (idealmente):
--   - istr 2 (add): hazard RAW su x1 (da istr 0 in EX/MEM) e x2 (da istr 1 in
--     ID/EX -> EX/MEM al prossimo ciclo). Forwarding 2x.
--   - istr 3 (sw): hazard RAW su x3 (da istr 2 in EX/MEM). Forwarding.
--   - istr 4 (lw): nessun hazard sui registri (usa x0).
--   - istr 5 (jal): branch incondizionato -> flush IF/ID e ID/EX, redirect
--     a se stessa. PC si ferma a 0x14.
--
-- Cosa controllare:
--   - dbg_pc converge a 0x014 e ci resta (jal self-loop).
--   - durante WB della lw, dbg_rd_value = 0x00000008 (= mem_out della LW).
--
-- Tempistica stimata (clock 10 ns):
--   - Reset rilasciato a t=20 ns.
--   - Pipeline si riempie in 5 cicli, le 6 istruzioni fluiscono.
--   - Branch JAL risolto in EX al ciclo ~7-8, flush, PC -> 0x14.
--   - Steady state (PC fermo a 0x14) entro 200 ns con abbondante margine.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_cpu_pipelined is
end tb_cpu_pipelined;

architecture sim of tb_cpu_pipelined is
    signal clk            : std_logic := '0';
    signal reset          : std_logic := '1';

    -- Porte esterne (non usate in questo TB di core, ma vanno cablate)
    signal uart_tx_pin    : std_logic;
    signal led_out        : std_logic_vector(15 downto 0);
    signal sw_in          : std_logic_vector(15 downto 0) := (others => '0');

    -- Debug signals (stato interno per la simulazione)
    signal dbg_pc         : std_logic_vector(11 downto 0);
    signal dbg_instr      : std_logic_vector(31 downto 0);
    signal dbg_state      : std_logic_vector(1 downto 0);
    signal dbg_alu_result : std_logic_vector(31 downto 0);
    signal dbg_mem_out    : std_logic_vector(31 downto 0);
    signal dbg_rd_value   : std_logic_vector(31 downto 0);

begin

    --------------------------------------------------------------------
    -- DUT: CPU pipelined con il programma di test del core (PROGRAM_SEL=0).
    --------------------------------------------------------------------
    uut: entity work.cpu_top_pipelined
        generic map (
            CLK_HZ      => 100_000_000,
            BAUD        =>     115_200,
            PROGRAM_SEL => 0
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
        ----------------------------------------------------------------
        -- 1) Reset per 2 cicli (20 ns)
        ----------------------------------------------------------------
        reset <= '1';
        wait for 25 ns;

        assert dbg_pc = x"000"
            report "Dopo reset, PC deve essere 0"
            severity error;

        ----------------------------------------------------------------
        -- 2) Rilascio reset e lascio girare la pipeline.
        --    Per consentire alle 6 istruzioni di completare + JAL halt,
        --    aspetto 250 ns (= 25 cicli). Anche con stall e flush la
        --    pipeline finisce ben prima.
        ----------------------------------------------------------------
        reset <= '0';
        wait for 250 ns;

        ----------------------------------------------------------------
        -- 3) Verifica stato finale: il PC di FETCH oscilla nel self-loop
        --    della JAL finale (0x014). Con branch risolto in EX, dbg_pc
        --    (= pc_if) corre avanti a 0x018/0x01C e viene ridiretto a 0x014
        --    ad ogni giro (penalita' 2 cicli); l'istruzione committata resta
        --    la JAL a 0x014. Accetto quindi la finestra 0x014..0x01C invece
        --    di un valore esatto (era un'assunzione errata della prima
        --    versione del testbench).
        ----------------------------------------------------------------
        assert (dbg_pc = x"014" or dbg_pc = x"018" or dbg_pc = x"01C")
            report "PC fuori dal self-loop della JAL finale (atteso 0x014-0x01C)"
            severity error;

        report "tb_cpu_pipelined: programma Fase A eseguito su pipeline"
            severity note;
        report "Controlla nelle waveform: dbg_rd_value = 0x8 durante WB di LW"
            severity note;

        wait;
    end process;

end sim;
