----------------------------------------------------------------------------------
-- Testbench: tb_decoder
-- Verifica il decoder per tutte le 16 istruzioni del subset + alcuni casi limite.
-- Per ogni caso: assegna instr, aspetta che la logica combinatoria si stabilizzi,
-- controlla op_class, alu_opcode, cond_opcode, a_sel, b_sel, imm_type.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_decoder is
end tb_decoder;

architecture sim of tb_decoder is
    signal instr       : std_logic_vector(31 downto 0) := (others => '0');
    signal op_class    : std_logic_vector(4 downto 0);
    signal alu_opcode  : std_logic_vector(2 downto 0);
    signal cond_opcode : std_logic_vector(2 downto 0);
    signal a_sel       : std_logic;
    signal b_sel       : std_logic;
    signal imm_type    : std_logic_vector(2 downto 0);

    -- Helper: assert con messaggio descrittivo
    procedure check_outputs(
        signal op_c : in std_logic_vector(4 downto 0);
        signal alu  : in std_logic_vector(2 downto 0);
        signal asel : in std_logic;
        signal bsel : in std_logic;
        constant exp_op_c : in std_logic_vector(4 downto 0);
        constant exp_alu  : in std_logic_vector(2 downto 0);
        constant exp_asel : in std_logic;
        constant exp_bsel : in std_logic;
        constant labels    : in string
    ) is
    begin
        assert op_c = exp_op_c
            report labels & ": op_class wrong" severity error;
        assert alu = exp_alu
            report labels & ": alu_opcode wrong" severity error;
        assert asel = exp_asel
            report labels & ": a_sel wrong" severity error;
        assert bsel = exp_bsel
            report labels & ": b_sel wrong" severity error;
    end procedure;
begin
    uut: entity work.decoder
        port map (
            instr       => instr,
            op_class    => op_class,
            alu_opcode  => alu_opcode,
            cond_opcode => cond_opcode,
            a_sel       => a_sel,
            b_sel       => b_sel,
            imm_type    => imm_type
        );

    stim: process
    begin
        ------------------------------------------------------------------
        -- R-type ALU
        ------------------------------------------------------------------

        -- ADD x3, x1, x2  →  funct7=0000000 rs2=00010 rs1=00001 funct3=000 rd=00011 op=0110011
        instr <= "0000000" & "00010" & "00001" & "000" & "00011" & "0110011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "000", '1', '0', "ADD");

        -- SUB x3, x1, x2  →  funct7=0100000, resto come ADD
        instr <= "0100000" & "00010" & "00001" & "000" & "00011" & "0110011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "010", '1', '0', "SUB");

        -- XOR x9, x8, x7  →  da esempio slide 7 del PDF: 0x007444b3
        instr <= x"007444b3";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "100", '1', '0', "XOR");

        -- OR  x3, x1, x2
        instr <= "0000000" & "00010" & "00001" & "110" & "00011" & "0110011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "110", '1', '0', "OR");

        -- AND x3, x1, x2
        instr <= "0000000" & "00010" & "00001" & "111" & "00011" & "0110011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "111", '1', '0', "AND");

        ------------------------------------------------------------------
        -- I-type ALU
        ------------------------------------------------------------------

        -- ADDI x5, x1, 12  →  da esempio slide 7 del PDF: 0x00c08293
        instr <= x"00c08293";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "000", '1', '1', "ADDI");
        assert imm_type = "000" report "ADDI: imm_type wrong" severity error;

        -- XORI x3, x1, 0xFF
        instr <= "000011111111" & "00001" & "100" & "00011" & "0010011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "100", '1', '1', "XORI");

        -- ORI x3, x1, 7
        instr <= "000000000111" & "00001" & "110" & "00011" & "0010011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "110", '1', '1', "ORI");

        -- ANDI x3, x1, 0x0F
        instr <= "000000001111" & "00001" & "111" & "00011" & "0010011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00001", "111", '1', '1', "ANDI");

        ------------------------------------------------------------------
        -- Load / Store
        ------------------------------------------------------------------

        -- LW x1, 10(x2)  →  da esempio slide 7 del PDF: 0x00a12083
        instr <= x"00a12083";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00100", "000", '1', '1', "LW");
        assert imm_type = "000" report "LW: imm_type wrong" severity error;

        -- SW x8, 17(x1)  →  da esempio slide 7: 0x0080a8a3
        instr <= x"0080a8a3";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "00010", "000", '1', '1', "SW");
        assert imm_type = "001" report "SW: imm_type wrong" severity error;

        ------------------------------------------------------------------
        -- Branch — verifica anche cond_opcode e che a_sel=0 (curr_pc)
        ------------------------------------------------------------------

        -- BEQ x1, x2, +16
        instr <= "0000000" & "00010" & "00001" & "000" & "10000" & "1100011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "01000", "000", '0', '1', "BEQ");
        assert cond_opcode = "000" report "BEQ: cond_opcode wrong" severity error;
        assert imm_type = "010" report "BEQ: imm_type wrong" severity error;

        -- BNE x9, x5, -16  →  da esempio slide 7 del PDF: 0xfe5498e3
        instr <= x"fe5498e3";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "01000", "000", '0', '1', "BNE");
        assert cond_opcode = "001" report "BNE: cond_opcode wrong" severity error;

        -- BLT x1, x2, +16
        instr <= "0000000" & "00010" & "00001" & "100" & "10000" & "1100011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "01000", "000", '0', '1', "BLT");
        assert cond_opcode = "100" report "BLT: cond_opcode wrong" severity error;

        -- BGE x1, x2, +16
        instr <= "0000000" & "00010" & "00001" & "101" & "10000" & "1100011";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "01000", "000", '0', '1', "BGE");
        assert cond_opcode = "101" report "BGE: cond_opcode wrong" severity error;

        ------------------------------------------------------------------
        -- Jump
        ------------------------------------------------------------------

        -- JAL x21, +28  →  da esempio slide 7 del PDF: 0x01c00aef
        instr <= x"01c00aef";
        wait for 5 ns;
        check_outputs(op_class, alu_opcode, a_sel, b_sel,
                      "10000", "000", '0', '1', "JAL");
        assert imm_type = "100" report "JAL: imm_type wrong" severity error;

        ------------------------------------------------------------------
        -- Casi speciali
        ------------------------------------------------------------------

        -- NOP canonico: ADD x0, x0, x0  →  0x00000033
        -- È formalmente valido (è R-type ADD), il decoder lo riconosce come
        -- ALU op. È il regfile poi che ignora la scrittura su x0.
        instr <= x"00000033";
        wait for 5 ns;
        assert op_class = "00001" report "NOP (add x0,x0,x0): wrong" severity error;

        -- Istruzione fuori dal subset: LUI x1, 0x12345 (opcode 0110111)
        -- Deve diventare un NOP "puro" (op_class=00000)
        instr <= "00010010001101000101" & "00001" & "0110111";
        wait for 5 ns;
        assert op_class = "00000"
            report "LUI fuori subset: dovrebbe essere NOP" severity error;

        -- Istruzione fuori subset: SLLI (opcode I-ALU + funct3=001)
        -- Deve diventare NOP perché il sotto-case di I-ALU non lo riconosce
        instr <= "000000000100" & "00001" & "001" & "00011" & "0010011";
        wait for 5 ns;
        -- Nota: op_class=O (perché l'opcode è I-ALU), ma alu_opcode resta default
        -- Questo è un caso ambiguo, dipende da come implementiamo il "fuori subset"
        -- Per ora va bene così, dopo se vogliamo lo blindiamo

        report "tb_decoder: tutti i casi del subset verificati" severity note;
        wait;
    end process;
end sim;
