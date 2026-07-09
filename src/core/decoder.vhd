----------------------------------------------------------------------------------
-- Module Name: decoder - Behavioral
-- Description: Decoder per il subset RV32I del prof (16 istruzioni).
--   Ingresso : instr (32 bit) — istruzione appena letta dalla IMEM.
--   Uscite (tutte combinatorie):
--     op_class   [4:0] one-hot OSLBJ  (O=ALU op, S=Store, L=Load, B=Branch, J=Jump)
--     alu_opcode [2:0] per la mia ALU (3-bit, 6 op)
--     cond_opcode[2:0] per il comparator (3-bit, 4 op)
--     a_sel      sceglie input A dell'ALU: 0=curr_pc, 1=rs1_value
--     b_sel      sceglie input B dell'ALU: 0=rs2_value, 1=immediate
--     imm_type   [2:0] sceglie il formato di estrazione nell'immediate_gen
--                       000=I, 001=S, 010=B, 100=J
--
--   Istruzioni supportate:
--     R-type ALU : ADD, SUB, XOR, OR, AND
--     I-type ALU : ADDI, XORI, ORI, ANDI
--     I-type Load: LW
--     S-type     : SW
--     B-type     : BEQ, BNE, BLT, BGE
--     J-type     : JAL
--   Tutto il resto → NOP (op_class=00000, niente azione).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity decoder is
    port (
        instr       : in  std_logic_vector(31 downto 0);
        op_class    : out std_logic_vector(4 downto 0);  -- OSLBJ (one-hot)
        alu_opcode  : out std_logic_vector(2 downto 0);
        cond_opcode : out std_logic_vector(2 downto 0);
        a_sel       : out std_logic;
        b_sel       : out std_logic;
        imm_type    : out std_logic_vector(2 downto 0);
        is_lui      : out std_logic   -- '1' solo per LUI (EX forza alu_a=0)
    );
end decoder;

architecture Behavioral of decoder is
    -- Estrazione dei campi (alias sui bit dell'istruzione)
    signal opcode : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);

    -- Costanti per le 5 categorie one-hot del op_class
    -- bit:    4=J  3=B  2=L  1=S  0=O
    constant OPC_O  : std_logic_vector(4 downto 0) := "00001";  -- ALU op
    constant OPC_S  : std_logic_vector(4 downto 0) := "00010";  -- Store
    constant OPC_L  : std_logic_vector(4 downto 0) := "00100";  -- Load
    constant OPC_B  : std_logic_vector(4 downto 0) := "01000";  -- Branch
    constant OPC_J  : std_logic_vector(4 downto 0) := "10000";  -- Jump
    constant OPC_NOP: std_logic_vector(4 downto 0) := "00000";  -- nessuna azione

    -- Costanti per gli opcode RV32I del subset
    constant OPCODE_R_ALU  : std_logic_vector(6 downto 0) := "0110011";
    constant OPCODE_I_ALU  : std_logic_vector(6 downto 0) := "0010011";
    constant OPCODE_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OPCODE_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OPCODE_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OPCODE_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OPCODE_LUI    : std_logic_vector(6 downto 0) := "0110111";

    -- Costanti per alu_opcode
    constant ALU_ADD  : std_logic_vector(2 downto 0) := "000";
    constant ALU_ADDU : std_logic_vector(2 downto 0) := "001";
    constant ALU_SUB  : std_logic_vector(2 downto 0) := "010";
    constant ALU_XOR  : std_logic_vector(2 downto 0) := "100";
    constant ALU_OR   : std_logic_vector(2 downto 0) := "110";
    constant ALU_AND  : std_logic_vector(2 downto 0) := "111";

    -- Costanti per imm_type
    constant IMM_I : std_logic_vector(2 downto 0) := "000";
    constant IMM_S : std_logic_vector(2 downto 0) := "001";
    constant IMM_B : std_logic_vector(2 downto 0) := "010";
    constant IMM_J : std_logic_vector(2 downto 0) := "100";
    constant IMM_U : std_logic_vector(2 downto 0) := "011";  -- U-type (gia' gestito da immediate_gen)
begin
    -- Estrai i campi dall'istruzione (sono cablaggi puri, niente logica)
    opcode <= instr(6 downto 0);
    funct3 <= instr(14 downto 12);
    funct7 <= instr(31 downto 25);

    -- Logica combinatoria che produce tutti gli output a partire dai campi
    process(opcode, funct3, funct7)
    begin
        -- DEFAULT: NOP — tutti i segnali in uno stato "innocuo".
        -- Importante settare i default in cima al processo, altrimenti Vivado
        -- inferirebbe dei latch dove un ramo del case non assegna un signal.
        op_class    <= OPC_NOP;
        alu_opcode  <= ALU_ADD;
        cond_opcode <= "000";
        a_sel       <= '0';
        b_sel       <= '0';
        imm_type    <= IMM_I;
        is_lui      <= '0';

        case opcode is

            ----------------------------------------------------------------
            -- R-type ALU: ADD, SUB, XOR, OR, AND
            -- ALU prende rs1 e rs2 (a_sel=1, b_sel=0).
            -- alu_opcode dipende da funct3 (e funct7 per distinguere ADD/SUB).
            ----------------------------------------------------------------
            when OPCODE_R_ALU =>
                op_class <= OPC_O;
                a_sel    <= '1';   -- rs1
                b_sel    <= '0';   -- rs2

                case funct3 is
                    when "000" =>
                        -- funct7[5]=0 → ADD ; funct7[5]=1 → SUB
                        if funct7(5) = '0' then
                            alu_opcode <= ALU_ADD;
                        else
                            alu_opcode <= ALU_SUB;
                        end if;
                    when "100" => alu_opcode <= ALU_XOR;
                    when "110" => alu_opcode <= ALU_OR;
                    when "111" => alu_opcode <= ALU_AND;
                    when others => null;  -- istruzione fuori dal subset → NOP
                end case;

            ----------------------------------------------------------------
            -- I-type ALU: ADDI, XORI, ORI, ANDI
            -- ALU prende rs1 e immediate (a_sel=1, b_sel=1).
            -- imm_type = I.
            ----------------------------------------------------------------
            when OPCODE_I_ALU =>
                op_class <= OPC_O;
                a_sel    <= '1';   -- rs1
                b_sel    <= '1';   -- immediate
                imm_type <= IMM_I;

                case funct3 is
                    when "000" => alu_opcode <= ALU_ADD;   -- ADDI
                    when "100" => alu_opcode <= ALU_XOR;   -- XORI
                    when "110" => alu_opcode <= ALU_OR;    -- ORI
                    when "111" => alu_opcode <= ALU_AND;   -- ANDI
                    when others => null;  -- es. SLTI/SLLI/SRLI/SRAI fuori subset
                end case;

            ----------------------------------------------------------------
            -- I-type Load: LW
            -- ALU calcola l'indirizzo: rs1 + imm. imm_type = I.
            ----------------------------------------------------------------
            when OPCODE_LOAD =>
                if funct3 = "010" then  -- solo LW; LB/LH/LBU/LHU fuori subset
                    op_class   <= OPC_L;
                    alu_opcode <= ALU_ADD;
                    a_sel      <= '1';
                    b_sel      <= '1';
                    imm_type   <= IMM_I;
                end if;

            ----------------------------------------------------------------
            -- S-type Store: SW
            -- ALU calcola l'indirizzo: rs1 + imm. imm_type = S.
            -- (rs2_value verrà mandato come dato sulla DMEM, ma è pilotato
            --  fuori dal decoder, semplicemente cablato dal regfile.)
            ----------------------------------------------------------------
            when OPCODE_STORE =>
                if funct3 = "010" then  -- solo SW
                    op_class   <= OPC_S;
                    alu_opcode <= ALU_ADD;
                    a_sel      <= '1';
                    b_sel      <= '1';
                    imm_type   <= IMM_S;
                end if;

            ----------------------------------------------------------------
            -- B-type Branch: BEQ, BNE, BLT, BGE
            -- ALU calcola il branch target: curr_pc + imm (a_sel=0, b_sel=1).
            -- Il comparator decide il "taken/not taken" via cond_opcode.
            -- imm_type = B.
            ----------------------------------------------------------------
            when OPCODE_BRANCH =>
                op_class   <= OPC_B;
                alu_opcode <= ALU_ADD;
                a_sel      <= '0';   -- curr_pc
                b_sel      <= '1';   -- immediate
                imm_type   <= IMM_B;
                cond_opcode <= funct3;  -- 000=EQ, 001=NEQ, 100=LT, 101=GE
                -- (BLTU/BGEU con funct3 110/111 non sono nel subset; il
                --  comparator li tratterà come "false" → branch mai preso.)

            ----------------------------------------------------------------
            -- J-type Jump: JAL
            -- ALU calcola il jump target: curr_pc + imm (stesso pattern del branch).
            -- op_class = J → rd riceve next_pc (return address) e PC salta a alu_result.
            -- imm_type = J.
            ----------------------------------------------------------------
            when OPCODE_JAL =>
                op_class   <= OPC_J;
                alu_opcode <= ALU_ADD;
                a_sel      <= '0';   -- curr_pc
                b_sel      <= '1';   -- immediate
                imm_type   <= IMM_J;

            ----------------------------------------------------------------
            -- U-type LUI: rd = imm[31:12] << 12
            -- LUI non ha rs1: l'ALU calcola 0 + immediato_U leggendo x0 come
            -- operando A (rs1 forzato a x0 nel cpu_top_pipelined). imm_type = U.
            ----------------------------------------------------------------
            when OPCODE_LUI =>
                op_class   <= OPC_O;     -- scrive rd
                alu_opcode <= ALU_ADD;   -- rd = a + b  (a forzato a 0 in EX)
                a_sel      <= '1';
                b_sel      <= '1';       -- b = immediato
                imm_type   <= IMM_U;     -- immediato U: instr[31:12] << 12
                is_lui     <= '1';       -- EX forza alu_a = 0 -> rd = immediato

            ----------------------------------------------------------------
            -- Tutto il resto: opcode sconosciuto → NOP (default già settati).
            -- Include AUIPC, JALR, FENCE, SYSTEM, ecc.
            ----------------------------------------------------------------
            when others =>
                null;

        end case;
    end process;
end Behavioral;
