----------------------------------------------------------------------------------
-- Module Name : cpu_top_pipelined - Behavioral
--
-- VERSIONE PIPELINED 5-STAGE della CPU RISC-V (estensione architetturale).
--
-- ARCHITETTURA (5 stadi, 4 pipeline register canonici)
-- ====================================================
--   IF -> ID -> EX -> MEM -> WB
--   pipeline register: IF/ID, ID/EX, EX/MEM, MEM/WB
--
-- NOTA DI PROGETTO IMPORTANTE — le BRAM come registri di pipeline
-- =============================================================
-- IMEM e DMEM sono BRAM a LETTURA SINCRONA: il loro output e' gia' un
-- registro (1 ciclo di latenza). Invece di mettere un SECONDO registro a
-- valle (che aggiungerebbe stadi nascosti, rompendo lo schema 5-stadi e
-- introducendo bug di disallineamento), usiamo l'output register della BRAM
-- COME registro di pipeline:
--   * l'output della IMEM E' il registro IF/ID per l'istruzione;
--   * l'output della DMEM E' il registro MEM/WB per il dato di load.
-- Cio' che la BRAM non porta con se' (il PC dell'istruzione, il bit di
-- validita') lo registriamo a parte, allineato. Cosi' lo schema resta
-- esattamente a 4 pipeline register.
--
-- Conseguenze pratiche di questa scelta:
--   1. Stall load-use: si congela l'output BRAM IMEM con un read-enable
--      (re = not stall), non un registro a valle.
--   2. Flush branch: l'output BRAM non si puo' forzare a NOP, quindi si usa
--      un bit di validita' (ifid_valid): se '0' il decoder vede una NOP.
--   3. Load: l'indirizzo DMEM e' quello REGISTRATO dello stadio MEM
--      (exmem_alu_result); il dato esce in WB ed e' letto LIVE dall'output
--      della DMEM (mem_out_mem), senza un registro mem_out aggiuntivo.
--
-- HAZARD
-- ======
--   * RAW: forwarding EX/MEM->EX e MEM/WB->EX (forwarding_unit).
--   * Load-use: stall di 1 ciclo (hazard_unit) + bolla in ID/EX.
--   * WB->ID stesso ciclo: gestito dal regfile_dp write-first (bypass).
--   * Control (branch/jump taken): risolto in EX, flush dei 2 stadi
--     precedenti, redirect del PC. Penalita' 2 cicli.
--
-- INTERFACCIA ESTERNA: usata dal wrapper di board (nexys4ddr_top).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_top_pipelined is
    generic (
        CLK_HZ      : integer := 100_000_000;
        BAUD        : integer := 115_200;
        PROGRAM_SEL : integer := 0
    );
    port (
        clk             : in  std_logic;
        reset           : in  std_logic;
        uart_tx_pin     : out std_logic;
        led_out         : out std_logic_vector(15 downto 0);
        sw_in           : in  std_logic_vector(15 downto 0);
        -- Debug (riusati per simulazione, mostrano lo stato dello stadio EX)
        dbg_pc          : out std_logic_vector(11 downto 0);
        dbg_instr       : out std_logic_vector(31 downto 0);
        dbg_state       : out std_logic_vector(1 downto 0);
        dbg_alu_result  : out std_logic_vector(31 downto 0);
        dbg_mem_out     : out std_logic_vector(31 downto 0);
        dbg_rd_value    : out std_logic_vector(31 downto 0)
    );
end cpu_top_pipelined;

architecture Behavioral of cpu_top_pipelined is

    constant NOP_INSTR : std_logic_vector(31 downto 0) := x"00000013";

    --------------------------------------------------------------------
    -- IF STAGE
    --------------------------------------------------------------------
    signal pc_if         : std_logic_vector(11 downto 0) := (others => '0');
    signal pc_next_if    : std_logic_vector(11 downto 0);
    signal pc_in         : std_logic_vector(11 downto 0);
    signal instruction_if: std_logic_vector(31 downto 0);  -- output BRAM = istruzione IF/ID
    signal pc_word_if    : std_logic_vector(9 downto 0);
    signal pc_write_en   : std_logic;
    signal pc_redirect   : std_logic;       -- '1' se branch/jump taken in EX
    signal pc_target     : std_logic_vector(11 downto 0);
    signal imem_re       : std_logic;  -- read-enable BRAM IMEM = not stall

    --------------------------------------------------------------------
    -- IF/ID PIPELINE REGISTER
    --   L'istruzione vive nell'output register della BRAM (instruction_if).
    --   Qui teniamo solo cio' che la BRAM non porta: il PC compagno e il
    --   bit di validita' (per il flush).
    --------------------------------------------------------------------
    signal pc_if_q     : std_logic_vector(11 downto 0) := (others => '0');
    signal pc_next_q   : std_logic_vector(11 downto 0) := (others => '0');
    signal ifid_valid  : std_logic := '0';
    signal id_instr    : std_logic_vector(31 downto 0);  -- istruzione vista da ID (NOP se non valida)

    --------------------------------------------------------------------
    -- ID STAGE
    --------------------------------------------------------------------
    signal rs1_addr_id : std_logic_vector(4 downto 0);
    signal rs2_addr_id : std_logic_vector(4 downto 0);
    signal rd_addr_id  : std_logic_vector(4 downto 0);
    signal rs1_value_id: std_logic_vector(31 downto 0);
    signal rs2_value_id: std_logic_vector(31 downto 0);
    signal immediate_id: std_logic_vector(31 downto 0);
    signal op_class_id : std_logic_vector(4 downto 0);
    signal alu_op_id   : std_logic_vector(2 downto 0);
    signal cond_op_id  : std_logic_vector(2 downto 0);
    signal a_sel_id    : std_logic;
    signal b_sel_id    : std_logic;
    signal imm_type_id : std_logic_vector(2 downto 0);
    signal is_lui_id   : std_logic;

    --------------------------------------------------------------------
    -- ID/EX PIPELINE REGISTER
    --------------------------------------------------------------------
    signal idex_pc        : std_logic_vector(11 downto 0) := (others => '0');
    signal idex_pc_next   : std_logic_vector(11 downto 0) := (others => '0');
    signal idex_rs1_value : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_rs2_value : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_immediate : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_rs1_addr  : std_logic_vector(4 downto 0)  := (others => '0');
    signal idex_rs2_addr  : std_logic_vector(4 downto 0)  := (others => '0');
    signal idex_rd_addr   : std_logic_vector(4 downto 0)  := (others => '0');
    signal idex_op_class  : std_logic_vector(4 downto 0)  := (others => '0');
    signal idex_alu_op    : std_logic_vector(2 downto 0)  := (others => '0');
    signal idex_cond_op   : std_logic_vector(2 downto 0)  := (others => '0');
    signal idex_a_sel     : std_logic := '0';
    signal idex_b_sel     : std_logic := '0';
    signal idex_is_load   : std_logic;
    signal idex_is_lui    : std_logic := '0';

    --------------------------------------------------------------------
    -- EX STAGE
    --------------------------------------------------------------------
    signal fwd_a, fwd_b      : std_logic_vector(1 downto 0);
    signal rs1_fwd, rs2_fwd  : std_logic_vector(31 downto 0);
    signal alu_a_ex, alu_b_ex: std_logic_vector(31 downto 0);
    signal pc_ex_32          : std_logic_vector(31 downto 0);
    signal alu_result_ex     : std_logic_vector(31 downto 0);
    signal alu_result_latched: std_logic_vector(31 downto 0);
    signal branch_cond_ex    : std_logic;
    signal branch_taken_ex   : std_logic;

    --------------------------------------------------------------------
    -- EX/MEM PIPELINE REGISTER
    --------------------------------------------------------------------
    signal exmem_alu_result : std_logic_vector(31 downto 0) := (others => '0');
    signal exmem_rs2_value  : std_logic_vector(31 downto 0) := (others => '0');
    signal exmem_pc_next    : std_logic_vector(11 downto 0) := (others => '0');
    signal exmem_rd_addr    : std_logic_vector(4 downto 0)  := (others => '0');
    signal exmem_op_class   : std_logic_vector(4 downto 0)  := (others => '0');
    signal exmem_regwrite   : std_logic := '0';
    signal exmem_memwrite   : std_logic := '0';

    --------------------------------------------------------------------
    -- MEM STAGE — l'output della BRAM DMEM (mem_out_mem) e' il dato di load
    -- dello stadio MEM/WB, letto LIVE in WB. Non serve un registro mem_out.
    --------------------------------------------------------------------
    signal mem_out_mem      : std_logic_vector(31 downto 0);

    --------------------------------------------------------------------
    -- MEM/WB PIPELINE REGISTER (senza mem_out: lo tiene la BRAM DMEM)
    --------------------------------------------------------------------
    signal memwb_alu_result : std_logic_vector(31 downto 0) := (others => '0');
    signal memwb_pc_next_32 : std_logic_vector(31 downto 0) := (others => '0');
    signal memwb_rd_addr    : std_logic_vector(4 downto 0)  := (others => '0');
    signal memwb_op_class   : std_logic_vector(4 downto 0)  := (others => '0');
    signal memwb_regwrite   : std_logic := '0';

    --------------------------------------------------------------------
    -- WB STAGE
    --------------------------------------------------------------------
    signal wb_data : std_logic_vector(31 downto 0);

    --------------------------------------------------------------------
    -- HAZARD / STALL / FLUSH
    --------------------------------------------------------------------
    signal stall      : std_logic;
    signal flush_ifid : std_logic;
    signal flush_idex : std_logic;

begin

    --==================================================================
    -- IF STAGE
    --==================================================================
    pc_next_if  <= std_logic_vector(unsigned(pc_if) + 4);
    pc_in       <= pc_target when pc_redirect = '1' else pc_next_if;
    pc_write_en <= not stall;
    imem_re     <= not stall;   -- durante lo stall l'output BRAM IMEM tiene il valore

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pc_if <= (others => '0');
            elsif pc_write_en = '1' then
                pc_if <= pc_in;
            end if;
        end if;
    end process;

    pc_word_if <= pc_if(11 downto 2);

    -- L'output register di questa BRAM E' il registro IF/ID (lato istruzione).
    u_imem: entity work.instr_memory
        generic map ( PROGRAM_SEL => PROGRAM_SEL )
        port map (
            clk         => clk,
            re          => imem_re,
            addr        => pc_word_if,
            instruction => instruction_if
        );

    --==================================================================
    -- IF/ID PIPELINE REGISTER (PC compagno + valid)
    --   L'istruzione e' gia' registrata dalla BRAM. Qui registriamo il PC
    --   (e PC+4) allineati all'output BRAM, e il bit di validita'.
    --   reset/flush -> non valido (squash); stall -> congela; else -> avanza.
    --==================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or flush_ifid = '1' then
                pc_if_q    <= (others => '0');
                pc_next_q  <= (others => '0');
                ifid_valid <= '0';
            elsif stall = '1' then
                null;  -- congelato (anche la BRAM IMEM e' congelata da re)
            else
                pc_if_q    <= pc_if;
                pc_next_q  <= pc_next_if;
                ifid_valid <= '1';
            end if;
        end if;
    end process;

    -- Squash: se la slot IF/ID non e' valida (flush/reset) il decoder vede NOP.
    id_instr <= instruction_if when ifid_valid = '1' else NOP_INSTR;

    --==================================================================
    -- ID STAGE
    --==================================================================
    rs1_addr_id <= id_instr(19 downto 15);
    rs2_addr_id <= id_instr(24 downto 20);
    rd_addr_id  <= id_instr(11 downto 7);

    u_decoder: entity work.decoder
        port map (
            instr       => id_instr,
            op_class    => op_class_id,
            alu_opcode  => alu_op_id,
            cond_opcode => cond_op_id,
            a_sel       => a_sel_id,
            b_sel       => b_sel_id,
            imm_type    => imm_type_id,
            is_lui      => is_lui_id
        );

    u_imm: entity work.immediate_gen
        port map (
            instr    => id_instr,
            imm_type => imm_type_id,
            imm_out  => immediate_id
        );

    u_regfile: entity work.regfile_dp
        port map (
            clk      => clk,
            we       => memwb_regwrite,
            wr_addr  => memwb_rd_addr,
            wr_data  => wb_data,
            rs1_addr => rs1_addr_id,
            rs1_data => rs1_value_id,
            rs2_addr => rs2_addr_id,
            rs2_data => rs2_value_id
        );

    --==================================================================
    -- HAZARD UNIT (combinatorio, deve essere collegato PRIMA di ID/EX)
    --==================================================================
    idex_is_load <= idex_op_class(2);

    u_hazard: entity work.hazard_unit
        port map (
            idex_is_load => idex_is_load,
            idex_rd      => idex_rd_addr,
            ifid_rs1     => rs1_addr_id,
            ifid_rs2     => rs2_addr_id,
            stall        => stall
        );

    -- flush_idex e' alto se branch taken in EX, OPPURE se siamo in stall
    -- (in entrambi i casi voglio iniettare una NOP nel pipeline register ID/EX).
    flush_idex <= pc_redirect or stall;

    --==================================================================
    -- ID/EX PIPELINE REGISTER
    --==================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or flush_idex = '1' then
                -- Bolla NOP: azzera tutti i control signal cosi' EX/MEM/WB
                -- non producono effetti collaterali.
                idex_pc        <= (others => '0');
                idex_pc_next   <= (others => '0');
                idex_rs1_value <= (others => '0');
                idex_rs2_value <= (others => '0');
                idex_immediate <= (others => '0');
                idex_rs1_addr  <= (others => '0');
                idex_rs2_addr  <= (others => '0');
                idex_rd_addr   <= (others => '0');
                idex_op_class  <= (others => '0');
                idex_alu_op    <= (others => '0');
                idex_cond_op   <= (others => '0');
                idex_a_sel     <= '0';
                idex_b_sel     <= '0';
                idex_is_lui    <= '0';
            else
                idex_pc        <= pc_if_q;      -- PC allineato (vedi IF/ID)
                idex_pc_next   <= pc_next_q;
                idex_rs1_value <= rs1_value_id;
                idex_rs2_value <= rs2_value_id;
                idex_immediate <= immediate_id;
                idex_rs1_addr  <= rs1_addr_id;
                idex_rs2_addr  <= rs2_addr_id;
                idex_rd_addr   <= rd_addr_id;
                idex_op_class  <= op_class_id;
                idex_alu_op    <= alu_op_id;
                idex_cond_op   <= cond_op_id;
                idex_a_sel     <= a_sel_id;
                idex_b_sel     <= b_sel_id;
                idex_is_lui    <= is_lui_id;
            end if;
        end if;
    end process;

    --==================================================================
    -- EX STAGE
    --==================================================================

    -- Forwarding unit: combinatoriamente decide se prendere i valori
    -- da regfile (00), da EX/MEM (01), o da MEM/WB (10).
    u_forward: entity work.forwarding_unit
        port map (
            idex_rs1       => idex_rs1_addr,
            idex_rs2       => idex_rs2_addr,
            exmem_rd       => exmem_rd_addr,
            exmem_regwrite => exmem_regwrite,
            memwb_rd       => memwb_rd_addr,
            memwb_regwrite => memwb_regwrite,
            fwd_a          => fwd_a,
            fwd_b          => fwd_b
        );

    -- Mux di forwarding sui due operandi
    rs1_fwd <= exmem_alu_result when fwd_a = "01"
          else wb_data          when fwd_a = "10"
          else idex_rs1_value;

    rs2_fwd <= exmem_alu_result when fwd_b = "01"
          else wb_data          when fwd_b = "10"
          else idex_rs2_value;

    -- Mux operandi ALU (a_sel: 0=PC, 1=rs1; b_sel: 0=rs2, 1=imm)
    pc_ex_32 <= x"00000" & idex_pc;
    -- LUI: alu_a forzato a 0 (qui in EX, fuori dal cammino di lettura del regfile)
    -- cosi' rd = 0 + immediato_U. Altrimenti: 0=PC, 1=rs1.
    alu_a_ex <= (others => '0') when idex_is_lui = '1'
           else pc_ex_32        when idex_a_sel = '0'
           else rs1_fwd;
    alu_b_ex <= rs2_fwd  when idex_b_sel = '0' else idex_immediate;  -- 0=rs2, 1=imm

    u_alu: entity work.alu
        port map (
            clk            => clk,
            a              => alu_a_ex,
            b              => alu_b_ex,
            alu_opcode     => idex_alu_op,
            alu_pre_result => alu_result_ex,
            alu_result     => alu_result_latched
        );

    -- Comparator combinatorio replicato (l'EX risolve il branch nello stesso ciclo)
    process(idex_cond_op, rs1_fwd, rs2_fwd)
        variable sa, sb : signed(31 downto 0);
    begin
        sa := signed(rs1_fwd);
        sb := signed(rs2_fwd);
        branch_cond_ex <= '0';
        case idex_cond_op is
            when "000"  => if sa = sb  then branch_cond_ex <= '1'; end if;
            when "001"  => if sa /= sb then branch_cond_ex <= '1'; end if;
            when "100"  => if sa < sb  then branch_cond_ex <= '1'; end if;
            when "101"  => if sa >= sb then branch_cond_ex <= '1'; end if;
            when others => null;
        end case;
    end process;

    branch_taken_ex <= (idex_op_class(3) and branch_cond_ex)  -- B-type con condizione
                   or  idex_op_class(4);                      -- J-type (sempre)
    pc_redirect <= branch_taken_ex;
    pc_target   <= alu_result_ex(11 downto 0);
    flush_ifid  <= pc_redirect;

    --==================================================================
    -- EX/MEM PIPELINE REGISTER
    --==================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                exmem_alu_result <= (others => '0');
                exmem_rs2_value  <= (others => '0');
                exmem_pc_next    <= (others => '0');
                exmem_rd_addr    <= (others => '0');
                exmem_op_class   <= (others => '0');
                exmem_regwrite   <= '0';
                exmem_memwrite   <= '0';
            else
                exmem_alu_result <= alu_result_ex;
                exmem_rs2_value  <= rs2_fwd;
                exmem_pc_next    <= idex_pc_next;
                exmem_rd_addr    <= idex_rd_addr;
                exmem_op_class   <= idex_op_class;
                exmem_regwrite   <= idex_op_class(0) or idex_op_class(2) or idex_op_class(4);
                exmem_memwrite   <= idex_op_class(1);
            end if;
        end if;
    end process;

    --==================================================================
    -- MEM STAGE
    --   Indirizzo REGISTRATO (stadio MEM): la lettura DMEM sincrona parte qui
    --   e il dato esce in WB, dove l'output register della BRAM (mem_out_mem)
    --   fa da registro MEM/WB. Timing comodo (registro -> BRAM).
    --==================================================================
    u_mmap: entity work.memory_map
        generic map ( CLK_HZ => CLK_HZ, BAUD => BAUD )
        port map (
            clk         => clk,
            reset       => reset,
            addr        => exmem_alu_result,
            we          => exmem_memwrite,
            din         => exmem_rs2_value,
            dout        => mem_out_mem,
            uart_tx_pin => uart_tx_pin,
            led_out     => led_out,
            sw_in       => sw_in
        );

    --==================================================================
    -- MEM/WB PIPELINE REGISTER (mem_out NON registrato: lo tiene la BRAM DMEM)
    --==================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                memwb_alu_result <= (others => '0');
                memwb_pc_next_32 <= (others => '0');
                memwb_rd_addr    <= (others => '0');
                memwb_op_class   <= (others => '0');
                memwb_regwrite   <= '0';
            else
                memwb_alu_result <= exmem_alu_result;
                memwb_pc_next_32 <= x"00000" & exmem_pc_next;
                memwb_rd_addr    <= exmem_rd_addr;
                memwb_op_class   <= exmem_op_class;
                memwb_regwrite   <= exmem_regwrite;
            end if;
        end if;
    end process;

    --==================================================================
    -- WB STAGE
    --   Load -> output BRAM DMEM letto LIVE (valido in WB);
    --   Jump -> pc_next (return address); default -> alu_result.
    --==================================================================
    wb_data <= mem_out_mem      when memwb_op_class(2) = '1'   -- Load
          else memwb_pc_next_32 when memwb_op_class(4) = '1'   -- Jump
          else memwb_alu_result;                                -- ALU

    --==================================================================
    -- DEBUG OUTPUT (simulazione)
    --==================================================================
    dbg_pc         <= pc_if;
    dbg_instr      <= id_instr;
    dbg_state      <= "00";
    dbg_alu_result <= alu_result_ex;
    dbg_mem_out    <= mem_out_mem;
    dbg_rd_value   <= wb_data;

end Behavioral;
