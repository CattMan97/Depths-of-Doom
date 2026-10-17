; =====================================================================
;  Overlay 2: the ending.  Cartridge bank 5, copied to RAM $1000 when
;  level 15 is cleared; its pictures and walking frames stay in banks 6-7
;  and are read straight from the cartridge (interrupts held off).
;
;  The escapee walks down the last corridor toward a door full of
;  daylight, the light swallows everything, and out of the glare comes
;  a ruined city under a dusty sun.  THE END.
;
;  Screen: GTIA mode 9, 80 x 96 at $2000-$2EFF (the maze generator's and
;  buffer 1's space, free now); display list at $3000 (buffer 2's).
; =====================================================================
ESCR    = $2000
EDL     = $3000
FIGROW  = 16                    ; PM row of screen row 0 (2-line players)
WALK_HP = 120                   ; walking figure: players 0, 1 side by side
STAND_HP = 64                   ;   ... standing on the ledge, lower left
STAND_TOP = 96                  ; standing figure's feet on the bottom row
WINDV   = 2                     ; wind noise volume

.segment "OVL2"
ENDING: lda #0
        sta SDMCTL              ; dark while it is set up
        ldx #7
@snd:   sta AUDF1,x             ; silence
        dex
        bpl @snd
        ldx #7                  ; the gun, imps and muzzle flash away
@hp:    sta HPOSP0,x
        dex
        bpl @hp
        sta SIZEP0
        sta SIZEP1
        sta PCOLR0              ; the escapee is a black shape
        sta PCOLR1
        sta COLOR4              ; corridor: grey
        sta sndv
        sta wind
        jsr pmclr
        ldx #1
        jsr ewait
        ; ---- display list: 3 blank, then each of 96 rows shown twice
        lda #<EDL
        sta gptr
        lda #>EDL
        sta gptr+1
        lda #<ESCR
        sta sptr
        lda #>ESCR
        sta sptr+1
        ldy #0
        lda #$70
        jsr dlb
        jsr dlb
        jsr dlb
        ldx #96
@row:   jsr dll
        jsr dll
        clc
        lda sptr
        adc #40
        sta sptr
        bcc @r1
        inc sptr+1
@r1:    dex
        bne @row
        lda #$41
        jsr dlb
        lda #<EDL
        jsr dlb
        lda #>EDL
        jsr dlb
        lda #<EDL
        sta SDLSTL
        lda #>EDL
        sta SDLSTL+1
        lda #$41                ; GTIA mode 9 everywhere, players in front
        sta GPRIOR
        ; ---- the corridor
        ldx #pcor_BANK
        lda #<pcor
        ldy #>pcor
        jsr unpack
        lda #WALK_HP
        sta HPOSP0
        lda #WALK_HP+8
        sta HPOSP1
        lda #0
        sta efr
        jsr showfr
        lda #$2E
        sta SDMCTL
        ldx #50
        jsr ewait
@walk:  jsr showfr              ; ---- walking to the door
        ldx efr
        lda fstep,x             ; a footstep?
        beq @nfs
        lda #6
        sta sndv
@nfs:   ldx #WALK_STEP
        jsr ewait
        inc efr
        lda efr
        cmp #WALK_FRAMES
        bne @walk
        ldx #40
        jsr ewait
        ; ---- into the light: everything goes white
        ldx #1
@wh:    stx elum
        stx COLOR4
        txa
        lsr
        sta AUDC2               ; (a rising rush of noise)
        lda #$40
        sta AUDF2
        ldx #3
        jsr ewait
        ldx elum
        inx
        cpx #16
        bne @wh
        lda #$0C                ; pure white: no playfield, only the border colour
        sta SDMCTL
        jsr pmclr               ; (gone into the glare)
        ldx #30
        jsr ewait
        lda #$2F                ; the outside is orange
        sta COLOR4
        ldx #2
        jsr ewait
        ldx #pwas_BANK          ; (unseen: the glare covers it)
        lda #<pwas
        ldy #>pwas
        jsr unpack
        lda #STAND_HP           ; the escapee, standing in the doorway's glare
        sta HPOSP0
        lda #STAND_HP+8
        sta HPOSP1
        jsr showst
        ldx #40
        jsr ewait
        lda #$2E                ; the picture again, under the glare
        sta SDMCTL
        lda #1                  ; the wind
        sta wind
        ; ---- eyes adjust: the glare fades and the world appears
        ldx #15
@rv:    stx elum
        txa
        ora #$20
        sta COLOR4
        txa
        lsr
        cmp #WINDV
        bcs @rw
        lda #WINDV
@rw:    ora #$80
        sta AUDC2
        ldx #6
        jsr ewait
        ldx elum
        dex
        bpl @rv
        ldx #150
        jsr ewait
        ; ---- THE END fades in
        lda #1
        sta elum
@te:    jsr drawend
        ldx #6
        jsr ewait
        inc elum
        lda elum
        cmp #16
        bne @te
        ; ---- until a key, the button or START (after letting go)
        ldx #60
        jsr ewait
        lda #$FF
        sta CH
        lda #0
        sta srreq
@rel:   jsr ewait1
        lda STRIG0
        beq @rel
@key:   jsr ewait1
        lda STRIG0
        beq @out
        lda srreq
        bne @out
        lda CH
        cmp #$FF
        beq @key
@out:   lda #0                  ; ---- back to the menu
        sta SDMCTL
        sta COLOR4
        ldx #7
@q:     sta AUDF1,x
        dex
        bpl @q
        jsr pmclr
        lda #0
        sta HPOSP0
        sta HPOSP1
        sta paused
        sta srreq
        lda #$FF
        sta CH
        lda #PRI_STD
        sta GPRIOR
        jmp gomenu

dll:    lda #$4F                ; one mode F line with its address
        jsr dlb
        lda sptr
        jsr dlb
        lda sptr+1
dlb:    sta (gptr),y
        iny
        bne @x
        inc gptr+1
@x:     rts

; ewait: X frames (ewait1: one), keeping the sound going
ewait1: ldx #1
ewait:  stx ewc
@f:     lda RTCLOK+2
@v:     cmp RTCLOK+2
        beq @v
        lda sndv                ; footsteps: a soft thud of noise
        beq @nf
        dec sndv
        lda sndv
        sta AUDC1
        lda #$B0
        sta AUDF1
@nf:    lda wind                ; the wind wanders in pitch
        beq @nw
        lda RTCLOK+2
        and #7
        bne @nw
        lda RANDOM
        and #$3F
        ora #$80
        sta AUDF2
@nw:    dec ewc
        bne @f
        rts

; pmclr: players 0 and 1 empty
pmclr:  lda #0
        ldx #127
@c:     sta P0MEM,x
        sta P1MEM,x
        dex
        bpl @c
        rts

; showfr: walking frame efr into players 0 and 1 (from the cartridge)
showfr: jsr pmclr
        lda efr
        asl
        tax
        lda fwoff,x
        sta sptr
        lda fwoff+1,x
        sta sptr+1
        lda #fwalk_BANK
        jmp showpm
showst: jsr pmclr
        lda #<fstand
        sta sptr
        lda #>fstand
        sta sptr+1
        lda #STAND_TOP-STAND_ROWS
        ldy #0
        sty NMIEN               ; (the stand frame's top is placed here)
        ldy #fstand_BANK
        sty CARTCTL
        ldy #0
        clc
        adc #FIGROW
        tax
        jmp spm2
showpm: ldy #0
        sty NMIEN
        sta CARTCTL
        lda (sptr),y            ; top row
        clc
        adc #FIGROW
        tax
spm2:   iny
        lda (sptr),y            ; rows
        sta ewc
        iny
@r:     lda (sptr),y
        sta P0MEM,x
        iny
        lda (sptr),y
        sta P1MEM,x
        iny
        inx
        dec ewc
        bne @r
        lda #$80
        sta CARTCTL
        lda #$C0
        sta NMIEN
        rts

; unpack: picture at A/Y in bank X onto the screen (see endart.py)
unpack: sta sptr
        sty sptr+1
        lda #0
        sta NMIEN
        stx CARTCTL
        lda #<ESCR
        sta gptr
        lda #>ESCR
        sta gptr+1
@op:    sec                     ; the row above
        lda gptr
        sbc #40
        sta cpptr
        lda gptr+1
        sbc #0
        sta cpptr+1
        ldy #0
        lda (sptr),y
        inc sptr
        bne @s1
        inc sptr+1
@s1:    cmp #$80
        bcs @nl
        tax                     ; literal: n+1 bytes
        inx
@lit:   lda (sptr),y
        sta (gptr),y
        iny
        dex
        bne @lit
        tya
        clc
        adc sptr
        sta sptr
        bcc @adv
        inc sptr+1
        bcs @adv
@nl:    cmp #$C0
        bcs @up
        and #$3F                ; run: n+2 of the next byte
        tax
        inx
        inx
        lda (sptr),y
        inc sptr
        bne @run
        inc sptr+1
@run:   sta (gptr),y
        iny
        dex
        bne @run
        beq @adv
@up:    and #$3F                ; copy n+1 bytes from the row above
        tax
        inx
@u:     lda (cpptr),y
        sta (gptr),y
        iny
        dex
        bne @u
@adv:   tya
        clc
        adc gptr
        sta gptr
        bcc @e
        inc gptr+1
@e:     lda gptr+1
        cmp #>(ESCR+96*40)
        bcc @op
        lda #$80
        sta CARTCTL
        lda #$C0
        sta NMIEN
        rts

; drawend: THE END at brightness elum (only its own pixels change)
drawend:lda elum
        asl
        asl
        asl
        asl
        ora elum
        sta evl
        lda #<(ESCR+END_Y*40+END_X/2)
        sta gptr
        lda #>(ESCR+END_Y*40+END_X/2)
        sta gptr+1
        lda #<endmask
        sta sptr
        lda #>endmask
        sta sptr+1
        lda #END_ROWS
        sta ewr
@row:   ldy #END_W-1
@b:     lda (sptr),y
        sta emk
        eor #$FF
        and (gptr),y
        sta etmp
        lda evl
        and emk
        ora etmp
        sta (gptr),y
        dey
        bpl @b
        clc
        lda gptr
        adc #40
        sta gptr
        bcc @n
        inc gptr+1
@n:     clc
        lda sptr
        adc #END_W
        sta sptr
        bcc @m
        inc sptr+1
@m:     dec ewr
        bne @row
        rts

efr:    .byte 0
elum:   .byte 0
ewc:    .byte 0
ewr:    .byte 0
evl:     .byte 0
emk:     .byte 0
etmp:     .byte 0
sndv:   .byte 0
wind:   .byte 0

.include "enddata.s"
