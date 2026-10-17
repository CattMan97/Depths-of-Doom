; =====================================================================
;  MEMTEST: what RAM does this Atari XL/XE have, and is it all good?
;  An 8K cartridge (type 1).  Shows:
;    RAM UNDER OS ROM: YES / NO        (PORTB bit 0 switches the ROM out)
;    EXTENDED BANKS:   n               (130XE-style 16K banks at $4000)
;  then tests, pass after pass, forever:
;    MAIN RAM       every byte from $0000 to RAMTOP
;    ADDRESS LINES  A0-A7 in one page, and each page tagged with its own
;                   number (a bad high address line makes pages alias)
;    OS RAM         $C000-$CFFF and $D800-$FFFF with the ROM switched off
;    EXT RAM        every byte of every bank setting
;  Every byte is tested with 8 patterns ($00 $FF $55 $AA $33 $CC $0F $F0:
;  each bit stuck high or low, and each pair of bits shorted together)
;  and put back as it was, so the screen and the OS survive.
;  The first bad address in each test is shown and stays on screen.
;  Interrupts stay off throughout (nothing here needs the OS).
; =====================================================================
PORTB   = $D301
NMIEN   = $D40E
COLPF1  = $D017
COLPF2  = $D018
COLBK   = $D01A
DMACTL  = $D400
DLISTL  = $D402
SDMCTL  = $022F
SDLSTL  = $0230
SAVMSC  = $58           ; OS: screen memory address
RAMTOP  = $6A           ; OS: first page above RAM (in pages)
CRSINH  = $02F0

p       = $F0           ; (2) the byte under test: page in p+1, offset in Y
s       = $F2           ; (2) screen pointer
m       = $F4           ; (2) message pointer
pg      = $F6           ; (2) where the progress goes on screen
tg      = $F8           ; (2) page-tag pointer

V       = $0640         ; variables (the tags at $xx7F and the buffer avoid them)
oldpb   = V+0
good    = V+1
mainb   = V+2
nbank   = V+3
tmp     = V+4
tmp2    = V+5
ri      = V+6
curbk   = V+7
pass    = V+8
dh      = V+9
dt      = V+10
du      = V+11
rb      = V+12          ; (4) per test: 0 = fine so far, 1 = failed
rh      = V+16          ; (4) first bad address, high
rl      = V+20          ; (4)                    low
rk      = V+24          ; (4) bank of it (ext RAM)
hx      = V+28
bok     = V+29          ; (16) bank setting n is a distinct bank
NV      = 45
bufr    = $0580         ; (up to 160) bytes the page tags covered

R_MAIN  = 6             ; screen row of the first test
SCOL    = 20            ; and the column of the results

.macro PRT row, col, msg
        lda #<msg
        sta m
        lda #>msg
        sta m+1
        ldy #row
        ldx #col
        jsr prt
.endmacro

.segment "CODE"
start:  sei
        lda #0
        sta NMIEN
        sta COLPF2              ; black screen, white text
        sta COLBK
        lda #$0C
        sta COLPF1
        lda #1
        sta CRSINH
        lda SAVMSC              ; clear the screen
        sta s
        lda SAVMSC+1
        sta s+1
        ldx #4
        ldy #0
        tya
@cl:    sta (s),y
        iny
        bne @cl
        inc s+1
        dex
        bne @cl
        ldx #NV-1
@cv:    sta V,x
        dex
        bpl @cv
        lda #$FF
        sta curbk
        lda PORTB
        sta oldpb

        PRT 1, 2, m_ttl
        ; ---- RAM under the OS ROM: five addresses, two patterns each
        lda oldpb
        and #$FE                ; OS ROM off
        sta PORTB
        ldx #0
@t:     lda taddr,x
        sta p
        lda taddr+1,x
        sta p+1
        ldy #0
        lda (p),y
        sta tmp
        lda #$5A
        sta (p),y
        lda (p),y
        cmp #$5A
        bne @bad
        lda #$A5
        sta (p),y
        lda (p),y
        cmp #$A5
        bne @bad
        lda tmp
        sta (p),y
        inx
        inx
        cpx #10
        bne @t
        inc good                ; all five held
@bad:   lda oldpb               ; OS ROM back
        sta PORTB
        PRT 3, 2, m_os
        lda good
        bne @y
        PRT 3, SCOL, m_no
        jmp @bk
@y:     PRT 3, SCOL, m_yes

        ; ---- extended banks: tag each bank setting, then count the tags
        ;      that survive (settings that alias the same RAM overwrite each
        ;      other).  Bits 2, 3, 5, 6 of PORTB select the bank; bit 4 = 0
        ;      lets the CPU see it at $4000-$7FFF.
@bk:    lda $4000               ; the main RAM's byte, kept
        sta mainb
        ldx #15
@w:     jsr bankx
        txa
        ora #$80
        sta $4000
        dex
        bpl @w
        lda oldpb               ; main RAM: its own marker
        sta PORTB
        lda #$55
        sta $4000
        ldx #15
@r:     jsr bankx
        txa
        ora #$80
        cmp $4000
        bne @n
        inc nbank
        inc bok,x
@n:     dex
        bpl @r
        lda oldpb
        sta PORTB
        lda $4000               ; did the banks write through to main RAM?
        cmp #$55
        beq @ok
        lda #0                  ; (no banking at all)
        sta nbank
        ldx #15
@zb:    sta bok,x
        dex
        bpl @zb
@ok:    lda mainb
        sta $4000
        PRT 4, 2, m_bk
        PRT 4, SCOL, m_none
        lda nbank
        beq @tl
        ldy #0
        lda nbank
        jsr dec3

        ; ---- the test labels
@tl:    PRT R_MAIN, 2, m_main
        lda RAMTOP
        lsr
        lsr
        jsr dec3
        jsr putk
        PRT R_MAIN+1, 2, m_addr
        PRT R_MAIN+2, 2, m_osr
        PRT R_MAIN+3, 2, m_ext
        lda nbank
        asl
        asl
        asl
        asl                     ; (16 banks: 256, carry out)
        bcc @e1
        lda #2
        jsr putd
        lda #5
        jsr putd
        lda #6
        jsr putd
        jmp @e2
@e1:    jsr dec3
@e2:    jsr putk
        ldx #3
@sl:    stx ri                  ; "TESTING" (or "N/A") beside each
        lda #<m_wait
        sta m
        lda #>m_wait
        sta m+1
        jsr skip
        bcc @sw
        lda #<m_na
        sta m
        lda #>m_na
        sta m+1
@sw:    lda ri
        clc
        adc #R_MAIN
        tay
        ldx #SCOL
        jsr prt
        ldx ri
        dex
        bpl @sl
        PRT 11, 2, m_pass
        PRT 11, 12, m_tst
        lda s                   ; the progress: just after "TESTING $"
        clc
        adc #9
        sta pg
        lda s+1
        adc #0
        sta pg+1
        PRT 15, 2, m_note

; ===================================================================== passes
loop:   PRT 11, 7, m_blank      ; pass number
        ldy #0
        lda pass
        clc
        adc #1                  ; (counting from 1)
        jsr dec3
        ; ---- main RAM
        lda #0
        ldx RAMTOP
        jsr trange
        bcc @m
        ldx #0
        jsr rec
@m:     ldx #0
        jsr stat
        ; ---- address lines
        jsr addr
        ldx #1
        jsr stat
        ; ---- RAM under the OS
        lda good
        beq @noos
        lda oldpb
        and #$FE
        sta PORTB
        lda #$C0
        ldx #$D0
        jsr trange
        bcs @ob
        lda #$D8
        ldx #$00                ; (to the top: the page number wraps to 0)
        jsr trange
        bcc @oo
@ob:    ldx #2
        jsr rec
@oo:    lda oldpb
        sta PORTB
        ldx #2
        jsr stat
@noos:  ; ---- extended banks
        lda nbank
        beq @noext
        ldx #0
@b:     stx curbk
        lda bok,x               ; (only the settings that are banks of their own)
        beq @bo
        jsr bankx
        lda #$40
        ldx #$80
        jsr trange
        bcc @bo
        ldx #3
        jsr rec
@bo:    ldx curbk
        inx
        cpx #16
        bne @b
        lda oldpb
        sta PORTB
        lda #$FF
        sta curbk
        ldx #3
        jsr stat
@noext: ; ---- the verdict
        lda rb
        ora rb+1
        ora rb+2
        ora rb+3
        bne @fl
        PRT 13, 2, m_pass2
        jmp @nx
@fl:    PRT 13, 2, m_fail
@nx:    inc pass
        jmp loop

; ===================================================================== tests
; tpage: test the 256 bytes of page p+1 (p = 0), every byte put back.
;        Carry set on a failure, Y = its offset.  Uses only A, X, Y and p,
;        so it can test any RAM, its own variables included (just not p).
.macro tpat v
        lda #v
        sta (p),y
        cmp (p),y
        bne @bad
.endmacro
tpage:  ldy #0
@l:     lda p+1
        bne @go
        cpy #p                  ; (in page 0, skip the pointer itself)
        beq @nx
        cpy #p+1
        beq @nx
@go:    lda (p),y
        tax
        tpat $00
        tpat $FF
        tpat $55
        tpat $AA
        tpat $33
        tpat $CC
        tpat $0F
        tpat $F0
        txa
        sta (p),y
@nx:    iny
        bne @l
        clc
        rts
@bad:   txa
        sta (p),y
        sec
        rts

; trange: test pages A up to (not including) X.  Carry set on a failure,
;         with p+1 and Y the bad address.
trange: sta p+1
        stx tmp2
        lda #0
        sta p
@pg:    jsr prog
        lda p+1
        cmp SDLSTL+1            ; the display list's page: ANTIC off meanwhile
        bne @n                  ; (a pattern there could send it astray, and
        lda #0                  ;  with no VBI nothing would set it right)
        sta DMACTL
        jsr tpage
        php
        jsr antic
        plp
        jmp @c
@n:     jsr tpage
@c:     bcs @x
        inc p+1
        lda p+1
        cmp tmp2
        bne @pg
        clc
@x:     rts

; antic: display list and DMA back on
antic:  lda SDLSTL
        sta DLISTL
        lda SDLSTL+1
        sta DLISTL+1
        lda SDMCTL
        sta DMACTL
        rts

; addr: address lines.  A0-A7: in page 7, each address and the one a bit
;       away hold different values.  A8-A15: every page gets its own number
;       at offset $7F, then they are all read back (then put back).
.macro abit b
        ldx $0700
        ldy $0700+b
        lda #$55
        sta $0700
        lda #$AA
        sta $0700+b
        lda $0700
        cmp #$55
        php
        stx $0700
        sty $0700+b
        plp
        beq :+
        lda #7
        sta p+1
        ldy #b
        ldx #1
        jsr rec
:
.endmacro
addr:   lda #7
        sta p+1
        jsr prog
        .repeat 8, k
        abit (1 << k)
        .endrepeat
        lda #0                  ; (ANTIC off while the tags are about)
        sta DMACTL
        lda #$7F
        sta tg
        ldx #0
@s:     stx tg+1                ; tag them all
        ldy #0
        lda (tg),y
        sta bufr,x
        txa
        sta (tg),y
        inx
        cpx RAMTOP
        bne @s
        ldx #0
@v:     stx tg+1                ; read them all
        ldy #0
        txa
        cmp (tg),y
        beq @vo
        stx p+1
        stx tmp2
        ldy #$7F
        ldx #1
        jsr rec
        ldx tmp2
@vo:    inx
        cpx RAMTOP
        bne @v
        ldx #0
@rs:    stx tg+1                ; put them back
        ldy #0
        lda bufr,x
        sta (tg),y
        inx
        cpx RAMTOP
        bne @rs
        jmp antic

; rec: test X failed at p+1:Y (only the first failure is kept)
rec:    lda rb,x
        bne @x
        lda #1
        sta rb,x
        lda p+1
        sta rh,x
        tya
        sta rl,x
        lda curbk
        sta rk,x
@x:     rts

; skip: carry set if test X can't run here (no OS RAM / no banks)
skip:   cpx #2
        bcc @x                  ; (main, address lines: always)
        bne @e
        lda good
        bne @c
        sec
        rts
@e:     lda nbank
        bne @c
        sec
        rts
@c:     clc
@x:     rts

; bankx: PORTB for bank setting X (0-15): bits 2,3 = X bits 0,1;
;        bits 5,6 = X bits 2,3; bit 4 = 0 (CPU sees the bank); ROMs as they
;        were.  X is kept.
bankx:  txa
        and #3
        asl
        asl
        sta tmp
        txa
        and #12
        asl
        asl
        asl
        ora tmp
        sta tmp
        lda oldpb
        and #%10000011
        ora tmp
        sta PORTB
        rts

; ===================================================================== screen
; stat: show test X's result on its row
stat:   stx ri
        txa
        clc
        adc #R_MAIN
        tay
        lda rb,x
        bne @bad
        lda #<m_ok
        sta m
        lda #>m_ok
        sta m+1
        ldx #SCOL
        jmp prt
@bad:   lda #<m_bad
        sta m
        lda #>m_bad
        sta m+1
        ldx #SCOL
        jsr prt
        ldx ri
        lda rh,x
        jsr hex
        lda rl,x
        jsr hex
        cpx #3
        bne @x
        lda #0                  ; ext RAM: " B" and the bank
        sta (s),y
        iny
        lda #'B'-32
        sta (s),y
        iny
        lda rk,x
        jsr hex1
@x:     rts

; rowp: s = the start of screen row Y
rowp:   lda SAVMSC
        sta s
        lda SAVMSC+1
        sta s+1
@r:     dey
        bmi @x
        lda s
        clc
        adc #40
        sta s
        bcc @r
        inc s+1
        bne @r
@x:     rts

; prt: message m at row Y, column X.  Leaves s at the column, Y after it.
prt:    jsr rowp
        txa
        clc
        adc s
        sta s
        bcc @c
        inc s+1
@c:     ldy #0
@ch:    lda (m),y
        cmp #$FF
        beq @x
        sta (s),y
        iny
        bne @ch
@x:     rts

; hex: A as two hex digits at (s),Y.  X kept.
hex:    pha
        lsr
        lsr
        lsr
        lsr
        jsr hex1
        pla
        and #15
hex1:   stx hx
        tax
        lda hexs,x
        sta (s),y
        iny
        ldx hx
        rts

; dec3: A (0-255) in decimal at (s),Y, no leading zeros
dec3:   ldx #$FF
@h:     inx
        sec
        sbc #100
        bcs @h
        adc #100
        stx dh
        ldx #$FF
@t:     inx
        sec
        sbc #10
        bcs @t
        adc #10
        stx dt
        sta du
        lda dh
        beq @n1
        jsr putd
@n1:    lda dh
        ora dt
        beq @n2
        lda dt
        jsr putd
@n2:    lda du
putd:   ora #$10                ; one digit
        sta (s),y
        iny
        rts
putk:   lda #'K'-32
        sta (s),y
        iny
        lda #':'-32
        sta (s),y
        rts

; prog: the page under test (and the bank) on the pass line
prog:   lda pg
        sta s
        lda pg+1
        sta s+1
        ldy #0
        lda p+1
        jsr hex
        lda #$10                ; "00"
        sta (s),y
        iny
        sta (s),y
        iny
        lda #0
        sta (s),y
        iny
        sta (s),y
        iny
        sta (s),y
        lda curbk
        bmi @x
        dey                     ; " B" and the bank
        lda #'B'-32
        sta (s),y
        iny
        lda curbk
        jmp hex1
@x:     rts

taddr:  .word $C000, $CFFF, $D800, $E000, $FFF0
hexs:   .byte $10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$21,$22,$23,$24,$25,$26

.macro scr str
        .repeat .strlen(str), i
        .byte .strat(str, i) - 32
        .endrepeat
        .byte $FF
.endmacro
m_ttl:  scr "DEPTHS OF DOOM - MEMORY TEST"
m_os:   scr "RAM UNDER OS ROM:"
m_yes:  scr "YES"
m_no:   scr "NO"
m_bk:   scr "EXTENDED BANKS:"
m_none: scr "0"
m_main: scr "MAIN RAM "
m_addr: scr "ADDRESS LINES:"
m_osr:  scr "OS RAM 14K:"
m_ext:  scr "EXT RAM "
m_wait: scr "TESTING"
m_na:   scr "N/A"
m_ok:   scr "OK          "
m_bad:  scr "BAD $"
m_pass: scr "PASS"
m_blank:scr "   "
m_tst:  scr "TESTING $"
m_pass2:scr "ALL TESTS PASSED           "
m_fail: scr "ERRORS FOUND - SEE ABOVE   "
m_note: scr "(PHOTO THIS SCREEN FOR CLAUDE)"

init:   rts

.segment "VEC"
        .word start             ; $BFFA: run address
        .byte 0                 ; $BFFC: cartridge present
        .byte $04               ; $BFFD: run it, no disk boot
        .word init              ; $BFFE: init address
