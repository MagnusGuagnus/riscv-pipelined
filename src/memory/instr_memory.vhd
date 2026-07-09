----------------------------------------------------------------------------------
-- Module Name: instr_memory - Behavioral
-- Description: Instruction Memory.
--   - BRAM sincrona 1024 x 32 bit (4 kB).
--   - Indirizzo: 10 bit (word-level), corrisponde a pc[11:2].
--   - Lettura sincrona: l'istruzione esce 1 ciclo dopo che addr e' applicato.
--   - Read-only durante l'esecuzione (mai scritta dalla CPU).
--
--   Il programma da eseguire si sceglie a elaborazione tramite il generic
--   PROGRAM_SEL. I programmi sono precaricati come costanti (vedi tabella sotto)
--   e ogni istruzione e' annotata con il suo assembly.
--
--   PROGRAM_SEL | programma
--   ------------+--------------------------------------------------------------
--        0      | test di base del core (5 + 3 = 8, store/load)
--        1      | Hello su UART con tabella indirizzi in DMEM
--        2      | invio di un singolo carattere su UART (test minimale)
--        3      | come 2, con indirizzo periferica calcolato da registro
--        4      | test auto-verificante degli hazard (firma LED 0x4F)
--        5      | echo: switch -> LED (lettura GPIO_SW, scrittura GPIO_LED)
--        6      | test dell'istruzione LUI (LED = 0xAA)
--        7      | Hello su UART con indirizzi via LUI/ADDI (demo principale)
--        8      | running light sui LED (ALU + branch + delay loop)
--        9      | interattivo: switch -> LED, e switch15 invia 'A' su UART
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity instr_memory is
    generic (
        PROGRAM_SEL : integer := 0
    );
    port (
        clk         : in  std_logic;
        re          : in  std_logic := '1';
        addr        : in  std_logic_vector(9 downto 0);
        instruction : out std_logic_vector(31 downto 0)
    );
end instr_memory;

architecture Behavioral of instr_memory is
    type rom_t is array (0 to 1023) of std_logic_vector(31 downto 0);

    --------------------------------------------------------------------
    -- PROGRAM 0 — test di base del core
    --   0: addi x1, x0, 5      x1 = 5
    --   1: addi x2, x0, 3      x2 = 3
    --   2: add  x3, x1, x2     x3 = 8
    --   3: sw   x3, 0(x0)      DMEM[0] = 8
    --   4: lw   x4, 0(x0)      x4 = DMEM[0] = 8
    --   5: jal  x0, 0          halt (loop su se stessa)
    --------------------------------------------------------------------
    constant PROGRAM_A : rom_t := (
        0 => x"00500093",   -- addi x1, x0, 5
        1 => x"00300113",   -- addi x2, x0, 3
        2 => x"002081B3",   -- add  x3, x1, x2
        3 => x"00302023",   -- sw   x3, 0(x0)
        4 => x"00002203",   -- lw   x4, 0(x0)
        5 => x"0000006F",   -- jal  x0, 0
        others => x"00000013"  -- nop (addi x0, x0, 0)
    );

    --------------------------------------------------------------------
    -- PROGRAM 1 — Hello su UART con tabella indirizzi in DMEM.
    -- Versione che legge gli indirizzi delle periferiche da DMEM[0..2]
    -- (vedi data_memory.vhd per l'inizializzazione). Superata dal PROGRAM 7,
    -- che costruisce gli indirizzi con LUI/ADDI senza usare la DMEM.
    --
    --   istr 0  @ 0x00      istr 10 @ 0x28 (poll:)
    --   istr 8  @ 0x20 (send_loop:)        istr 18 @ 0x48 (halt)
    --------------------------------------------------------------------
    constant PROGRAM_B : rom_t := (
        0  => x"00002503",  -- lw   x10, 0(x0)        x10 = &UART_DATA
        1  => x"00402583",  -- lw   x11, 4(x0)        x11 = &UART_STATUS
        2  => x"00802603",  -- lw   x12, 8(x0)        x12 = &GPIO_LED
        3  => x"01000A13",  -- addi x20, x0, 16       base byte addr caratteri
        4  => x"00000B13",  -- addi x22, x0, 0        indice corrente
        5  => x"01400C13",  -- addi x24, x0, 20       limite (5 char * 4 byte)
        6  => x"00F00313",  -- addi x6, x0, 15        LED iniziali 0x0F
        7  => x"00662023",  -- sw   x6, 0(x12)        GPIO_LED <= 0x0F
        8  => x"016A0BB3",  -- add  x23, x20, x22     &chars[i]   (send_loop:)
        9  => x"000BA283",  -- lw   x5, 0(x23)        x5 = chars[i]
        10 => x"0005A383",  -- lw   x7, 0(x11)        UART_STATUS (poll:)
        11 => x"0013F393",  -- andi x7, x7, 1         isola bit 0 (ready)
        12 => x"FE038CE3",  -- beq  x7, x0, -8        se busy, ricicla (-> poll)
        13 => x"00552023",  -- sw   x5, 0(x10)        UART_DATA <= byte
        14 => x"004B0B13",  -- addi x22, x22, 4       i += 4
        15 => x"FF8B42E3",  -- blt  x22, x24, -28     se i < 20 continua (-> send_loop)
        16 => x"05500313",  -- addi x6, x0, 85        LED finali 0x55
        17 => x"00662023",  -- sw   x6, 0(x12)        GPIO_LED <= 0x55
        18 => x"0000006F",  -- jal  x0, 0             halt
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 2 — invio di un singolo carattere 'X' su UART.
    -- Test minimale del percorso CPU -> UART, con due marcatori sui LED
    -- (0xAA prima dell'invio, 0x11 dopo). Niente polling: dopo il reset la
    -- UART e' in IDLE/ready, quindi la sw parte di sicuro.
    --   0: lw   x12, 8(x0)   x12 = &GPIO_LED
    --   1: addi x6, x0, 170  x6  = 0xAA
    --   2: sw   x6, 0(x12)   LED <= 0xAA
    --   3: lw   x10, 0(x0)   x10 = &UART_DATA
    --   4: addi x5, x0, 88   x5  = 'X'
    --   5: sw   x5, 0(x10)   UART_DATA <= 'X'
    --   6: addi x6, x0, 17   x6  = 0x11
    --   7: sw   x6, 0(x12)   LED <= 0x11
    --   8: jal  x0, 0        halt
    --------------------------------------------------------------------
    constant PROGRAM_C : rom_t := (
        0 => x"00802603",   -- lw   x12, 8(x0)
        1 => x"0AA00313",   -- addi x6, x0, 170
        2 => x"00662023",   -- sw   x6, 0(x12)
        3 => x"00002503",   -- lw   x10, 0(x0)
        4 => x"05800293",   -- addi x5, x0, 88
        5 => x"00552023",   -- sw   x5, 0(x10)
        6 => x"01100313",   -- addi x6, x0, 17
        7 => x"00662023",   -- sw   x6, 0(x12)
        8 => x"0000006F",   -- jal  x0, 0
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 3 — come PROGRAM 2 ma l'indirizzo di UART_DATA e' calcolato da
    -- registro (addi x10, x12, -8) invece di leggerlo dalla DMEM.
    --   0: lw   x12, 8(x0)      x12 = &GPIO_LED = 0x00010008
    --   1: addi x6, x0, 170     x6  = 0xAA
    --   2: sw   x6, 0(x12)      LED <= 0xAA
    --   3: addi x10, x12, -8    x10 = 0x00010000 = &UART_DATA
    --   4: addi x5, x0, 88      x5  = 'X'
    --   5: sw   x5, 0(x10)      UART_DATA <= 'X'
    --   6: addi x6, x0, 17      x6  = 0x11
    --   7: sw   x6, 0(x12)      LED <= 0x11
    --   8: jal  x0, 0           halt
    --------------------------------------------------------------------
    constant PROGRAM_D : rom_t := (
        0 => x"00802603",   -- lw   x12, 8(x0)
        1 => x"0AA00313",   -- addi x6, x0, 170
        2 => x"00662023",   -- sw   x6, 0(x12)
        3 => x"FF860513",   -- addi x10, x12, -8
        4 => x"05800293",   -- addi x5, x0, 88
        5 => x"00552023",   -- sw   x5, 0(x10)
        6 => x"01100313",   -- addi x6, x0, 17
        7 => x"00662023",   -- sw   x6, 0(x12)
        8 => x"0000006F",   -- jal  x0, 0
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 4 — test AUTO-VERIFICANTE degli hazard della pipeline.
    -- Esercita forwarding, load-use stall, branch (preso e non preso) e jal con
    -- link (rd != x0), poi scrive una "firma" su GPIO_LED. La firma e' corretta
    -- solo se tutti gli hazard si comportano bene.
    --   Firma attesa: led_out = 0x004F  (= 79 = 30 + 5 + 44)
    --
    --   0  addi x1,x0,10     x1=10
    --   1  addi x2,x0,20     x2=20
    --   2  add  x3,x1,x2     x3=30        forwarding (x1 da MEM/WB, x2 da EX/MEM)
    --   3  sw   x3,12(x0)    DMEM[3]=30   forwarding di x3
    --   4  lw   x4,12(x0)    x4=30        (load)
    --   5  add  x6,x4,x0     x6=30        LOAD-USE -> stall di 1 ciclo
    --   6  beq  x4,x3,+8     30==30 PRESO -> salta istr 7
    --   7  addi x6,x0,255    deve essere SALTATA
    --   8  bne  x4,x3,+8     30!=30 falso -> NON preso
    --   9  addi x7,x0,5      x7=5 (deve ESEGUIRE)
    --  10  jal  x8,+8        x8=PC+4=44, salta istr 11 (link rd!=x0)
    --  11  addi x7,x0,238    deve essere SALTATA
    --  12  lw   x12,8(x0)    x12 = &GPIO_LED
    --  13  add  x5,x6,x7     x5 = 30+5 = 35
    --  14  add  x5,x5,x8     x5 = 35+44 = 79 = 0x4F
    --  15  sw   x5,0(x12)    GPIO_LED <= 0x4F   (firma)
    --  16  jal  x0,0         halt
    --------------------------------------------------------------------
    constant PROGRAM_E : rom_t := (
         0 => x"00A00093",   -- addi x1,x0,10
         1 => x"01400113",   -- addi x2,x0,20
         2 => x"002081B3",   -- add  x3,x1,x2     forwarding x1,x2
         3 => x"00302623",   -- sw   x3,12(x0)    forwarding x3
         4 => x"00C02203",   -- lw   x4,12(x0)    load
         5 => x"00020333",   -- add  x6,x4,x0     LOAD-USE -> stall
         6 => x"00320463",   -- beq  x4,x3,+8     branch PRESO
         7 => x"0FF00313",   -- addi x6,x0,255    (salta)
         8 => x"00321463",   -- bne  x4,x3,+8     branch NON preso
         9 => x"00500393",   -- addi x7,x0,5      esegue
        10 => x"0080046F",   -- jal  x8,+8        link rd=x8, salta istr 11
        11 => x"0EE00393",   -- addi x7,x0,238    (salta)
        12 => x"00802603",   -- lw   x12,8(x0)    &GPIO_LED
        13 => x"007302B3",   -- add  x5,x6,x7     35
        14 => x"008282B3",   -- add  x5,x5,x8     79 = 0x4F
        15 => x"00562023",   -- sw   x5,0(x12)    GPIO_LED <= firma
        16 => x"0000006F",   -- jal  x0,0         halt
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 5 — echo: switch -> LED (lettura periferica in pipeline).
    -- In loop legge GPIO_SW e lo riflette su GPIO_LED. Esercita una lettura
    -- memory-mapped di periferica (latenza uniforme in memory_map).
    --   0  lw   x12,8(x0)     x12 = &GPIO_LED  (una volta)
    --   1  addi x13,x12,4     x13 = &GPIO_SW   (una volta)
    --   2  lw   x14,0(x13)    x14 = switch     (loop:)  load-use -> stall
    --   3  sw   x14,0(x12)    GPIO_LED <= x14
    --   4  jal  x0,-8         torna a istr 2
    --------------------------------------------------------------------
    constant PROGRAM_F : rom_t := (
        0 => x"00802603",   -- lw   x12, 8(x0)
        1 => x"00460693",   -- addi x13, x12, 4
        2 => x"0006A703",   -- lw   x14, 0(x13)     loop:
        3 => x"00E62023",   -- sw   x14, 0(x12)
        4 => x"FF9FF06F",   -- jal  x0, -8
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 6 — test dell'istruzione LUI.
    -- Costruisce &GPIO_LED con lui/addi (niente DMEM) e accende LED = 0xAA.
    --   0  lui  x12, 0x10     x12 = 0x00010000
    --   1  addi x12, x12, 8   x12 = 0x00010008 = &GPIO_LED
    --   2  addi x6,  x0, 170  x6  = 0xAA
    --   3  sw   x6,  0(x12)   GPIO_LED <= 0xAA
    --   4  jal  x0,  0        halt
    --------------------------------------------------------------------
    constant PROGRAM_G : rom_t := (
        0 => x"00010637",   -- lui  x12, 0x10
        1 => x"00860613",   -- addi x12, x12, 8
        2 => x"0AA00313",   -- addi x6,  x0, 170
        3 => x"00662023",   -- sw   x6,  0(x12)
        4 => x"0000006F",   -- jal  x0,  0
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 7 — Hello su UART, indirizzi via LUI/ADDI (demo principale).
    -- Nessuna tabella in DMEM: gli indirizzi delle periferiche sono costruiti
    -- con LUI+ADDI. Per ogni carattere: polling di UART_STATUS bit0 (ready),
    -- poi sw su UART_DATA. LED 0x0F all'avvio, 0x55 a fine.
    --   x10=&UART_DATA  x11=&UART_STATUS  x12=&GPIO_LED  x5=char  x7=status
    --------------------------------------------------------------------
    constant PROGRAM_H : rom_t := (
        0  => x"00010537",   -- lui  x10, 0x10        x10 = &UART_DATA
        1  => x"00450593",   -- addi x11, x10, 4      x11 = &UART_STATUS
        2  => x"00850613",   -- addi x12, x10, 8      x12 = &GPIO_LED
        3  => x"00F00313",   -- addi x6,  x0, 15      x6  = 0x0F
        4  => x"00662023",   -- sw   x6,  0(x12)      LED = 0x0F
        5  => x"04800293",   -- addi x5, x0, 72       'H'
        6  => x"0005A383",   -- lw   x7, 0(x11)       poll
        7  => x"0013F393",   -- andi x7, x7, 1
        8  => x"FE038CE3",   -- beq  x7, x0, -8
        9  => x"00552023",   -- sw   x5, 0(x10)       invia
        10 => x"06500293",   -- addi x5, x0, 101      'e'
        11 => x"0005A383",   -- lw   x7, 0(x11)
        12 => x"0013F393",   -- andi x7, x7, 1
        13 => x"FE038CE3",   -- beq  x7, x0, -8
        14 => x"00552023",   -- sw   x5, 0(x10)
        15 => x"06C00293",   -- addi x5, x0, 108      'l'
        16 => x"0005A383",   -- lw   x7, 0(x11)
        17 => x"0013F393",   -- andi x7, x7, 1
        18 => x"FE038CE3",   -- beq  x7, x0, -8
        19 => x"00552023",   -- sw   x5, 0(x10)
        20 => x"06C00293",   -- addi x5, x0, 108      'l'
        21 => x"0005A383",   -- lw   x7, 0(x11)
        22 => x"0013F393",   -- andi x7, x7, 1
        23 => x"FE038CE3",   -- beq  x7, x0, -8
        24 => x"00552023",   -- sw   x5, 0(x10)
        25 => x"06F00293",   -- addi x5, x0, 111      'o'
        26 => x"0005A383",   -- lw   x7, 0(x11)
        27 => x"0013F393",   -- andi x7, x7, 1
        28 => x"FE038CE3",   -- beq  x7, x0, -8
        29 => x"00552023",   -- sw   x5, 0(x10)
        30 => x"05500313",   -- addi x6, x0, 85       x6 = 0x55
        31 => x"00662023",   -- sw   x6, 0(x12)       LED = 0x55
        32 => x"0000006F",   -- jal  x0, 0            halt
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 8 — running light sui LED.
    -- Una luce che scorre verso sinistra sui 16 LED, con loop di ritardo per
    -- renderla visibile. Mostra: ALU (add come shift x2), branch condizionali,
    -- GPIO write, loop di delay annidato.
    --   x12=&GPIO_LED  x5=pattern  x9=0x10000 (limite oltre il bit15)  x6=ritardo
    --   Il valore di delay (lui x6,0x40) e' tarabile per rallentare la luce.
    --   4  loop:  sw  x5,0(x12)
    --   6  delay: addi x6,x6,-1
    --   7         bne x6,x0,delay   -> idx6
    --   9         bge x5,x9,reset   -> idx11
    --   10        jal x0,loop       -> idx4
    --   11 reset: addi x5,x0,1
    --   12        jal x0,loop       -> idx4
    --------------------------------------------------------------------
    constant PROGRAM_I : rom_t := (
        0  => x"00010637",   -- lui  x12, 0x10       x12 = 0x00010000
        1  => x"00860613",   -- addi x12, x12, 8     x12 = &GPIO_LED
        2  => x"00100293",   -- addi x5,  x0, 1      pattern, parte dal bit0
        3  => x"000104B7",   -- lui  x9,  0x10       x9  = 0x10000 (limite)
        4  => x"00562023",   -- sw   x5,  0(x12)     loop:  LED <= pattern
        5  => x"00040337",   -- lui  x6,  0x40       x6  = ritardo
        6  => x"FFF30313",   -- addi x6,  x6, -1     delay: x6--
        7  => x"FE031EE3",   -- bne  x6,  x0, delay
        8  => x"005282B3",   -- add  x5,  x5, x5     x5 = x5*2 (shift left 1)
        9  => x"0092D463",   -- bge  x5,  x9, reset  se x5>=0x10000 -> reset
        10 => x"FE9FF06F",   -- jal  x0,  loop
        11 => x"00100293",   -- addi x5,  x0, 1      reset: torna al bit0
        12 => x"FE1FF06F",   -- jal  x0,  loop
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- PROGRAM 9 — interattivo switch + UART.
    -- Echo continuo degli switch sui LED; quando lo switch 15 e' alto, manda
    -- il carattere 'A' su UART (con polling di UART_STATUS). Usa entrambe le
    -- periferiche, il test di un bit con AND e i branch.
    --   x10=&UART_DATA  x11=&UART_STATUS  x12=&GPIO_LED  x13=&GPIO_SW
    --   4  loop: lw  x5,0(x13)
    --   8        beq x7,x0,loop  -> idx4
    --   9  wait: lw  x8,0(x11)
    --   11       beq x8,x0,wait  -> idx9
    --   14       jal x0,loop     -> idx4
    --------------------------------------------------------------------
    constant PROGRAM_J : rom_t := (
        0  => x"00010537",   -- lui  x10, 0x10       x10 = &UART_DATA
        1  => x"00450593",   -- addi x11, x10, 4     x11 = &UART_STATUS
        2  => x"00850613",   -- addi x12, x10, 8     x12 = &GPIO_LED
        3  => x"00C50693",   -- addi x13, x10, 12    x13 = &GPIO_SW
        4  => x"0006A283",   -- lw   x5,  0(x13)     loop: leggi switch
        5  => x"00562023",   -- sw   x5,  0(x12)     echo sui LED
        6  => x"00008337",   -- lui  x6,  0x8        x6  = 0x8000 = bit15
        7  => x"0062F3B3",   -- and  x7,  x5, x6     isola bit15
        8  => x"FE0388E3",   -- beq  x7,  x0, loop   bit15 spento -> solo echo
        9  => x"0005A403",   -- lw   x8,  0(x11)     wait: poll UART_STATUS
        10 => x"00147413",   -- andi x8,  x8, 1      isola bit0 (ready)
        11 => x"FE040CE3",   -- beq  x8,  x0, wait
        12 => x"04100493",   -- addi x9,  x0, 65     x9 = 'A'
        13 => x"00952023",   -- sw   x9,  0(x10)     invia 'A'
        14 => x"FD9FF06F",   -- jal  x0,  loop
        others => x"00000013"
    );

    --------------------------------------------------------------------
    -- Selezione del programma a partire dal generic PROGRAM_SEL.
    --------------------------------------------------------------------
    function select_program(sel : integer) return rom_t is
    begin
        if sel = 1 then
            return PROGRAM_B;
        elsif sel = 2 then
            return PROGRAM_C;
        elsif sel = 3 then
            return PROGRAM_D;
        elsif sel = 4 then
            return PROGRAM_E;
        elsif sel = 5 then
            return PROGRAM_F;
        elsif sel = 6 then
            return PROGRAM_G;
        elsif sel = 7 then
            return PROGRAM_H;
        elsif sel = 8 then
            return PROGRAM_I;
        elsif sel = 9 then
            return PROGRAM_J;
        else
            return PROGRAM_A;
        end if;
    end function;

    signal mem : rom_t := select_program(PROGRAM_SEL);
begin
    -- BRAM sincrona, lettura registrata al rising_edge.
    -- E' il pattern che Vivado riconosce come BRAM.
    process(clk)
    begin
        if rising_edge(clk) then
            if re = '1' then
                instruction <= mem(to_integer(unsigned(addr)));
            end if;
        end if;
    end process;
end Behavioral;
