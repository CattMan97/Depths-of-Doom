; =====================================================================
;  Overlay: main menu, demo bot and game-over banner.
;  Lives in cartridge bank 4 and is copied to RAM $1000-$1AFF (frame
;  buffer 0, free while the menu is up) each time the menu opens.
;    OVL     $1000  the menu (code, display list, screen lines)
;    OVLBAN  ->$BB90 the game-over banner, copied to spare RAM by the menu
;    OVLBOT  $1A00  the demo bot (above buffer 0, so it survives the demo)
; =====================================================================
.import mtitle, mopt1, mopt2, mhint, mhs, mhelp1, mhelp2, mcols
.import banbits, msg_demo, imsg1, imsg2, imsg3, imsg4, msg_god, msg_lsel
.importzp LSCOL
.import __OVLC1_LOAD__, __OVLC1_RUN__, __OVLC1_SIZE__
.import __OVLD1_LOAD__, __OVLD1_RUN__, __OVLD1_SIZE__
.import __OVLD2_LOAD__, __OVLD2_RUN__, __OVLD2_SIZE__
.import __OVLC2_LOAD__, __OVLC2_RUN__, __OVLC2_SIZE__
.import __OVLC3_LOAD__, __OVLC3_RUN__, __OVLC3_SIZE__
.import __OVLC4_LOAD__, __OVLC4_RUN__, __OVLC4_SIZE__
.import __RC_LOAD__, __RC_RUN__, __RC_SIZE__
.import __RT0_LOAD__, __RT0_RUN__, __RT0_SIZE__
.import __RT1_LOAD__, __RT1_RUN__, __RT1_SIZE__
.import __RT2_LOAD__, __RT2_RUN__, __RT2_SIZE__
.import __RT3_LOAD__, __RT3_RUN__, __RT3_SIZE__
.import __CWA_LOAD__, __CWA_RUN__, __CWA_SIZE__
.import __CWB_LOAD__, __CWB_RUN__, __CWB_SIZE__
.import __CWC_LOAD__, __CWC_RUN__, __CWC_SIZE__
.import __PKF_LOAD__, __PKF_RUN__, __PKF_SIZE__
.import __PKM1_LOAD__, __PKM1_RUN__, __PKM1_SIZE__
.import __PKM2_LOAD__, __PKM2_RUN__, __PKM2_SIZE__
.import __MSND_LOAD__, __MSND_RUN__, __MSND_SIZE__
.import __ZRF_LOAD__, __ZRF_RUN__, __ZRF_SIZE__
.import __ZMU_LOAD__, __ZMU_RUN__, __ZMU_SIZE__
.import __RA1_LOAD__, __RA1_RUN__, __RA1_SIZE__
.import __RA2_LOAD__, __RA2_RUN__, __RA2_SIZE__
.import __RA3_LOAD__, __RA3_RUN__, __RA3_SIZE__
.importzp SEEDCOL, HSCOL
.import __OVLBAN_LOAD__, __OVLBAN_RUN__, __OVLBAN_SIZE__
.import __OVLB2_LOAD__, __OVLB2_RUN__, __OVLB2_SIZE__
.import __OVLB3_LOAD__, __OVLB3_RUN__, __OVLB3_SIZE__
.import __OVLB4_LOAD__, __OVLB4_RUN__, __OVLB4_SIZE__

MENU_IDLE = 7           ; menu -> demo after this many x 256 frames (~30 s)
DEMOLEN   = 4           ; demo length, x 256 game ticks (~50 s)


.segment "OVL"
; MENU: returns A = 0 to play (seedd / seedset chosen), 1 for the demo
MENU:        lda #0                  ; level dressing: straight from the cartridge
        sta NMIEN               ;   (bank 4 past the overlay) to the start-up
        lda #OVL_BANK           ;   code's old place in image A
        sta CARTCTL
        ldx #0
@xs:    lda xcptab,x
        sta sptr
        lda xcptab+1,x
        sta sptr+1
        lda xcptab+2,x
        sta gptr
        lda xcptab+3,x
        sta gptr+1
        ldy xcptab+4,x
@xc:    dey
        lda (sptr),y
        sta (gptr),y
        tya
        bne @xc
        txa
        clc
        adc #5
        tax
        cpx #xcptabend-xcptab
        bne @xs
        lda #$80
        sta CARTCTL
        lda #$C0
        sta NMIEN
        ldx #0                  ; the parts that stay resident (demo bot,
@cs:    lda cptab,x             ;   banner) -> spare corners of RAM
        sta sptr
        lda cptab+1,x
        sta sptr+1
        lda cptab+2,x
        sta gptr
        lda cptab+3,x
        sta gptr+1
        ldy cptab+4,x
@cp:    dey
        lda (sptr),y
        sta (gptr),y
        tya
        bne @cp
        txa
        clc
        adc #5
        tax
        cpx #cptabend-cptab
        bne @cs
        ldx #0                  ; the title theme
        jsr mload
        lda #<mdl
        sta SDLSTL
        lda #>mdl
        sta SDLSTL+1
        lda #$2E                ; text, plus players for the blood
        sta SDMCTL
        jsr dripinit
        ldx #4
@c:     lda mcols,x
        sta COLOR0,x
        dex
        bpl @c
        ldx #5                  ; the high score, from the top bar
@hs:    lda a:HUD3+HIGHPOS,x
        sta mhs+HSCOL,x
        dex
        bpl @hs
        lda #0
        sta mcur
        sta idle
        sta idle+1
        sta srreq
        lda #1
        sta mfire               ; (fire must be let go first)
        lda STICK0
        sta mstk
        lda #$FF
        sta CH
        jsr mdraw
@loop:  lda RTCLOK+2            ; once per frame
@v:     cmp RTCLOK+2
        beq @v
        jsr drips
        inc idle
        bne @i
        inc idle+1
@i:     lda idle+1
        cmp #MENU_IDLE
        bcc @in
        jsr mexit               ; nobody there: run the demo
        lda #1
        rts
@in:    lda STICK0              ; up / down picks the option
        cmp mstk
        beq @nj
        sta mstk
        cmp #14
        bne @dn
        lda #0
        beq @set
@dn:    cmp #13
        bne @act
        lda #1
@set:   sta mcur
        jmp @act
@nj:    lda STRIG0              ; fire (a fresh press) plays
        bne @rel
        lda mfire
        bne @st
        jmp @sel
@rel:   lda #0
        sta mfire
@st:    lda srreq               ; START plays too
        beq @ky
        lda #0
        sta srreq
        jmp @sel
@ky:    lda CH
        cmp #$FF
        beq @loop
        ldx #$FF
        stx CH
        and #$3F
        cmp #$0C                ; RETURN plays
        beq @sel
        ldx #9
@f:     cmp keytab,x
        beq @dig
        dex
        bpl @f
        bmi @act
@dig:   ldy #0                  ; a digit: shift it into the seed
@sh:    lda seedd+1,y
        sta seedd,y
        iny
        cpy #3
        bne @sh
        stx seedd+3
        lda #1
        sta seedset
        sta mcur
@act:   lda #0                  ; any input: stay on the menu
        sta idle
        sta idle+1
        jsr mdraw
        jmp @loop
@sel:   jsr mexit
        lda mcur
        bne @own
        jsr randseed
        lda #0
        rts
@own:   lda #1
        sta seedset
        lda #0
        rts

; ---------------------------------------------------------------------
; The blood: players 0-3 sit exactly over the four letters of DOOM (the
; title is ANTIC mode 7: 1 colour clock x 2 lines per pixel, the same as a
; single-width player at 2-line resolution).  Each drip hangs from the
; bottom of a letter, slowly grows, swells, and lets go of a drop that
; falls down the screen.
NDRIP   = 7
DTOP    = 27                    ; PM row under the letters' last pixel row
dripinit:
        ldx #0                  ; clear all four players
        txa
@c:     sta P0MEM,x
        sta P0MEM+$100,x
        inx
        bne @c
        ldx #3
@p:     lda dhpos,x
        sta HPOSP0,x
        lda #0
        sta SIZEP0,x
        sta HPOSM0,x
        lda #$44                ; the same red as the letters (COLPF3)
        sta PCOLR0,x
        dex
        bpl @p
        ldx #NDRIP-1
@d:     lda dmin,x              ; staggered start: some drips half grown
        clc
        adc dstart,x
        sta dlen,x
        lda #0
        sta dlenf,x
        sta dy,x
        dex
        bpl @d
        rts

mexit:  ldx #0                  ; players off and cleared for the game
        txa
@c:     sta P0MEM,x
        sta P0MEM+$100,x
        inx
        bne @c
        ldx #3
@p:     sta HPOSP0,x
        dex
        bpl @p
        lda #1                  ; the gun and hand sizes again
        sta SIZEP0
        lda #3
        sta SIZEP1
        rts

drips:  ldx #127-DTOP           ; wipe the area under the letters
        lda #0
@w:     sta P0MEM+DTOP,x
        sta P1MEM+DTOP,x
        sta P2MEM+DTOP,x
        sta P3MEM+DTOP,x
        dex
        bpl @w
        ldx #NDRIP-1
@d:     stx dix
        lda dpl,x               ; this drip's player
        sta gptr
        lda dph,x
        sta gptr+1
        clc                     ; grow
        lda dlenf,x
        adc drate,x
        sta dlenf,x
        bcc @g
        inc dlen,x
@g:     lda dlen,x
        cmp dmax,x
        bcc @hang
        adc #DTOP-1             ; full: the drop lets go (C was set)
        sta dy,x
        lda #0
        sta dv,x
        sta dyf,x
        lda dmin,x
        sta dlen,x
@hang:  lda dmask,x             ; the hanging stream
        sta tmp
        lda dlen,x
        sta tmp2
        ldy #DTOP
@s:     dec tmp2
        beq @tip
        lda (gptr),y
        ora tmp
        sta (gptr),y
        iny
        bne @s
@tip:   lda (gptr),y            ; a fatter tip
        ora dbulb,x
        sta (gptr),y
        lda dy,x                ; a falling drop?
        beq @nx
        lda dv,x                ; gravity
        cmp #248
        bcs @fv
        adc #7
        sta dv,x
@fv:    clc
        adc dyf,x
        sta dyf,x
        lda dy,x
        adc #0
        cmp #125
        bcc @fy
        lda #0                  ; off the bottom
@fy:    sta dy,x
        beq @nx
        tay
        lda (gptr),y
        ora dmask,x
        sta (gptr),y
        iny
        lda (gptr),y
        ora dbulb,x
        sta (gptr),y
        iny
        lda (gptr),y
        ora dbulb,x
        sta (gptr),y
@nx:    ldx dix
        dex
        bmi @r
        jmp @d
@r:     rts

dhpos:  .byte 152, 160, 168, 176        ; D O O M (title chars 13-16)
;              D    D    O    O    O    M    M
dpl:    .byte <P0MEM, <P0MEM, <P1MEM, <P2MEM, <P2MEM, <P3MEM, <P3MEM
dph:    .byte >P0MEM, >P0MEM, >P1MEM, >P2MEM, >P2MEM, >P3MEM, >P3MEM
dmask:  .byte $40, $10, $10, $08, $20, $40, $02
dbulb:  .byte $60, $18, $18, $0C, $30, $60, $03
dmin:   .byte 2,   1,   2,   1,   1,   3,   2      ; stub left after a drop
dmax:   .byte 12,  4,   9,   14,  3,   10,  7      ; length when it lets go
drate:  .byte 23,  9,   31,  19,  5,   27,  15     ; growth, 1/256 row per frame
dstart: .byte 6,   1,   0,   9,   0,   3,   4
dix:    .byte 0
dlen:   .res NDRIP
dlenf:  .res NDRIP
dy:     .res NDRIP
dyf:    .res NDRIP
dv:     .res NDRIP

; mdraw: the seed digits, and the chosen option shown as an inverse bar
mdraw:  ldx #3
@d:     lda seedd,x
        ora #$10
        sta mopt2+SEEDCOL,x
        dex
        bpl @d
        ldx #39
@l:     lda mopt1,x
        and #$7F
        ldy mcur
        bne @1
        ora #$80
@1:     sta mopt1,x
        lda mopt2,x
        and #$7F
        ldy mcur
        beq @2
        ora #$80
@2:     sta mopt2,x
        dex
        bpl @l
        rts

cptab:  .word __OVLBAN_LOAD__, __OVLBAN_RUN__
        .byte <__OVLBAN_SIZE__
        .word __OVLB2_LOAD__, __OVLB2_RUN__
        .byte <__OVLB2_SIZE__
        .word __OVLB3_LOAD__, __OVLB3_RUN__
        .byte <__OVLB3_SIZE__
        .word __OVLB4_LOAD__, __OVLB4_RUN__
        .byte <__OVLB4_SIZE__
        .word __OVLC1_LOAD__, __OVLC1_RUN__
        .byte <__OVLC1_SIZE__
        .word __OVLD1_LOAD__, __OVLD1_RUN__
        .byte <__OVLD1_SIZE__
        .word __OVLD2_LOAD__, __OVLD2_RUN__
        .byte <__OVLD2_SIZE__
        .word __OVLC2_LOAD__, __OVLC2_RUN__
        .byte <__OVLC2_SIZE__
        .word __OVLC3_LOAD__, __OVLC3_RUN__
        .byte <__OVLC3_SIZE__
        .word __OVLC4_LOAD__, __OVLC4_RUN__
        .byte <__OVLC4_SIZE__
        .word $2000, __RT1_RUN__        ; (the tunnel, from its staging)
        .byte <__RT1_SIZE__
cptabend:
xcptab: .word __RA1_LOAD__, __RA1_RUN__
        .byte <__RA1_SIZE__
        .word __RA2_LOAD__, __RA2_RUN__
        .byte <__RA2_SIZE__
        .word __RA3_LOAD__, __RA3_RUN__
        .byte <__RA3_SIZE__
        .word __RC_LOAD__, __RC_RUN__
        .byte <__RC_SIZE__
        .word __RT0_LOAD__, __RT0_RUN__
        .byte <__RT0_SIZE__
        .word __RT2_LOAD__, __RT2_RUN__
        .byte <__RT2_SIZE__
        .word __RT3_LOAD__, __RT3_RUN__
        .byte <__RT3_SIZE__
        .word __CWA_LOAD__, __CWA_RUN__
        .byte <__CWA_SIZE__
        .word __CWB_LOAD__, __CWB_RUN__
        .byte <__CWB_SIZE__
        .word __CWC_LOAD__, __CWC_RUN__
        .byte <__CWC_SIZE__
        .word __PKF_LOAD__, __PKF_RUN__
        .byte <__PKF_SIZE__
        .word __PKM1_LOAD__, __PKM1_RUN__
        .byte <__PKM1_SIZE__
        .word __PKM2_LOAD__, __PKM2_RUN__
        .byte <__PKM2_SIZE__
        .word __MSND_LOAD__, __MSND_RUN__
        .byte <__MSND_SIZE__
        .word __ZRF_LOAD__, __ZRF_RUN__
        .byte <__ZRF_SIZE__
        .word __ZMU_LOAD__, __ZMU_RUN__
        .byte <__ZMU_SIZE__
        .word __RT1_LOAD__, $2000       ; (under the cartridge: staged)
        .byte <__RT1_SIZE__
xcptabend:
keytab: .byte $32, $1F, $1E, $1A, $18, $1D, $1B, $33, $35, $30   ; keys 0-9
mcur:   .byte 0                 ; 0 random seed, 1 your own seed
idle:   .word 0
mfire:  .byte 0
mstk:   .byte 0

; the menu's display list (no DLIs)
mdl:    .byte $70, $70, $70, $70    ; (all of it ends by line 200: TV safe)
        .byte $47
        .word mtitle
        .byte $70, $70, $70             ; (room for the drips)
        .byte $42
        .word mopt1
        .byte $70
        .byte $42
        .word mopt2
        .byte $70
        .byte $42
        .word mhint
        .byte $70, $70, $70
        .byte $42
        .word mhs
        .byte $70, $70, $70
        .byte $42
        .word mhelp1
        .byte $70
        .byte $42
        .word mhelp2
        .byte $41
        .word mdl

; =====================================================================
; INTRO: the wake-up.  Called once, from the main loop, when the first
; frame of a new run is ready (in buffer 1: this code lives under buffer
; 0).  The view opens and closes like eyelids -- rows of the display list
; outside the opening point at a page of zeros -- then the story lines.
INTRO:  lda #0
        sta intro
        tax                     ; the zero page for closed eyes
@z:     sta PMG,x               ;   ($1C00-$1D27; test keys live above it)
        cpx #$28
        bcs @z1
        sta PMG+$100,x
@z1:    inx
        bne @z
        sta HPOSP0              ; no gun yet
        sta HPOSP1
        sta ih4
        sta istep
        lda #1
        sta dead                ; (clock stopped)
        sta ifire               ; (fire must be let go before it skips)
        lda nextdl              ; the list about to go on screen
        sta idl
        lda nextdlh
        sta idlh
        ldx buf
        lda bufhi,x
        sta ibuf
        jsr lid                 ; shut
        lda #<msg_none
        ldy #>msg_none
        jsr putmsg
        lda #1
        sta pending
@fl:    lda pending
        bne @fl
@next:  ldx istep               ; ---- the next step of the script
        lda iscr,x
        cmp #$FF
        bne @go
        jmp @done
@go:    sta itgt
        lda iscr+1,x
        sta ispd
        lda iscr+2,x
        sta icnt
        lda iscr+3,x
        sta iflash
        beq @frame
        and #$7F
        tax
        lda imlo-1,x
        ldy imhi-1,x
        jsr putmsg
@frame: lda RTCLOK+2            ; ---- once per frame
@v:     cmp RTCLOK+2
        beq @v
        lda STRIG0              ; fire skips it
        bne @r
        lda ifire
        bne @k
        jmp @done
@r:     lda #0
        sta ifire
@k:     lda ih4                 ; the lids move toward the target
        cmp itgt
        beq @hold
        bcs @cl
        adc ispd
        cmp itgt
        bcc @set
        lda itgt
        bcs @set
@cl:    sbc ispd
        bcc @tg
        cmp itgt
        bcs @set
@tg:    lda itgt
@set:   sta ih4
        jsr lid
@hold:  lda iflash              ; the last line flashes
        bpl @nf
        lda RTCLOK+2
        and #16
        asl
        asl
        asl
        sta tmp
        ldx #39
@iv:    lda HUD+40,x
        beq @sp
        and #$7F
        ora tmp
        sta HUD+40,x
@sp:    dex
        bpl @iv
@nf:    dec icnt
        beq @st
        jmp @frame
@st:    lda istep
        clc
        adc #4
        sta istep
        jmp @next
@done:  lda #128                ; eyes open, the game starts
        sta ih4
        jsr lid
@up:    lda STRIG0              ; (a skip's press is not a shot)
        beq @up
        lda #0
        sta trigl
        sta dead
        lda #$FF
        sta lsec
        sta CH
        lda #120                ; the gun
        sta HPOSP0
        lda #112
        sta HPOSP1
        jmp showlevel

; lid: rows of the shown list within ih4/4 of the middle show the
;      picture, the rest a page of zeros
lid:    lda ih4
        lsr
        lsr
        sta tmp2
        lda idl
        sta gptr
        lda idlh
        sta gptr+1
        ldx #0
@h:     ldy #GDL_ROWS
@r:     txa                     ; distance from the middle (0 at rows 31, 32)
        sec
        sbc #32
        bcs @p
        eor #$FF
@p:     cmp tmp2
        lda #>PMG
        bcs @s
        lda rowhi,x
        ora ibuf
@s:     sta (gptr),y
        iny
        iny
        iny
        sta (gptr),y
        iny
        iny
        iny
        inx
        txa
        and #31
        bne @r
        clc
        lda gptr
        adc #192
        sta gptr
        bcc @c
        inc gptr+1
@c:     cpx #64
        bne @h
        rts

; the script: lids' target and speed (quarter rows), frames, line to show
; (+$80: flashing)
iscr:   .byte 0, 0, 50, 0               ; dark
        .byte 20, 1, 40, 0              ; a slit of light ...
        .byte 0, 8, 14, 0               ; ... gone
        .byte 0, 0, 24, 0
        .byte 52, 2, 56, 1              ; WHERE... AM I?
        .byte 6, 12, 12, 0              ; blink
        .byte 128, 4, 70, 0             ; open
        .byte 128, 0, 110, 2            ; NO MEMORY ...
        .byte 128, 0, 90, 3             ; ONLY ONE THING ...
        .byte 128, 0, 140, $84          ; YOU MUST ESCAPE.
        .byte $FF
imlo:   .byte <imsg1, <imsg2, <imsg3, <imsg4
imhi:   .byte >imsg1, >imsg2, >imsg3, >imsg4
msg_none: .byte 0, $FF
idl:    .byte 0
idlh:   .byte 0
ibuf:   .byte 0
ih4:    .byte 0
itgt:   .byte 0
ispd:   .byte 0
icnt:   .byte 0
iflash: .byte 0
istep:  .byte 0
ifire:  .byte 0

; =====================================================================
; Maze braiding: runs while each level is built, from the maze generator's
; stack page (only its first half is ever used: 121 cells at most).
.segment "OVLD1"                ; ($2A80)
; braid: every dead end more than SHORT cells from a junction is opened
;        into the next cell (straight on if it can), so long blind
;        corridors become cut-throughs.  Small stubs off a junction stay.
braid:  lda #1
        sta ly
@by:    lda #1
        sta lx
@bx:    lda lx
        sta cx
        lda ly
        sta cy
        jsr xyidx
        lda curl
        sta svl
        lda curh
        sta svh
        jsr nopen
        dex
        beq @de
        jmp @nx                 ; not a dead end
@de:    lda nbdir
        sta bod
        sta bdr
        lda #SHORT+1
        sta blen
@w:     dec blen                ; walk out along the corridor
        bne @wk
        jmp @open               ; long: open the dead end
@wk:
        lda bdr
        ora #4
        tay
        jsr step
        lda nl
        sta curl
        lda nh
        sta curh
        jsr idxxy
        jsr nopen
        cpx #2
        beq @cor
        jmp @nx                 ; a junction (or the far end) soon: keep it
@cor:
        lda nbdir               ; on along the corridor, not back
        eor bdr
        cmp #1
        bne @f
        lda nbdir+1
        bcs @s                  ; (C set: equal)
@f:     lda nbdir
@s:     sta bdr
        jmp @w
.segment "OVLD2"                ; ($2B80)
@open:  lda svl
        sta curl
        lda svh
        sta curh
        jsr idxxy
        lda bod                 ; straight on, or any other wall
        eor #1
        sta dir
        jsr dirok
        bcs @do
        lda #3
        sta dir
@try:   jsr dirok
        bcc @tn
        ldy dir
        jsr step
        jsr ldmap
        bne @op
@tn:    dec dir
        bpl @try
        bmi @nx
@do:    ldy dir
        jsr step
@op:    lda #0
        jsr stmap
@nx:    lda lx
        clc
        adc #2
        sta lx
        cmp maxc
        bcs @ny
        jmp @bx
@ny:    lda ly
        adc #1                  ; (C set: +2)
        sta ly
        cmp maxc
        bcs @bd
        jmp @by
@bd:    rts
.segment "OVLC1"                ; ($1D28)
; nopen: X = how many of the cell's four walls are open, nbdir = which
nopen:  lda #0
        sta nnb
        lda #3
        sta dir
@l:     jsr dirok
        bcc @n
        ldy dir
        jsr step
        jsr ldmap
        bne @n
        lda dir
        jsr addnb
@n:     dec dir
        bpl @l
        ldx nnb
        rts


; =====================================================================
; Test keys, resident in spare corners of RAM (copied there by the menu).
; CHEAT: A = key code from the main loop; G and L are handled here.
;        Returns A that is not a weapon key.
.segment "CODE2"                ; (image B)
CHEAT:  cmp #$3D                ; G: god mode on / off
        bne @l
        lda god
        eor #1
        sta god
        beq @off
        lda #<msg_god
        ldy #>msg_god
        jsr showmsg
        lda #0
        rts
@off:   jmp showlevel
@l:     cmp #$00                ; L: level select
        beq LSEL
        rts
; LSEL: pick a level with the stick (up / down), fire to go there,
;       any key to stay.  Everything holds while it's up.
LSEL:   lda #1
        sta paused
        lda level
        sta lsv
lshow:  lda #<msg_lsel
        ldy #>msg_lsel
        jsr putmsg
        lda lsv
        jsr div10
        sta a:HUD+40+LSCOL+1
        stx a:HUD+40+LSCOL
@rel:   lda STICK0              ; (one step per push)
        cmp #15
        bne @rel
        lda STRIG0
        beq @rel
@w:     lda CH
        cmp #$FF
        beq @k
        jmp lcan
@k:     lda STRIG0
        bne @s
        jmp lgo
@s:     lda STICK0
        cmp #14
        bne @d
        jmp lup
@d:     cmp #13
        bne @w
        dec lsv                 ; down
        bne lshow
        lda #LASTLEVEL
        jmp lst
.segment "OVLC2"                ; ($1BC9)
lup:    lda lsv                 ; up
        cmp #LASTLEVEL
        bcc @u
        lda #0
@u:     clc
        adc #1
lst:    sta lsv
        jmp lshow
lcan:   lda #$FF
        sta CH
        lda #0
        sta paused
        jmp showlevel
lgo:    lda STRIG0              ; (let go: no shot)
        beq lgo
        lda #0
        sta paused
        sta trigl
        lda lsv
        sta level
        jmp lgo2
.segment "OVLC3"                ; ($0BDE)
lgo2:   jsr new_level
        lda #0
        rts
lsv:    .byte 1

; =====================================================================
.segment "OVLBAN"
; BANNER: "GAME OVER" in big letters across the middle of all three frame
;         buffers (whichever is on screen shows it): a black box, rows 24-39,
;         bytes 6-33, and the 53x7 bitmap at pixel 14, rows 28-34
BXT     = 24 * VROWS / 32           ; (rows in the shown frame: 2 * VROWS)
BXH     = 16 * VROWS / 32
BMT     = BXT + (BXH - 7) / 2
BANNER: ldx #2
@b:     lda bufhi,x
        clc
        adc #>(BXT*40)
        sta gptr+1
        lda #<(BXT*40)
        sta gptr
        jsr bclear
        lda bufhi,x
        clc
        adc #>(BMT*40)
        sta gptr+1
        lda #<(BMT*40)
        sta gptr
        lda #0
        sta bnk
        lda #7
        sta bnr
@row:   lda #7
        sta bnb
        ldy #7
@byte:  stx bnx
        ldx bnk
        lda banbits,x
        sta bnv
        inc bnk
        ldx #4
@pair:  lda #0                  ; two bits -> two pixels (nibbles)
        asl bnv
        bcc @p1
        ora #$F0
@p1:    asl bnv
        bcc @p2
        ora #$0F
@p2:    ora (gptr),y
        sta (gptr),y
        iny
        dex
        bne @pair
        ldx bnx
        dec bnb
        bne @byte
        jsr bnext
        dec bnr
        bne @row
        dex
        bpl @b
        rts

.segment "OVLB3"                ; ($09A0: the banner's bitmap follows)
bnext:  clc
        lda gptr
        adc #40
        sta gptr
        bcc @x
        inc gptr+1
@x:     rts
bclear: lda #BXH                ; the black box: BXH rows, bytes 6-33
        sta bnr
@r:     ldy #33
        lda #0
@c:     sta (gptr),y
        dey
        cpy #6
        bcs @c
        jsr bnext
        dec bnr
        bne @r
        rts
bnr:    .byte 0
bnb:    .byte 0
bnk:    .byte 0
bnv:    .byte 0
bnx:    .byte 0

; =====================================================================
.segment "OVLBOT"
; the demo: a bot holds the joystick.  It follows the right-hand wall from
; tile centre to tile centre, and fires at monsters in front of it.
BOT:    jmp bot                 ; $1A00: A = this frame's stick
BOTINIT:lda px+1                ; $1A03: start of the demo
        sta btx
        sta bcx
        lda py+1
        sta bty
        sta bcy
        lda pa+1
        sta bdir
        lda #0
        sta dtime
        sta dtime+1
        sta bstuck
        rts

bot:    lda STRIG0              ; anybody there?  Back to the menu.
        beq @q
        lda STICK0
        cmp #15
        bne @q
        lda CH
        cmp #$FF
        bne @q
        lda srreq
        ora amreq
        beq @t
@q:     jmp gomenu
@t:     inc dtime               ; the demo runs a while, then the menu again
        bne @t1
        inc dtime+1
        lda dtime+1
        cmp #DEMOLEN
        bcs @q
@t1:    lda px+1
        ldy py+1
        cmp btx
        bne @nt
        cpy bty
        bne @nt
        lda px                  ; on the target tile: near its centre?
        sec
        sbc #$50
        cmp #$60
        bcs @steer
        lda py
        sec
        sbc #$50
        cmp #$60
        bcs @steer
        jsr chz
        jmp @steer
@nt:    cmp bcx                 ; still on the tile it set off from?
        bne @re
        cpy bcy
        beq @steer
@re:    jsr chz              ; somewhere else (pushed, new level): replan
@steer: inc bstuck              ; stuck for a while: turn around
        lda bstuck
        cmp #180
        bcc @s1
        lda bdir
        eor #2
        sta bdir
        jsr chz
@s1:    sec                     ; how far to turn: bdir * 256 - pa (10 bits)
        lda #0
        sbc pa
        tax
        lda bdir
        sbc pa+1
        and #3
        bne @s2
        cpx #24                 ; 0 .. 23: facing it
        bcc @fwd
        lda #7                  ; turn right
        bne @fire
@s2:    cmp #3
        bne @s3
        cpx #233                ; -23 .. -1: facing it
        bcs @fwd
@s3:    cmp #2
        bcs @lft
        lda #7
        bne @fire
@lft:   lda #11                 ; turn left
        bne @fire
@fwd:   lda #14                 ; forward
@fire:  pha
        lda #1                  ; trigger: pulse it at a live monster in view
        sta bfirev
        lda sls
        beq @nf
        lda sle
        bmi @nf
        tax
        lda EST,x
        cmp #1
        bne @nf
        lda ETYP,x
        cmp #TY_FIRE
        bcs @nf
        lda dtime
        and #2
        bne @nf
        lda #0
        sta bfirev
@nf:    pla
        rts
chz:    lda #0                  ; (a new plan: not stuck)
        sta bstuck
        jmp choose

.segment "OVLB2"                ; ($08A0)
; choose: from the tile the player is on, head for the first open
;         neighbour in one of four orders picked at random (mostly
;         straight on; back only at a dead end)
choose: lda px+1
        sta bcx
        lda py+1
        sta bcy
        lda RANDOM
        and #12
        tax
@try:   lda bdir
        clc
        adc dturn,x
        and #3
        sta bnd
        tay
        clc
        lda bcx
        adc ddx,y
        sta btx
        clc
        lda bcy
        adc ddy,y
        sta bty
        lsr
        lsr
        lsr
        ora #>map
        sta gptr+1
        lda bty
        asl
        asl
        asl
        asl
        asl
        ora btx
        sta gptr
        ldy #0
        lda (gptr),y
        beq @ok
        cmp #2                  ; the exit: walk in
        beq @ok
        inx
        txa
        and #3
        bne @try
        rts
@ok:    lda bnd
        sta bdir
        rts
.segment "OVLB4"                ; ($0AB0, after the demo message)
dturn:  .byte 0, 1, 3, 2,  0, 3, 1, 2,  1, 0, 3, 2,  3, 0, 1, 2
ddx:    .byte 1, 0, $FF, 0      ; E, S, W, N
ddy:    .byte 0, 1, 0, $FF
btx:    .byte 0                 ; target tile
bty:    .byte 0
bcx:    .byte 0                 ; tile it was chosen from
bcy:    .byte 0
bdir:   .byte 0                 ; heading 0-3 (x 256 = angle)
bnd:    .byte 0
bstuck: .byte 0
dtime:  .word 0
