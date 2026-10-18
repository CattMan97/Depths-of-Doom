; =====================================================================
;  The tunnel between levels: walk through the exit and a zooming tunnel
;  of colour fills the view while the next level is built.
;
;  The picture (bank 8, made by endart.py) is rectangular rings in GTIA
;  mode 10, where each pixel names a colour register.  Six registers
;  (players 0-3, playfield 0 and 3) are rotated round the rings every few
;  frames by the VBI, so the rings rush toward you, and their hues drift.
;
;  tuncopy  $1D51 (below the cartridge window)
;  tunnel, tunend  $B980 (staged through $2000 by the menu)
;  tunvbi          $0100 (the stack never gets that deep)
;  (tunon, which the VBI tests, is in BSS2: zeroed at start-up)
; =====================================================================
TUNBANK = 8
TUNLEN  = 70                    ; frames of tunnel before the level is built
PRI_GT10 = $91                  ; GTIA mode 10, players over playfield

.segment "RT0"                  ; ($1D51)
; tuncopy: the tunnel picture from the cartridge into the buffer at page A
tuncopy:sta gptr+1
        ldy #0
        sty gptr
        sty sptr
        sty NMIEN               ; (no interrupts while the cartridge is in)
        lda #TUNBANK
        sta CARTCTL
        lda #$80
        sta sptr+1
        ldx #10                 ; 2560 bytes
@c:     lda (sptr),y
        sta (gptr),y
        iny
        bne @c
        inc sptr+1
        inc gptr+1
        dex
        bne @c
        lda #$80
        sta CARTCTL
        lda #$C0
        sta NMIEN
        rts

.segment "RT1"                  ; ($B980)
; tunnel: from do_win, on the way to the next level
tunnel: lda #1
        sta dead                ; (the clock holds)
        sta paused              ; (and the music stops: just the rush)
@w:     lda pending
        bne @w
        lda amap                ; (through the exit with the map up: map off)
        beq @nm
        jsr toggle_map
@nm:    lda #0                  ; no monsters in front of it
        sta sls
        sta sls+1
        ldx #0
        jsr drawslot
        ldx #1
        jsr drawslot
        ldx buf
        lda bufhi,x
        jsr tuncopy
        jsr dlprep              ; the spare list shows it
        lda #PRI_GT10
        sta dlipr+1             ; (the view's DLI: mode 10 instead of 9)
        lda #1
        sta tunon
        sta pending
@f:     lda pending
        bne @f
        ldx buf                 ; draw the next level somewhere else
        inx
        cpx #3
        bcc @b
        ldx #0
@b:     stx buf
        jsr setbuf
        ldx #TUNLEN
@t:     lda RTCLOK+2
@v:     cmp RTCLOK+2
        beq @v
        dex
        bne @t
        rts

; tunend: the level is built (lvlextra calls this): back to normal
tunend: lda #0
        sta tunon
        sta AUDC1
        sta dead
        sta paused
        sta thump
        lda #PRI_GT9
        sta dlipr+1
        jsr gamecolours
        jsr toggle_map          ; twice: gun back, every buffer redrawn
        jmp toggle_map

.segment "RT2"                  ; ($0100: the bottom of the stack page, never reached)
; tunvbi: once a frame from the VBI while the tunnel is up
tunvbi: inc tunt
        dec tunc                ; every 3 frames the rings move one on
        bpl @col
        lda #2
        sta tunc
        ldx tuns
        dex
        bpl @s
        ldx #5
@s:     stx tuns
@col:   lda tunt                ; and every 16 the hues turn
        and #15
        bne @hd
        lda tund
        clc
        adc #$10
        sta tund
@hd:    ldx #5
@r:     txa
        clc
        adc tuns
        tay
        lda tuncol,y
        clc
        adc tund
        ldy tunreg,x
        sta PCOLR0,y
        dex
        bpl @r
        lda #0                  ; nothing else on screen
        ldx #7
@h:     sta HPOSP0,x
        dex
        bpl @h
        lda tunt                ; a rushing noise, falling in pitch
        sta AUDF1
        lda #$84
        sta AUDC1
        lda #0                  ; everything else silent (the music is paused)
        sta AUDC2
        sta AUDC3
        sta AUDC4
        rts

tuncol:   .byte $46, $3A, $2C, $C8, $86, $68      ; red, orange, yellow, green,
        .byte $46, $3A, $2C, $C8, $86, $68      ;   blue, purple (twice: mod 6)
tunreg:   .byte 0, 1, 2, 3, 4, 7  ; ring colour n -> PCOLR0-3, COLOR0, COLOR3
tunt:   .byte 0
tunc:   .byte 0
tuns:   .byte 0
tund:   .byte 0
