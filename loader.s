; =====================================================================
;  DEPTHS OF DOOM - cartridge loader (fixed bank 15, $A000-$BFFF)
;
;  1. Checks for RAM under the OS ROM (any 64K XL/XE has it); without it,
;     says so and stops.
;  2. Switches the OS ROM off for good: its character set is copied into
;     the RAM under it, and the game's code for that RAM (banks 10-11:
;     interrupt handlers, fast drawing code, tables) is copied in.
;  3. Copies the game image from banks 0-1 into RAM $4000-$7FFF and jumps
;     to it.  The game then switches the cartridge off, so $8000-$BFFF
;     becomes RAM too.  Banks 2-14 hold content the game pages in later.
; =====================================================================
CARTCTL = $D500         ; write = select 8K bank at $8000-$9FFF; bit 7 = off
DMACTL  = $D400
SDMCTL  = $022F
NMIEN   = $D40E
PORTB   = $D301
SAVMSC  = $58
COLOR1  = $02C5
COLOR2  = $02C6
IMGBANKS = 2            ; game image size in 8K banks
IMGBASE  = $40          ; RAM page it is copied to
OSRBANK  = 10           ; the code for the RAM under the OS
STAGE    = $20          ; (a page range free at boot)

.segment "ZEROPAGE"
src:    .res 2
dst:    .res 2
bank:   .res 1
cnt:    .res 1
tmp:    .res 1

.segment "CODE"
init:   rts

run:    sei
        lda #0                  ; no interrupts and no screen while the OS
        sta NMIEN               ;   goes and its display memory ($7C00+)
        sta SDMCTL              ;   gets overwritten
        sta DMACTL
        ; ---- 1. RAM under the OS ROM?
        lda PORTB
        and #$FE
        sta PORTB
        ldx #7
@t:     lda tlo,x
        sta src
        lda thi,x
        sta src+1
        ldy #0
        lda #$5A
        sta (src),y
        cmp (src),y
        bne @bad
        lda #$A5
        sta (src),y
        cmp (src),y
        bne @bad
        dex
        bpl @t
        bmi @ok
@bad:   jmp nomem
@ok:
        ; ---- 2. the character set: ROM -> $2000 -> the RAM under it
        lda PORTB
        ora #$01
        sta PORTB
        lda #$E0
        ldx #STAGE
        jsr copy4
        lda PORTB
        and #$FE
        sta PORTB
        lda #STAGE
        ldx #$E0
        jsr copy4
        ;      the code and tables: banks 10-11, in three runs of pages
        lda #OSRBANK
        sta bank
        sta CARTCTL
        lda #$80
        sta src+1
        ldy #0
        sty src
        sty dst
        ldx #0
@run:   lda rdst,x
        sta dst+1
        lda rlen,x
        sta cnt
@pg:    lda (src),y
        sta (dst),y
        iny
        bne @pg
        inc dst+1
        inc src+1
        lda src+1
        cmp #$A0                ; the end of the bank's window: the next bank
        bne @sb
        inc bank
        lda bank
        sta CARTCTL
        lda #$80
        sta src+1
@sb:    dec cnt
        bne @pg
        inx
        cpx #3
        bne @run
        ; ---- 3. the game image
        lda #IMGBASE
        sta dst+1
        lda #0
        sta dst
        sta bank
@bank:  lda bank
        sta CARTCTL
        lda #$80
        sta src+1
        lda #0
        sta src
        ldx #$20                ; 32 pages = 8K
        ldy #0
@copy:  lda (src),y
        sta (dst),y
        iny
        bne @copy
        inc src+1
        inc dst+1
        dex
        bne @copy
        inc bank
        lda bank
        cmp #IMGBANKS
        bne @bank
        jmp IMGBASE*256+$3FFD   ; image entry (last 3 bytes): jmp start

; copy4: 4 pages from page A to page X
copy4:  sta src+1
        stx dst+1
        ldy #0
        sty src
        sty dst
        ldx #4
@c:     lda (src),y
        sta (dst),y
        iny
        bne @c
        inc src+1
        inc dst+1
        dex
        bne @c
        rts

; nomem: no RAM under the OS ROM: the ROM back on, and a message
nomem:  lda PORTB
        ora #$01
        sta PORTB
        lda #$22
        sta SDMCTL
        lda #$40
        sta NMIEN
        cli
        lda #$42                ; red screen, white text
        sta COLOR2
        lda #$0E
        sta COLOR1
        lda SAVMSC
        sta dst
        lda SAVMSC+1
        sta dst+1
        ldy #0
@m:     lda nomsg,y
        cmp #$FF
        beq @h
        sta (dst),y
        iny
        bne @m
@h:     jmp @h

; the RAM tested under the OS ROM
tlo:    .byte <$C000, <$CFFF, <$D800, <$DFFF, <$E000, <$EFFF, <$F800, <$FFF0
thi:    .byte >$C000, >$CFFF, >$D800, >$DFFF, >$E000, >$EFFF, >$F800, >$FFF0
; the three runs: $C000-$CFFF, $D800-$DFFF, $E400-$FFFF
rdst:   .byte $C0, $D8, $E4
rlen:   .byte 16, 8, 28

.macro scr str
        .repeat .strlen(str), i
        .byte .strat(str, i) - 32
        .endrepeat
.endmacro
nomsg:  scr "                                        "
        scr "  DEPTHS OF DOOM NEEDS AN ATARI XL/XE   "
        scr "  WITH 64K: RAM UNDER THE OS ROM.       "
        scr "                                        "
        scr "  THIS MACHINE DOESN'T HAVE IT.         "
        .byte $FF

.segment "CARTHDR"
        .word run               ; $BFFA run address
        .byte 0                 ; $BFFC cartridge present
        .byte $04               ; $BFFD: run cart, no disk boot
        .word init              ; $BFFE init address
