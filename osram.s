; =====================================================================
;  RAM under the OS ROM.  The loader checks this RAM is there, copies the
;  OS's character set ($E000-$E3FF) into the RAM under it, copies these
;  segments in from cartridge banks 10-11, and switches the OS ROM off for
;  good.  So everything the OS did for the game is done here instead:
;    nmi     DLIs through VDSLST, VBIs through VVBLKI (as the OS does)
;    osinit  RESET restarts the game (instead of dropping to BASIC)
;    xitvbv  the end of a VBI
;    irq     the keyboard: CH, with the OS's debounce (KEYDEL)
;  The rest of this RAM holds code and tables the game runs from here.
;
;    $C000-$CFFF  OSC   (4K)
;    $D800-$DFFF  OSD   (2K)
;    $E000-$E3FF        the character set
;    $E400-$FFF9  OSE   (7K), then the 6502's vectors
; =====================================================================
NMIST   = $D40F
NMIRES  = $D40F
IRQST   = $D20E
IRQEN   = $D20E
KBCODE  = $D209
POKMSK  = $10
VVBLKI  = $0222
CH1     = $02F2
COLDSV  = $E477         ; (in the OS ROM: switched back on first)

.segment "OSC"
; ---------------------------------------------------------------------
; The game's display lists: one for each frame buffer, so a new frame only
; needs its list's address (the main program used to rewrite the 128 row
; addresses of a shared list every frame).  Blank, top bar (2 text lines),
; 128 mode F lines (each of the 64 rows twice, LMS on every line), bottom
; bar.  DLIs: top bar colours / view on (GTIA 9) / view off.  Each list is
; 397 bytes, so each sits in its own 512 bytes (ANTIC can't cross a 1K line).
;   The view is symmetric about the horizon, so rows 32-63 show rows 31-0:
; only the top half is ever drawn.  (mir = 0: the plain lists, rows 0-63,
; for the GAME OVER banner, which isn't symmetric.)
.macro GDL bufa, mir
.local top
top:    .byte $70, $F0, $42, <HUD3, >HUD3, $82
        .repeat 128, ln
        .if ln = 127
        .byte $CF
        .else
        .byte $4F
        .endif
        .if mir && (ln / 2) >= 32
        .word bufa + (63 - ln / 2) * 40
        .else
        .word bufa + (ln / 2) * 40
        .endif
        .endrepeat
        .byte $42, <HUD, >HUD, $02, $41
        .word top
        .res 512 - (* - top)
.endmacro
gdl0:   GDL BUF0, 1
gdl1:   GDL BUF1, 1
gdl2:   GDL BUF2, 1
; bendt: where texture band k (1-7) ends, for a wall of scale s: row
;   32 - s + (k * 32 * s) / 256, or 0 while that's still above the screen.
;   A page per k, by s (texcol used to multiply for each band).
bendt:  .repeat 7, kk
        .repeat 256, sc
        .byte ((32 - sc + (((kk + 1) * 32 * sc) >> 8)) > 0) * (32 - sc + (((kk + 1) * 32 * sc) >> 8))
        .endrepeat
        .endrepeat
.assert (bendt & $FF) = 0, error, "bendt must be page-aligned"
.assert (gdl0 & $1FF) = 0 && (gdl2 - gdl0) = 1024, error, "display lists must start on 512-byte lines"

.segment "OSE"
; ---------------------------------------------------------------------
; interp: the rays between the cast ones (0, 8 .. 72, 76, 78, 79), from
;   their neighbours: 4, 12 .. 68 from those 4 away, then 2, 6 .. 74 from
;   those 2 away, then the odd rays.  If both neighbours hit the same face
;   of the same tile (and are both textured or both not), the wall between
;   is that plane: scale, texture column and shade are the averages.  Else
;   the ray is cast.  (Both textured or both not: bit 7 of the hit id.)  Unrolled, with every index a constant (this was a loop
;   round tryint: about 7% of the frame).
.macro IRAY i, l, r
.local cast, done
        lda RIDL+((l)/2)
        cmp RIDL+((r)/2)
        bne cast
        lda RIDH+((l)/2)
        cmp RIDH+((r)/2)
        bne cast
        clc
        lda RCC+(l)
        adc RCC+(r)
        lsr
        sta RCC+(i)
        clc
        lda TID+(l)
        adc TID+(r)
        ror
        sta TID+(i)
        clc
        lda ZB+(l)
        adc ZB+(r)
        ror
        sta ZB+(i)
  .if ((i) & 1) = 0               ; (even rays: later ones interpolate from it)
        lda RIDL+((l)/2)
        sta RIDL+((i)/2)
        lda RIDH+((l)/2)
        sta RIDH+((i)/2)
  .endif
        jmp done
cast:   ldx #(i)
  .if ((i) & 1) = 0
        jsr icaste
  .else
        jsr icasto
  .endif
done:
.endmacro
interp: .repeat 9, k
        IRAY k * 8 + 4, k * 8, k * 8 + 8
        .endrepeat
        .repeat 19, k
        IRAY k * 4 + 2, k * 4, k * 4 + 4
        .endrepeat
        .repeat 39, k
        IRAY k * 2 + 1, k * 2, k * 2 + 2
        .endrepeat
        rts
icaste: stx rayi                ; (cast: an even ray)
        jsr castray
        jmp keep
icasto: stx rayi                ; (an odd ray: just its shade kept)
        jsr castray
        ldx rayi
        lda ccur
        sta RCC,x
        rts

; ---------------------------------------------------------------------
; Game time.  The game runs in ticks of 1/20 s (3 VBIs): movement, monsters
; and timers are per tick, so the game keeps the same pace whatever the
; frame rate.  (They were per frame, so a faster frame made a faster game.)
; ticks: the ticks due since the last frame: ntick = 1-4.  Waits for one
;        if none is due yet (so at most 20 frames a second).  More than 4
;        behind (a very slow frame) and the rest are dropped.
ticks:  lda RTCLOK+2
        sec
        sbc lastj
        cmp #3
        bcc ticks
        cmp #15
        bcs @far
        ldx #0
@d:     inx
        sec
        sbc #3
        tay
        clc
        lda lastj
        adc #3
        sta lastj
        tya
        cmp #3
        bcs @d
        stx ntick
        rts
@far:   lda #4
        sta ntick
tickrs: lda RTCLOK+2            ; (from now on)
        sta lastj
        rts
; tick: the per-tick timers: the exit stripes scroll (a step every two
;       ticks), a pickup message times out, the hurt flash fades
tick:   inc hzc
        lda hzc
        lsr
        sta hzph
        lda msgt
        beq @nm
        dec msgt
        bne @nm
        jsr showlevel
@nm:    lda hurt
        beq @nh
        dec hurt
        lda #$80
@nh:    sta hurtofs
        rts
; same: C set if the view is the one last drawn (same place, same angle,
;       same texture setting, no exit stripes scrolling on it, nothing
;       changed in the maze): then the frame on screen can stay.  Else C
;       clear, and this view is remembered.
.ifdef BENCH
same:   clc                     ; (benchmark builds: always draw)
        rts
.endif
.ifndef BENCH
same:
.endif
same_:  lda forcer
        ora intro
        ora hzvis
        bne @new
        ldx #5
@c:     lda px,x                ; (px, py, pa)
        cmp lastv,x
        bne @new
        dex
        bpl @c
        lda lods
        cmp lastl
        bne @new
        sec
        rts
@new:   ldx #5
@s:     lda px,x
        sta lastv,x
        dex
        bpl @s
        lda lods
        sta lastl
        lda #0
        sta forcer
        sta hzvis
        clc
        rts
; still: (from the main loop) the view hasn't changed: no casting or
;        drawing.  The frame on screen is shown again, with new sprites.
still:  lda pending
        bne still
.ifndef NOSPR
        jsr sprites
.endif
        ldx shownb
        lda gdlo,x
        sta nextdl
        lda gdhi,x
        sta nextdlh
        lda #0
        sta nextmap
        sta ATRACT
        lda #1
        sta pending
        jmp mainloop
forcer: .byte 1                 ; (nonzero: draw the view however it looks)
hzvis:  .byte 0                 ; (exit stripes were on the last view)
shownb: .byte 0                 ; the buffer holding the last view drawn
lastv:  .res 6
lastl:  .byte 0
ntick:  .byte 0
lastj:  .byte 0
hzc:    .byte 0

; nmi: as the OS's handler, less the jump through VNMI
nmi:    bit NMIST
        bpl @nd
        jmp (VDSLST)            ; display list interrupt
@nd:    bvc nmix                ; (not the VBI)
        cld
        pha
        txa
        pha
        tya
        pha
        sta NMIRES
        jmp (VVBLKI)
xitvbv: pla
        tay
        pla
        tax
        pla
        rti

nmix:   rti                     ; (no other NMI on an XL: RESET is a real reset)

; osinit: once, at start-up.  RESET on an XL resets the chips: the OS ROM
;         and BASIC come back, and the OS warm-starts.  It can't find the
;         cartridge (switched off), so it would drop to BASIC.  But it calls
;         DOSINI first when BOOT? says a disk booted: point that at a stub
;         that switches the cartridge back on and cold-starts, so RESET
;         restarts the game.  The stub lives in the stack page below where
;         the stack ever reaches, which the warm start leaves alone.
RSTUB   = $01CA
BOOTQ   = $09
DOSINI  = $0C
osinit: ldx #rstend-rstub-1
@c:     lda rstub,x
        sta RSTUB,x
        dex
        bpl @c
        lda #<RSTUB
        sta DOSINI
        lda #>RSTUB
        sta DOSINI+1
        lda BOOTQ
        ora #1
        sta BOOTQ
        rts
rstub:  sei
        lda #0
        sta NMIEN
        sta CARTCTL             ; cartridge on (bank 0; the loader is fixed)
        lda #$FF                ; OS ROM on, BASIC off
        sta PORTB
        jmp COLDSV
rstend:
.assert rstend - rstub <= $16, error, "reset stub too big for $01CA-$01DF"

; irq: the keyboard (any other IRQ is just acknowledged)
irq:    pha
        lda IRQST
        and #$40                ; 0 = a key
        bne @other
        lda POKMSK
        and #$BF
        sta IRQEN
        lda POKMSK
        sta IRQEN
        lda KBCODE
        cmp CH1                 ; the same key again: only after the debounce
        bne @new
        lda KEYDEL
        bne @x
        lda KBCODE
@new:   sta CH
        sta CH1
        lda #3
        sta KEYDEL
@x:     pla
        rti
@other: lda #0
        sta IRQEN
        lda POKMSK
        sta IRQEN
        pla
        rti

.segment "OSV"
        .word nmi               ; $FFFA
        .word nmi               ; $FFFC (RESET: never used, the ROM is off)
        .word irq               ; $FFFE

.segment "OSD"
; =====================================================================
; dpairs: draw the 40 byte columns of the view (two rays each) into the
;   back buffer.  Replaces the main loop's pair loop, drawpair, texcol,
;   band, grun and seg: the same picture, row for row, with much less
;   overhead per column (about a third of the frame went on it).
;
;   Every wall is symmetric about the horizon (row 32), so only rows 0-31
;   are worked out; the column writers store each row with its mirror.
;   Rows of a column, top down:
;     [prev, sega)   ceiling: gradient in both nibbles (rows above prev
;                    are already ceiling in this buffer)
;     [sega, segbx)  the taller ray's wall, gradient in the other nibble
;     [segbx, 32)    both rays' walls
;   Textured walls (scale >= lods) come in 8 bands, ending at bendt's rows;
;   equal neighbouring bands are runs (mkruns).
; =====================================================================
dpairs: ldx buf                 ; this frame's writers and top-row array
        lda cwhi,x
        sta wrp1+2
        sta wrp2+2
        sta wrj+2
        lda prevlo,x
        sta pv1+1
        sta pv2+1
        sta pv3+1
        sta pv4+1
        ldx #0
dpair:  stx pairx
        txa
        asl
        tay
        lda ZB,y                ; the two rays: scale, height, shade, texture
        sta sl
        cmp #33
        bcc @h1
        lda #32
@h1:    sta hl
        lda RCC,y
        sta cl
        lda ZB+1,y
        sta sr
        cmp #33
        bcc @h2
        lda #32
@h2:    sta hr
        lda RCC+1,y
        sta cr
        lda TID,y
        cmp #HAZID              ; (only stripe ids can scroll)
        bcc @z1
        jsr hzs
@z1:    sta tidl
        lda TID+1,y
        cmp #HAZID
        bcc @z2
        jsr hzs
@z2:    sta tidr
        cmp #$FF                ; (a solid wall next to a textured one)
        beq @sol
        lda tidl
        cmp #$FF
        beq @sol
        lda sl
        cmp sr
        bcc @rgt
        ; ---- the left ray is the taller (or equal)
        cmp lods
        bcc @sol
        sta tsc
        sbc sr                  ; (C set) the difference
        sta sdiff
        lda #0
        sta gss                 ; (the gradient goes to the right nibble)
        lda kside               ; bt: the left ray's bands, unless the last
        bne @ln                 ;   pair's are the same
        lda tidl
        cmp ktid
        bne @ln
        lda cl
        cmp kshade
        beq @lk
@ln:    lda #0
        sta kside
        lda tidl
        sta ktid
        ldy cl
        sty kshade
        jsr bthi
@lk:    lda tsc                 ; close enough to share bands?  (their
        lsr                     ;   scales differ by at most 1/8 of the
        lsr                     ;   taller one, + 1)
        lsr
        clc
        adc #1
        cmp sdiff
        bcc @lfar
        lda tidr                ; bb: bt | the right ray's bands
        cmp kstid
        bne @ls
        lda cr
        cmp ksshade
        bne @ls
        jmp dtex
@ls:    lda tidr
        sta kstid
        ldy cr
        sty ksshade
        jsr bblo
        jmp @tex
@lfar:  ldy cr                  ; too different: the right ray solid
        lda nibr+8,y
        jmp bbfill
@sol:   jmp dsolid
@rgt:   ; ---- the right ray is the taller
        lda sr
        cmp lods
        bcc @sol
        sta tsc
        sbc sl
        sta sdiff
        lda #8
        sta gss                 ; (the gradient goes to the left nibble)
        lda kside
        cmp #1
        bne @rn
        lda tidr
        cmp ktid
        bne @rn
        lda cr
        cmp kshade
        beq @rk
@rn:    lda #1
        sta kside
        lda tidr
        sta ktid
        ldy cr
        sty kshade
        jsr btlo
@rk:    lda tsc
        lsr
        lsr
        lsr
        clc
        adc #1
        cmp sdiff
        bcc @rfar
        lda tidl
        cmp kstid
        bne @rs
        lda cl
        cmp ksshade
        beq @tex
@rs:    lda tidl
        sta kstid
        ldy cl
        sty ksshade
        jsr bbhi
        jmp @tex
@rfar:  ldy cl
        lda nibl+8,y
        jmp bbfill
@tex:   jmp dtex

; hzs: the exit's stripes scroll (A = texture id, >= HAZID)
hzs:    cmp #HAZID+16
        bcs @x
        inc hzvis               ; (stripes on screen: they move)
        adc hzph                ; (C clear)
        and #15
        ora #HAZID
@x:     rts

; bthi/btlo: bt = the taller ray's 8 band nibbles (left / right): texture
;   id ktid at shade Y.  bbhi/bblo: bb = bt | the shorter ray's (kstid,
;   shade Y).  bbfill: bb = bt | A.  All mark the runs for rebuilding.
.macro TPTR tid
        lda tid                 ; gptr = tdel + id * 8
        sty tbase
        ldy #0
        sty gptr+1
        asl
        rol gptr+1
        asl
        rol gptr+1
        asl
        rol gptr+1
        adc #<tdel              ; (C clear: the rol out of a 0)
        sta gptr
        lda gptr+1
        adc #>tdel
        sta gptr+1
        lda #$FE                ; (a new bt: bb is stale too)
.endmacro
bthi:   TPTR ktid
        sta kstid
        ldy #7
@l:     lda (gptr),y
        adc tbase               ; (C clear: no sum passes 255)
        tax
        lda nibl,x
        sta bt,y
        dey
        bpl @l
        bmi dirty
btlo:   TPTR ktid
        sta kstid
        ldy #7
@l:     lda (gptr),y
        adc tbase
        tax
        lda nibr,x
        sta bt,y
        dey
        bpl @l
dirty:  lda #1
        sta rdirty
        ldx pairx
        rts
bbhi:   TPTR kstid
        ldy #7
@l:     lda (gptr),y
        adc tbase
        tax
        lda nibl,x
        ora bt,y
        sta bb,y
        dey
        bpl @l
        bmi dirty
bblo:   TPTR kstid
        ldy #7
@l:     lda (gptr),y
        adc tbase
        tax
        lda nibr,x
        ora bt,y
        sta bb,y
        dey
        bpl @l
        bmi dirty
bbfill: sta tmp
        lda #$FE
        sta kstid
        ldy #7
@f:     lda bt,y
        ora tmp
        sta bb,y
        dey
        bpl @f
        lda #1
        sta rdirty
        ; fall through

; ---------------------------------------------------------------------
; dtex: a textured pair
dtex:   ldx pairx
        lda hl                  ; sega = 32 - the taller height,
        cmp hr                  ; segbx = 32 - the shorter
        bcs @a
        lda hr
        eor #$FF
        sec
        adc #32
        sta sega
        lda hl
        jmp @b
@a:     eor #$FF
        sec
        adc #32
        sta sega
        lda hr
@b:     eor #$FF
        sec
        adc #32
        sta segbx
pv1 = *
        lda PREV0,x             ; ceiling where the wall was last time
        cmp sega
        bcs @nc
        sta segS
        lda sega
        sta segE
        lda #16
        sta gsd
        lda #0
        sta gor
        jsr grad
@nc:    lda sega
pv2 = *
        sta PREV0,x
        sta pos
        lda rdirty              ; the band runs, unless the last pair's
        beq @rr
        jsr mkruns              ; (keeps X)
@rr:    ldy #0                  ; run k ends at bendt's row for the scale
@k:     sty bk
        lda rk,y
        beq @last               ; (the last run ends at the horizon)
        sta @bt+2
        ldy tsc
@bt:    lda bendt,y
        cmp pos
        beq @nx
        jsr dband
@nx:    ldy bk
        iny
        bne @k
@last:  lda #32
        jsr dband
        ldx pairx
        inx
        cpx #NPAIRS
        beq @x
        jmp dpair
@x:     rts

; dband: rows [pos, A) of run bk: the taller ray's nibble (rt) above
;        segbx, with the gradient beside it; both rays' byte (rb) below
dband:  sta bend
        lda segbx
        cmp bend
        bcs @allt               ; the shorter ray starts at or after the end
        cmp pos
        bcc @allb
        beq @allb
        sta segE                ; split: [pos, segbx) the taller only
        lda pos
        sta segS
        ldy bk
        lda rt,y
        sta gor
        lda gss
        sta gsd
        jsr grad
        lda segbx
        sta pos
@allb:  lda pos                 ; [pos, bend): both
        sta segS
        ldy bk
        lda rb,y
        ldy bend
        sty pos
        jmp wr
@allt:  lda pos                 ; [pos, bend): the taller only
        sta segS
        lda bend
        sta segE
        sta pos
        ldy bk
        lda rt,y
        sta gor
        lda gss
        sta gsd
        ; fall through
; grad: rows [segS, segE) of the gradient (table offset gsd), each 4-row
;       band's value OR gor.  Keeps X.
grad:   lda segS
@l:     cmp segE
        bcs @x
        lsr
        lsr
        tay                     ; band
        asl
        asl
        adc #4                  ; (C clear) the next band's first row
        cmp segE
        bcc @e
        lda segE
@e:     sta gend
        tya
        clc
        adc gsd
        tay
        lda gtab,y
        ora gor
        ldy gend
        jsr wr
        lda gend
        sta segS
        bne @l
@x:     rts

; wr: rows [segS, Y) of column X := A via this frame's column writer (an
;     RTS put in at row Y for the call; the display list mirrors them).
;     Keeps X.
wr:     cpy segS
        beq wrx
        bcc wrx
        sta segV
        lda mul3,y
        tay
        lda #$60
wrp1 = *
        sta CW0,y
        sty patchy
        ldy segS
        lda mul3,y
        sta wrj+1
        lda segV
wrj = *
        jsr CW0
        ldy patchy
        lda #$9D
wrp2 = *
        sta CW0,y
wrx:    rts
mul3:   .repeat 33, r           ; writer entry for row r
        .byte 3 * r
        .endrepeat

; ---------------------------------------------------------------------
; dsolid: an untextured pair (far walls): ceiling, the taller ray's
;         colour beside the gradient, both colours
dsolid: ldx pairx
        lda hl
        cmp hr
        bcs @lge
        sta hmin                ; right taller: its nibble, gradient left
        lda hr
        sta hmax
        ldy cr
        lda nibr+8,y
        sta mixv
        lda #8
        sta gss
        bne @c
@lge:   lda hr
        sta hmin
        lda hl
        sta hmax
        ldy cl
        lda nibl+8,y
        sta mixv
        lda #0
        sta gss
@c:     ldy cl
        lda nibl+8,y
        ldy cr
        ora nibr+8,y
        sta bothv
        lda hmax
        eor #$FF
        sec
        adc #32
        sta sega
        lda hmin
        eor #$FF
        sec
        adc #32
        sta segb
pv3 = *
        lda PREV0,x             ; ceiling [last top, sega)
        cmp sega
        bcs @nc
        sta segS
        lda sega
        sta segE
        lda #16
        sta gsd
        lda #0
        sta gor
        jsr grad
@nc:    lda sega                ; mixed [sega, segb)
pv4 = *
        sta PREV0,x
        sta segS
        lda segb
        sta segE
        lda mixv
        sta gor
        lda gss
        sta gsd
        jsr grad
        lda segb                ; both [segb, 32)
        sta segS
        lda bothv
        ldy #32
        jsr wr
        ldx pairx
        inx
        cpx #NPAIRS
        beq @x
        jmp dpair
@x:     rts

.segment "OSP"                  ; ($F600: three 512-byte slots)
pdl0:   GDL BUF0, 0
pdl1:   GDL BUF1, 0
pdl2:   GDL BUF2, 0
.segment "OSE"
; unmir: the frame on screen gets its bottom half (rows 32-63: the
;        mirror of 0-31, which is all that's drawn), for GAME OVER
unmir:  ldx shownb
        lda bufhi,x
        sta sptr+1
        clc
        adc #>(63 * NPAIRS)
        sta gptr+1
        lda #0
        sta sptr
        lda #<(63 * NPAIRS)
        sta gptr
        ldx #32
@r:     ldy #NPAIRS-1
@c:     lda (sptr),y
        sta (gptr),y
        dey
        bpl @c
        clc
        lda sptr
        adc #NPAIRS
        sta sptr
        bcc @s
        inc sptr+1
@s:     sec
        lda gptr
        sbc #NPAIRS
        sta gptr
        bcs @d
        dec gptr+1
@d:     dex
        bne @r
        rts
; plaindl: the frame on screen through its plain list (GAME OVER)
plaindl:ldx shownb
        lda pdlo,x
        sta SDLSTL
        lda pdhi,x
        sta SDLSTL+1
        rts
pdlo:   .byte <pdl0, <pdl1, <pdl2
pdhi:   .byte >pdl0, >pdl1, >pdl2
