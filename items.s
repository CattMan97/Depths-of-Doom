; =====================================================================
;  Level dressing and automap marks.  Runs from RAM that only the
;  start-up code used ($7D80 in image A): the menu copies it there from
;  cartridge bank 4 each time it opens.
;
;  placepk   more ammo, health and time on later levels
;  lvlextra  per level: entrance door behind you, keycard colour, and the
;            "find the <colour> keycard" lines
;  frameck   per frame: the exit has been found (locked levels), and the
;            automap's entrance mark is put away when the map closes
;  mapextra  on the automap: the entrance (green) and pickups you've seen
; =====================================================================
.import kpre, ksuf, npre, nsuf, cnames, cnoff, msg_amax, msg_hmax, msg_tmax

C_MENTR = $C8                   ; automap: the entrance (green)
MAPDOT  = $14                   ; automap: a pickup (two yellow pixels)
MAPKEY  = $3C                   ; automap: the keycard (two white pixels)

.segment "RA1"
; placepk: ammo 2 + (level-1)/3 (a gun's, or 1 in 4 super ammo), health and
;          time 1 + (level-1)/7 each
placepk:lda #3
        ldx #2
        ldy #PK_AMMO
        jsr pkn
        lda #7
        ldx #1
        ldy #PK_HEALTH
        jsr pkn
        lda #7
        ldx #1
        ldy #PK_TIME
pkn:    sta pdiv
        stx pcnt
        sty ptyp
        lda level
        sec
        sbc #1
@d:     sec
        sbc pdiv
        bcc @l
        inc pcnt
        bcs @d
@l:     lda ptyp
        jsr pktype              ; (ammo: which gun's, or super ammo)
        jsr addpk
        dec pcnt
        bne @l
        rts

; lvlextra: after the things are placed (place_enemies jumps here)
lvlextra:
        lda tunon               ; came through the tunnel: it ends now
        beq @nt
        jsr tunend
@nt:    lda #0
        sta exitsn
        lda wallc1              ; the keycard is the colour of the locked door
        ora #$0A
        sta pkcol+5
        ; ---- the entrance: a dead door on the wall behind you.  Face an open
        ;      way whose opposite wall can take the door; failing that, the
        ;      door goes on any wall beside you and you face as before.
        ldy #3
@f:     sty edir
        tya
        eor #1
        tay
        jsr ewall               ; wall behind this way?
        bcc @fn
        lda edir
        jsr eopen               ; and this way open?
        bne @fn
        ldy edir
        lda faceang,y
        sta pa+1
        lda edir
        eor #1
        jmp @put
@fn:    ldy edir
        dey
        bpl @f
        ldy #3                  ; no luck: any wall
@g:     sty edir
        jsr ewall
        bcs @gok
        ldy edir
        dey
        bpl @g
        lda #$FF                ; (walled in?  no door)
        sta entx
        jmp lvmsgs
@gok:   lda edir
@put:   tay
        jsr estep
        lda #3                  ; tile 3: a door that never opens
        jsr stmap
        lda nl                  ; its tile, for the automap
        and #31
        sta entx
        lda nh
        asl
        asl
        asl
        sta enty
        lda nl
        lsr
        lsr
        lsr
        lsr
        lsr
        ora enty
        sta enty
        jmp lvmsgs

.segment "RA2"
; lvmsgs: the keycard lines, with this level's colour in them
lvmsgs: ldx level
        dex
@m6:    cpx #6                  ; theme = (level - 1) mod 6
        bcc @m7
        txa
        sbc #6
        tax
        bcs @m6
@m7:    lda cnoff,x
        sta cnm
        lda #<kmsg
        sta gptr
        lda #>kmsg
        sta gptr+1
        lda #>ksuf
        sta bsufh
        lda #<kpre
        ldy #>kpre
        ldx #<ksuf
        jsr build
        lda #<nmsg
        sta gptr
        lda #>nmsg
        sta gptr+1
        lda #>nsuf
        sta bsufh
        lda #<npre
        ldy #>npre
        ldx #<nsuf
        jmp build

; estep: Y = direction -> nl/nh = the tile next to the start
estep:  lda mstl
        sta curl
        lda msth
        sta curh
        jmp step
; eopen: A = direction; Z set if the tile that way is open
eopen:  tay
        jsr estep
        jmp ldmap
; ewall: Y = direction; C set if that tile is a plain wall (not an exit,
;        its stripes, or open)
ewall:  jsr estep
        jsr ldmap
        beq @no
        cmp #2
        beq @no
        cmp #4
        beq @no
        cmp #10
        beq @no
        sec
        rts
@no:    clc
        rts

; build: gptr = destination, A/Y = first part, X = low byte of the last
;        part (same page as ksuf/nsuf), cnm = the colour's offset in cnames.
;        bsufh its high byte.  Writes a message (pad, text, $FF), centred.
build:  sta sptr
        sty sptr+1
        stx bsuf
        ldx #1                  ; output index
        jsr @cp
        lda cnm                 ; the colour
        clc
        adc #<cnames
        sta sptr
        lda #>cnames
        adc #0
        sta sptr+1
        jsr @cp
        lda bsuf
        sta sptr
        lda bsufh
        sta sptr+1
        jsr @cp
        txa                     ; the end mark after the text
        tay
        lda #$FF
        sta (gptr),y
        txa                     ; pad = (40 - length) / 2, length = X - 1
        eor #$FF
        sec
        adc #41
        lsr
        ldy #0
        sta (gptr),y
        rts
@cp:    ldy #0
@c:     lda (sptr),y
        cmp #$FF
        beq @x
        sty bsy
        pha
        txa
        tay
        pla
        sta (gptr),y
        inx
        ldy bsy
        iny
        bne @c
@x:     rts

.segment "RA3"
; frameck: once a frame, from the main loop
frameck:lda amap                ; map closed: take its entrance mark away
        bne @lk
        lda mapm
        beq @lk
        lda #0
        sta mapm
        ldx #VIEWPM+63
@cm:    sta MISMEM,x
        dex
        cpx #VIEWPM
        bcs @cm
        lda #$55                ; missiles: the muzzle flash again
        sta SIZEM
        lda #132
        sta HPOSM0
        lda #C_FLASH
        sta COLOR3
@lk:    lda havekey             ; with the key, the line is "find the exit"
        beq @nk
        lda exitsn
        beq @x
        lda #0
        sta exitsn
        rts
@nk:    lda locked              ; locked and not found yet: seen it now?
        beq @x
        lda exitsn
        bne @x
        lda btl
        sta @a+1
        lda bth
        ora #>SEEN
        sta @a+2
@a:     lda SEEN
        beq @x
        lda #1
        sta exitsn
        lda #<kmsg              ; the keycard line for a while, then the
        ldy #>kmsg              ;   kill line (showlevel)
        jmp showmsg
@x:     rts

; mapextra: after the automap is drawn (drawmap jumps here)
mapextra:
        lda entx                ; ---- the entrance, as a green missile
        bmi @pk
        asl
        asl
        adc #64                 ; HPOS = 48 + 16 + 4 * x
        sta HPOSM0
        lda #$55                ; missile 0 double width: its two bits are four
        sta SIZEM               ;   colour clocks, one tile (quad width was two)
        lda #C_MENTR
        sta COLOR3
        lda enty
        asl
        adc #VIEWPM
        tax
        lda #3
        sta MISMEM,x
        sta MISMEM+1,x
        sta mapm
@pk:    jmp mappk

.segment "RC"                   ; ($3F80: past the end of the BFS queue's use)
mappk:  ldx #FB0-1              ; ---- pickups you've seen
@t:     lda EST,x
        cmp #1
        bne @n
        lda ETYP,x
        bpl @n
        lda EWAKE,x             ; (set when it was on screen)
        beq @n
        stx mex
        ldy #MAPDOT
        lda ETYP,x
        cmp #PK_KEY
        bne @c
        ldy #MAPKEY
@c:     sty mdot
        lda EYH,x               ; byte = buffer + y * 5 * 16 + 4 + x
        asl
        asl
        adc EYH,x               ; (C clear: y < 64)
        sta gptr
        lda #0
        sta gptr+1
        ldy #4
@m:     asl gptr
        rol gptr+1
        dey
        bne @m
        lda EXH,x
        clc
        adc #4
        adc gptr
        sta gptr
        bcc @h
        inc gptr+1
@h:     ldy buf
        lda bufhi,y
        clc
        adc gptr+1
        sta gptr+1
        lda mdot
        ldy #0
        sta (gptr),y
        ldy #40
        sta (gptr),y
        ldx mex
@n:     dex
        bpl @t
        rts

pdiv:   .byte 0
pcnt:   .byte 0
ptyp:   .byte 0
edir:   .byte 0
cnm:    .byte 0
bsuf:   .byte 0
bsufh:  .byte 0
bsy:    .byte 0
mex:    .byte 0
mdot:   .byte 0

.segment "BSSR"                 ; ($B780: start-up code's old corner of image B)
kmsg:   .res 42                 ; FIND THE <colour> KEYCARD, THEN EXIT!
nmsg:   .res 42                 ; LOCKED - FIND THE <colour> KEYCARD
exitsn: .res 1                  ; locked level: the exit has been seen
entx:   .res 1                  ; the entrance's tile ($FF: none)
enty:   .res 1
mapm:   .res 1                  ; the entrance mark is up
mstep:  .res 1                  ; music: 16th within the bar (drums)
keyby:  .res 1                  ; the monster carrying the keycard ($FF: none)
keysl:  .res 1                  ; the keycard's thing

; =====================================================================
.segment "CWC"                  ; ($07C8: past column writer 2)
; keyhide: place_enemies jumps here last.  On a locked level the keycard
;          is hidden, and a monster picked at random carries it.  Then
;          this level's music.
keyhide:lda #$FF
        sta keyby
        lda locked
        beq @m
        ldx #FB0-1
@f:     lda ETYP,x
        cmp #PK_KEY
        beq @k
        dex
        bpl @f
        bmi @m
@k:     stx keysl
        lda #0
        sta EST,x               ; (not in the maze until it's dropped)
@r:     jsr rnd
        and #7
        cmp nimp
        bcs @r
        sta keyby
@m:     ldx level
        jsr mload
        jmp lvlextra

.segment "RT3"                  ; ($0178: low in the stack page, never reached)
; keydrop: Y = a monster just killed.  The carrier drops the keycard where
;          it fell.  Keeps X and Y.
keydrop:cpy keyby
        bne @x
        stx kdx
        ldx keysl
        lda EXH,y
        sta EXH,x
        lda EXL,y
        sta EXL,x
        lda EYH,y
        sta EYH,x
        lda EYL,y
        sta EYL,x
        lda #1
        sta EST,x
        lda #0
        sta EWAKE,x             ; (not seen yet: off the automap)
        lda #$FF
        sta keyby
        lda exitsn              ; the exit's been found: the line says where now
        beq @n
        sty kdy
        lda gptr
        pha
        lda gptr+1
        pha
        jsr showlevel
        pla
        sta gptr+1
        pla
        sta gptr
        ldy kdy
@n:     ldx kdx
@x:     rts
kdx:    .byte 0
kdy:    .byte 0

.segment "CWA"                  ; ($05C8: past column writer 0; the writers end at +$C6)
; mload: X = track (0 title, 1-15 the levels).  Bank 9 -> MBUF, restart.
MUSBANK = 9
mload:  lda #0
        sta NMIEN               ; (the cartridge covers $8000+ meanwhile)
        sta mvol
        sta mvol+2
        lda #MUSBANK
        sta CARTCTL
        txa
        clc
        adc #$80
        sta @s+2
        ldy #MTLEN-1
@s:     lda $8000,y
        sta MBUF,y
        dey
        cpy #$FF
        bne @s
        lda #$80
        sta CARTCTL
        jmp mload2
.segment "CWB"                  ; ($06C8: past column writer 1)
mload2: ldx #2
@i:     lda #0
        sta mord,x
        sta mtr,x
        lda #1
        sta mdur,x
        lda #<mend
        sta mptr,x
        lda #>mend
        sta mptr+1,x
        dex
        dex
        bpl @i
        inx
        stx mstep               ; ($FF: the first 16th is step 0)
        lda #0
        sta mfr
        lda #$C0
        sta NMIEN
        rts

; =====================================================================
; pkfull: Y = the pickup's type; its stat is full, so it stays put
.segment "PKF"                  ; ($0BE5)
pkfull: lda fmlo-PK_AMMO,y
        pha
        lda fmhi-PK_AMMO,y
        tay
        pla
        jsr showmsg
        ldx ei
        rts
fmlo:   .byte <msg_amax, <msg_hmax, <msg_tmax
fmhi:   .byte >msg_amax, >msg_hmax, >msg_tmax

; =====================================================================
; Monster sounds, on POKEY channel 1 (the gun's: a shot takes it over).
.segment "MSND"                 ; ($0340: the OS's I/O control blocks, unused)
MS_GROWL = 0
MS_SWIPE = 1
MS_DEATH = 2
MS_HISS  = 3
; msplay: A = sound.  Keeps X and Y.
msplay: stx mssx
        tax
        lda mslen,x
        sta msnt
        lda msbase,x
        sta msnf
        stx msty
        ldx mssx
        rts
; mswake: Y = a thing that's just been noticed or hit: awake now (a monster
;         that was asleep growls).  Keeps X and Y; A = 1.
mswake: lda EWAKE,y
        bne @w
        lda ETYP,y
        cmp #TY_FIRE            ; (monsters only: not fireballs or pickups)
        bcs @w
        lda #MS_GROWL
        jsr msplay
@w:     lda #1
        sta EWAKE,y
        rts
; msatk: X = a monster lashing out
msatk:  lda #MS_SWIPE
        jsr msplay
        lda #12                 ; (ticks)
        sta EATK,x              ; attack pose
        rts
; mskill: Y = a monster just killed
mskill: lda #MS_DEATH
        jsr msplay
        jmp keydrop
; msnd: from the VBI while msnt > 0.  The pitch slides; when the gun is
;       sounding the monster stays quiet (its time still runs out).
msnd:   dec msnt
        ldx msty
        clc
        lda msnf
        adc msslp,x
        sta msnf
        ldy flash
        bne @x
        sta AUDF1
        lda msnt
        beq @z
        lda msaudc,x
@z:     sta AUDC1
@x:     jmp XITVBV
;               growl  swipe  death  hiss
mslen:  .byte   20,    8,     30,    10     ; frames
msbase: .byte   $70,   $08,   $40,   $02    ; AUDF to start from
msslp:  .byte   3,     5,     4,     1      ; AUDF added a frame (pitch falls)
msaudc: .byte   $C6,   $87,   $C7,   $84    ; tone (C buzz, 8 noise) and volume
