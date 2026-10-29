; =====================================================================
;  DEPTHS OF DOOM - raycasting first-person shooter for 64K Atari XL/XE machines
;  128K switchable XEGS cartridge (.CAR type 35), ca65 syntax.
;
;  This file is the game image.  It runs from RAM at $4000-$7FFF: the loader in
;  the cartridge's fixed bank copies it there from banks 0-1, and the game then
;  switches the cartridge off, freeing $8000-$BFFF as RAM.
;
;  Display : ANTIC mode D, full-width playfield (160x64, 4 colours),
;            double-buffered, 80 ray columns (2 pixels each)
;  Colours : COLBK = ceiling/floor gradient via DLIs (red tint when hurt)
;            PF0 = exit door, PF1/PF2 = wall (lit side / shaded side)
;  Sprites : P0 gun, P1 hand, P2/P3 the two nearest visible enemies
;            (scaled, clipped per column against a depth buffer),
;            missiles = muzzle flash (fifth-player colour PF3)
;  Levels  : every level is a new random maze (generated in RAM), with
;            more imps each time; the exit door is placed far from the start
;  Controls: joystick in port 1. Up/down move, left/right turn, fire shoots.
;            SELECT = automap, OPTION = music on/off
;  Seeds   : every run comes from a 4-digit seed (typed on the title/game-over
;            screen, or random).  Each level is built from (seed, level) only.
; =====================================================================

; ---------------- hardware
HPOSP0  = $D000
HPOSP1  = $D001
HPOSP2  = $D002
HPOSP3  = $D003
SIZEP0  = $D008
SIZEP1  = $D009
SIZEP2  = $D00A
SIZEP3  = $D00B
HPOSM0  = $D004
HPOSM1  = $D005
HPOSM2  = $D006
HPOSM3  = $D007
SIZEM   = $D00C
COLPM2  = $D014
COLPM3  = $D015
GRACTL  = $D01D
COLPF0  = $D016
COLPF1  = $D017
COLPF2  = $D018
COLBK   = $D01A
AUDF1   = $D200
AUDC1   = $D201
AUDF2   = $D202
AUDC2   = $D203
AUDF3   = $D204         ; music: bass
AUDC3   = $D205
AUDF4   = $D206         ; music: lead
AUDC4   = $D207
AUDCTL  = $D208
DLISTL  = $D402
COLPM0  = $D012         ; (PCOLR0-3, COLOR0-4 shadows map to $D012-$D01A)
PORTA   = $D300
TRIG0   = $D010
KEYDEL  = $02F1         ; OS: keyboard debounce timer
PMBASE  = $D407
WSYNC   = $D40A
VCOUNT  = $D40B
NMIEN   = $D40E

; ---------------- OS shadows / vectors
RTCLOK  = $12
ATRACT  = $4D
VDSLST  = $0200
SDMCTL  = $022F
SDLSTL  = $0230
GPRIOR  = $026F
STICK0  = $0278
STRIG0  = $0284
PCOLR0  = $02C0
PCOLR1  = $02C1
PCOLR2  = $02C2
PCOLR3  = $02C3
COLOR0  = $02C4
COLOR1  = $02C5
COLOR2  = $02C6
COLOR3  = $02C7
COLOR4  = $02C8
XITVBV  = xitvbv        ; (osram.s: the OS ROM is off)

; ---------------- RAM layout (16K machine: $0000-$3FFF)
CW0     = $0500         ; generated column writers, one page per buffer
.ifndef VROWS
VROWS   = 16            ; rows drawn above the horizon, 4 scanlines each (32: 2 each)
.endif
NBAND   = 4             ; texture bands per half wall (tdel and bendt are built for 4;
                        ;   8 bands: the deprecated-v1 branch)
CW1     = $0600
CW2     = $0700
MDLA    = $0800         ; automap display lists (mode D), two in turn
MDLB    = $0850
PRIOR   = $D01B
PRI_GT9 = $51           ; GTIA mode 9 + players over playfield + 5th player
PRI_STD = $11
PREV0   = $0900         ; per-pair top-of-wall row last drawn, per buffer
PREV1   = $0928
DUMMY   = $0950         ; 40-byte sink for the writers' 65th entry
PREV2   = $0978
HUD     = $0A00         ; two 40-char text lines
HUD3    = $3A00         ; top bar: two text lines (score, level, heading / seed, time)
SEEN    = $BC00         ; automap: 1 = a ray has hit this wall tile (32x32, 1K)
CONSOL  = $D01F
TRIG3   = $D013         ; cartridge-present line (XL/XE)
GINTLK  = $03FA         ; OS copy of TRIG3
CARTCTL = $D500         ; switchable XEGS: bank number, bit 7 = cartridge off
PORTB   = $D301         ; XL/XE memory control: bit 0 OS ROM, bit 1 BASIC (1 = off)
DMACTL  = $D400
IMGB_BANK = 2           ; image B lives in cartridge banks 2-3
CH      = $02FC         ; OS: last key pressed ($FF = none)
BUF0    = $1000         ; 40 bytes x 64 rows ($1000-$19FF)
PMG     = $1C00         ; double-line PMG block (1K)
BUF1    = $2000         ; ($2000-$29FF; no buffer crosses a 4K line)
BUF2    = $3000         ; ($3000-$39FF; OS screen at $3C00+ is unused)
P0MEM   = PMG+$200
P1MEM   = PMG+$280
P2MEM   = PMG+$300
P3MEM   = PMG+$380
MISMEM  = PMG+$180
NPAIRS  = 40
ZB      = $0A50         ; per-ray wall scale (depth buffer), 80 bytes
OUTROW  = $0AA0         ; resampled sprite rows, 16 bytes
STAGE2  = $0B00         ; staged 64 view rows for player 2
STAGE3  = $0B40         ; ... player 3
map     = $0C00         ; 32x32 maze, generated at run time (1K)
MDIST   = $2C00         ; BFS walking distance per tile (1K)
MQ      = $3C00         ; BFS queue: 512 x (low byte, page)
MSTKL   = $2A00         ; maze generator stack: tile low bytes ...
MSTKH   = $2B00         ;   ... and pages
gpc     = vt            ; level generation: map / MDIST row pointers for the
gdc     = vt+2          ;   row being scanned (c), the one above (u) and below (d)
gpu     = vb            ;   (zero page the renderer uses only while it draws)
gdu     = vb+2
gpd     = sl            ; (sl, sr)
gdd     = tidl          ; (tidl, tidr)
STRAIGHT = 0            ; maze: chance in 4 of carrying straight on (0 = turn freely)
LOOPS   = 4             ; maze: extra openings per cell row (loops)
SHORT   = 2             ; maze: dead ends are kept only this many cells from a junction
MAZEN   = 11            ; maze size in cells (tiles: 2 * MAZEN + 1), 15 at most
AIRANGE = 32            ; monsters path-find this many steps around you
RANDOM  = $D20A
VTOP    = 20            ; VCOUNT of the first view row
MAXEN   = 8             ; imps per level, at most
MAXTH   = 24            ; things (imps + pickups) per level
; thing types (ETYP): monsters are 0-$7F, pickups $80+
TY_IMP  = 0
TY_BRUTE = 1            ; charger: fast, tough, hits hard
TY_SPIT = 2             ; keeps its distance and spits fireballs
TY_FIRE = 3             ; a fireball in flight (not a target)
FB0     = MAXTH-2       ; the last two things are reserved for fireballs
BRUTELEVEL = 3
SPITLEVEL  = 5
HPMAX   = 12            ; imp toughness cap (+1 per level from level 4)
FBS     = 20            ; fireball speed, 1/256 tile per tick (max axis)
FB_DMG  = 12
FB_LIFE = 160           ; ticks a fireball flies before fizzling
SPITCOOL = 56           ; ticks between spits (+ 0-30 random)
FIREIDX = 9             ; texture numbers (texlo/texhi)
FALLIDX = 10
CORPSEIDX = 11
C_BRUTE = $5A
C_SPIT  = $C6
PK_AMMO = $80
PK_HEALTH = $81
PK_TIME = $82
PK_SHOTGUN = $83
PK_CHAIN = $84
PK_KEY  = $85
PK_PISTOL = $86        ; pistol ammo (PK_SHOTGUN / PK_CHAIN: that gun, or its ammo)
KEYLEVEL   = 3          ; exit locked from this level on
SHOTLEVEL  = 2          ; shotgun lying around from here, until you have it
CHAINLEVEL = 4
AMMO_PK = 15
HEALTH_PK = 25
TIME_PK = 30
C_DOOR  = $44           ; unlocked exit
C_LOCK  = $86           ; locked exit (blue)

VIEWPM  = 20            ; PM line of the view's first row (below the top bar)
GUNTOP  = VIEWPM+48     ; PM line of gun's first row (view bottom = VIEWPM+63)
TURN0   = 4             ; turning: angle units (1024/circle) per tick,
TURNUP  = 1             ;   ramping up while the stick is held
TURNMAX = 12
MARGIN  = 64            ; collision margin (1/4 tile)

; colours
C_PF0   = $44           ; exit door (red)
C_PF1   = $0C           ; walls, lit side (light gray)
C_PF2   = $08           ; walls, shaded side (gray)
C_EXIT  = $44           ; exit door, solid red
C_LOCKED = $00          ; locked exit, solid black
C_HAND  = $3A
C_GUNHI = $0C
C_FLASH = $2E
T_LEVEL = 30            ; seconds added per level, plus 2 s per step to the exit
T_START = 180           ; seconds on the clock at the start of a game (level 1)
T_KILL  = 10            ; seconds added per kill
MSGTIME = 50            ; ticks a pickup message stays up
T_CAPM  = 5             ; clock maximum, minutes
T_PANIC = 15            ; music speeds up below this
T_FLASH = 10            ; clock ticks below this
T_BLINK = 30            ; clock blinks below this
ESPMAX  = 32
C_MWALL = $46           ; automap colours
C_MDOOR = $2C
C_MYOU  = $0E
C_IMP   = $26
C_PAIN  = $0E
C_DEAD  = $44

; MUL8: (prodl,prodh) = a * Y, a set by setmul (inline quarter squares)
.macro MUL8
        sec
        lda (msl),y
        sbc (mml),y
        sta prodl
        lda (msh),y
        sbc (mmh),y
        sta prodh
.endmacro
; SETMUL: multiplier a for MUL8 (inline setmul)
.macro SETMUL
        sta msl
        sta msh
        eor #$FF
        sta mml
        sta mmh
.endmacro

LODS    = 10            ; walls at least this scale are textured
HAZID   = 112           ; texture id of the exit's stripes (texbase, tile 10)
HZMID   = 208           ; ... mirrored (west / north of the exit: they point at it)
E_HP    = 3             ; an imp's toughness (hit points; kept as half points: x 2)
.ifndef E_SPEED
E_SPEED = 8             ; 1/256 tile per tick, level 1
ESTEP   = 1             ; faster each level
.else
ESTEP   = 0             ; (test builds that freeze the imps)
.endif
E_MARG  = 80            ; enemy collision margin
DMG     = 10            ; health lost per hit
ATKCOOL = 20            ; ticks between enemy hits

.import sqlo, sqhi, sqmlo, sqmhi
.import invcl, invch, invsl, invsh
.import movxl, movxh, movyl, movyh
.import spat, sprm, sprhw, sprsz, sprsh, htab, dvl, dvh, cs9
.import s88la, s88ha, s88lb, s88hb
.import impb, corpseb, handq
.import msg_died, hudline3, msg_tout
.import texlo, texhi, msg_texon, msg_texoff, msg_pause, compass
.importzp PAMDIG, SAMDIG, MAMDIG
.import qcos, tdel, nibl, nibr
.importzp NID
.import wpnname, gungfx3, handq3, pklo, pkhi, pkcol
.import msg_kill, msg_gotkey, msg_health, msg_time, msg_shotgun, msg_super
.import msg_pammo, msg_sammo, msg_mammo
.import msg_chain, msg_noweapon
.importzp WPNPOS, KEYPOS, LVLPOSK
.importzp SCOREPOS, HIGHPOS, TIMEPOS, SEEDPOS, LVLTPOS, DIRPOS
.import mfreq, MBUF
mplo    = MBUF+MT_PLO       ; the playing track (copied from bank 9: mload)
mphi    = MBUF+MT_PHI
mordb   = MBUF+MT_ORDB
mordl   = MBUF+MT_ORDL
mattack = MBUF+MT_ATK       ; attack volume: bass, -, lead
.importzp MT_TICK, MT_FAST, MT_BDIST, MT_LDIST, MT_ATK, MT_BFLOOR, MT_LFLOOR, MT_LRATE
.importzp MT_DRUM, MT_BFREQ, MT_PLO, MT_PHI, MT_ORDB, MT_ORDL, MTLEN
.import offlo, offhi, cosfix, gtab, fogl, fogs
.import hudline1, msg_level, msg_empty
.import gungfx, flashgfx
.importzp AMMOPOS, KILLPOS, HEALTHPOS, LVLPOS


; ---------------- zero page (layout of the first bytes is read by the test harness)
.segment "ZEROPAGE"
fcount: .res 1
ammo:   .res 1
px:     .res 2          ; 8.8 position, hi = tile
py:     .res 2
pa:     .res 2          ; 10-bit angle
ra:     .res 1          ; ray angle low byte (q)
quad:   .res 1          ; ray quadrant 0-3
dxl:    .res 1
dxh:    .res 1
dyl:    .res 1
dyh:    .res 1
sxl:    .res 1
sxh:    .res 1
syl:    .res 1
syh:    .res 1
stepx:  .res 1
stepy:  .res 1
hitv:   .res 1
hitside:.res 1
distl:  .res 1
disth:  .res 1
pl:     .res 1
ph:     .res 1
rayi:   .res 1
pairx:  .res 1
tmp:    .res 1
tmp2:   .res 1
prodl:  .res 1
prodh:  .res 1
msl:    .res 2          ; quarter-square multiply pointers
msh:    .res 2
mml:    .res 2
mmh:    .res 2
hcur:   .res 1
ccur:   .res 1
hl:     .res 1
hr:     .res 1
cl:     .res 1
cr:     .res 1
hmin:   .res 1
hmax:   .res 1
mixv:   .res 1
bothv:  .res 1
sega:   .res 1
segb:   .res 1
segS:   .res 1
sl:     .res 1          ; textured walls: the pair's two scales, texture columns
sr:     .res 1
tidl:   .res 1
tidr:   .res 1
tsc:    .res 1          ; the taller ray's scale
sdiff:  .res 1
segbx:  .res 1          ; short ray's top row ...
pos:    .res 1          ; band emitter: next row, pending run start/value
bend:   .res 1
vtv:    .res 1
vbv:    .res 1
mp:     .res 2          ; pointers into map / MDIST (low bytes stay 0)
dp:     .res 2
qhp:    .res 2          ; BFS queue head / tail
qtp:    .res 2
tvp:    .res 2          ; tileval
lods:   .res 1          ; texture threshold: LODS, or 255 with textures off (T)
vt:     .res 4          ; per band: taller ray's nibble, and both rays' byte
vb:     .res 4
segE:   .res 1
segV:   .res 1
patchy: .res 1
jptr:   .res 2
cpptr:  .res 2
prevptr:.res 2
buf:    .res 1
stick:  .res 1
mdxl:   .res 1
mdxh:   .res 1
mdyl:   .res 1
mdyh:   .res 1
nxl:    .res 1
nxh:    .res 1
flash:  .res 1
won:    .res 1
pending:.res 1          ; 1 = a finished frame is queued for the VBI
nextdl: .res 1
nextdlh:.res 1
genl:   .res 1
genh:   .res 1
gptr:   .res 2
mptr:   .res 4          ; music pattern pointers (bass, lead), used by the VBI only
tlo:    .res 2          ; sprite helpers
sptr:   .res 2
vis:    .res 1
occ:    .res 1
vlo:    .res 1
vhi:    .res 1

.segment "BSS2"
hitlo:  .res 1          ; what the last ray hit: tile low byte ...
hitid:  .res 1          ;   ... and page * 2 + face, + $80 if textured
rl:     .res 1          ; ray interpolation: the neighbours
rr:     .res 1
score:  .res 3          ; 24-bit binary
high:   .res 3
nn:     .res 3          ; dec6 work
tt0:    .res 1
tt1:    .res 1
dg:     .res 1
tcol:   .res 1          ; tileval
TID:    .res 80         ; per ray: wall texture column (texbase + u)
amap:   .res 1          ; 1 = automap showing
amreq:  .res 1          ; SELECT pressed (set by the VBI)
cprev:  .res 1          ; console keys last frame
muson:  .res 1          ; music on (OPTION toggles)
mty:    .res 1
mtx:    .res 1
mpx:    .res 1
mpy:    .res 1
mnx:    .res 1
mrow:   .res 32
tadm:   .res 1          ; seconds to add: written by the main program
tadv:   .res 1          ;   ... and how much of it the VBI has applied
tinv:   .res 1          ; $80 while the clock blinks (inverse)
paused: .res 1          ; 1 = paused (VBI holds the clock and sound)
hzph:   .res 1          ; exit stripes: scroll position
demo:   .res 1          ; 1 = the demo is running (the bot plays)
bfirev: .res 1          ; the bot's trigger (0 = pressed)
dwait:  .res 1          ; game over: frames waited
intro:  .res 1          ; 1 = wake-up scene before the first frame
god:    .res 1          ; 1 = god mode (G): no damage, ammo or clock
tunon:  .res 1          ; 1 = the tunnel between levels is up (VBI colours)
dsave:  .res 5          ; the player's seed (seedd, seedset) during the demo
tout:   .res 1          ; VBI: clock reached 0:00
mtickv: .res 1          ; music frames per 16th (less when time is short)
espeed: .res 1          ; imp speed this level
trate:  .res 1          ; current turn rate
seedd:  .res 4          ; seed digits 0-9
seedset:.res 1          ; 0 = no seed chosen yet (shows ----)
srreq:  .res 1          ; START pressed (VBI)
rs:     .res 2          ; xorshift state
bestd:  .res 1          ; exit placement
mfr:    .res 1          ; music (VBI): frames until next tick
mord:   .res 4          ; per channel at stride 2 (X = 0 bass, 2 lead)
mdur:   .res 4
mtr:    .res 4
mvol:   .res 4
mpi:    .res 1
fcool:  .res 1          ; weapon refire timer (VBI counts it down)
guncol: .res 1          ; gun colour (the VBI flash restores it)
msnt:   .res 1          ; monster sound: frames left (0 = none; the VBI tests it)
ptmp:   .res 1
dlsel:  .res 1          ; which of the two lists is the spare
amapgen:.res 1
nextmap:.res 1          ; the queued list is a map list (1)
scrmap: .res 1          ; the list on screen is a map list (for the DLI)
gend:   .res 1          ; gradient runs: end row, OR value, table offset
gor:    .res 1
gsd:    .res 1
gss:    .res 1
pcol:   .res 1          ; plot colour mask ($FF = colour 3, $55 = colour 1)
wallc1: .res 1          ; this level's wall colours (lit, shaded)
wallc2: .res 1
msty:   .res 1          ; monster sound: which

.segment "BSS"
health: .res 1
kills:  .res 1
dead:   .res 1
hurt:   .res 1
hurtofs:.res 1
atkcool:.res 1
ei:     .res 1
edxl:   .res 1
edxh:   .res 1
edyl:   .res 1
edyh:   .res 1
rxl:    .res 1
rxh:    .res 1
ryl:    .res 1
ryh:    .res 1
vl:     .res 1
vh:     .res 1
p0:     .res 1
p1:     .res 1
p2:     .res 1
accl:   .res 2          ; [0] = depth, [1] = lateral (8.8 signed)
acch:   .res 2
acos:   .res 1          ; |cos|, |sin| and their signs for this frame
csgn:   .res 1
asin:   .res 1
ssgn:   .res 1
rxs:    .res 1
rys:    .res 1
msnf:   .res 1          ; monster sound: its pitch now
mssx:   .res 1          ; (msplay keeps X here)
trigp:  .res 1          ; the trigger last frame (VBI)
pmcl:   .res 1          ; players 2/3 already hold blank columns (VBI)
latl:   .res 1
lath:   .res 1
lsgn:   .res 1
es:     .res 1
tl:     .res 1
th:     .res 1
exq:    .res 1
sle:    .res 2          ; slot: enemy index
sls:    .res 2          ; slot: scale (0 = empty)
slx:    .res 2          ; slot: centre X' (screen x + 32)
slhpos: .res 2
slsize: .res 2
slcol:  .res 2
slhit:  .res 2
slot:   .res 1
em:     .res 1
ehw:    .res 1
eH:     .res 1
dvlo:   .res 1
dvhi:   .res 1
ebot:   .res 1
rstart: .res 1
dg0:    .res 1
dg1:    .res 1
dg2:    .res 1
level:  .res 1
trigl:  .res 1          ; trigger latched by the VBI
sfl:    .res 1          ; 8.8 sprite scale
sfh:    .res 1
thump:  .res 1          ; hit-sound timer (channel 2), separate from the gun flash
jif:    .res 1          ; level clock (VBI)
secs:   .res 1
mins:   .res 1
lsec:   .res 1
edist:  .res 1
pthr:   .res 1          ; movement dead-zone (positive / negative side)
nthr:   .res 1
nen:    .res 1          ; things this level (imps + pickups)
mstart: .res 1          ; maze generator
sp:     .res 1
cur:    .res 1
cx:     .res 1
cy:     .res 1
nnb:    .res 1
nbdir:  .res 4
cnt:    .res 1
slemp:  .res 2          ; per sprite slot: its staging column is already blank
thr:    .res 1
tries:  .res 1

.segment "ENTRY"
        jmp start               ; image entry point ($7FFD), called by the loader

.segment "CODE"

; =====================================================================
; =====================================================================
.segment "INITA"               ; (boot only: reused after start-up, see RA)
start:
        sei
        lda #0
        sta NMIEN               ; no VBI/DLIs while we rebuild things (the OS VBI
        sta SDMCTL              ; must not see the cartridge come and go)
        sta DMACTL
        lda PORTB               ; built-in BASIC off.  With a cartridge in, the XL
        ora #$02                ; OS leaves it on (unless OPTION is held), and it
        sta PORTB               ; would appear at $A000-$BFFF instead of our RAM
                                ; once the cartridge switches off
        ; ---- image B: cartridge banks 2-3 -> RAM $8000-$BFFF.  The bank shows up
        ;      at $8000, which is also where it has to go, so each bank is staged
        ;      through $2000-$3FFF (a frame buffer, not in use yet).
        lda #IMGB_BANK
        sta cnt
        lda #$80
        sta genh                ; destination page
@ib:    lda cnt
        sta CARTCTL             ; cartridge on, bank cnt at $8000-$9FFF
        lda #$80
        ldx #$20
        jsr copy8k              ; $8000 -> $2000
        lda #$80
        sta CARTCTL             ; cartridge off: $8000-$BFFF is RAM
        lda #$20
        ldx genh
        jsr copy8k              ; $2000 -> destination
        clc
        lda genh
        adc #$20
        sta genh
        inc cnt
        lda cnt
        cmp #IMGB_BANK+2
        bne @ib
        lda TRIG3               ; tell the XL OS the cartridge is gone on
        sta GINTLK              ; purpose (otherwise its VBI locks up)
        jsr osinit              ; (RESET restarts the game)
        cli

        ; ---- clear RAM $0500-$39FF (writers, DLs, HUD, buffers, PMG)
        lda #$05
        sta gptr+1
        lda #0
        sta gptr
        tay
@clr:   sta (gptr),y
        iny
        bne @clr
        inc gptr+1
        ldx gptr+1
        cpx #$3A
        bne @clr

        ; ---- multiply table pointers (high bytes fixed)
        lda #>sqlo
        sta msl+1
        lda #>sqhi
        sta msh+1
        lda #>sqmlo
        sta mml+1
        lda #>sqmhi
        sta mmh+1

        jsr gen_writers
        lda #$FF
        sta pcol
        lda #LODS               ; room walls textured (T toggles)
        sta lods
        lda #$FF                ; band cache empty
        sta kside
        jsr gen_dlists

        ; ---- previous-top arrays: 0 = "redraw the whole column" (the first
        ;      frames paint the ceiling/floor gradient into every buffer)
        ldx #NPAIRS-1
        lda #0
@pv:    sta PREV0,x
        sta PREV1,x
        sta PREV2,x
        dex
        bpl @pv

        ; ---- HUD
        ldx #39
@hud:   lda hudline1,x
        sta HUD,x
        lda hudline3,x
        sta HUD3,x
        lda hudline3+40,x
        sta HUD3+40,x
        dex
        bpl @hud

        ; ---- player missile graphics: gun
        lda #>PMG
        sta PMBASE
        ldx #15
@gun:   lda gungfx,x
        sta P0MEM+GUNTOP,x
        lda handq,x
        sta P1MEM+GUNTOP,x
        dex
        bpl @gun
        lda #1
        sta SIZEP0              ; gun: double width
        lda #3
        sta SIZEP1              ; hand: quad width
        lda #120
        sta HPOSP0
        lda #112
        sta HPOSP1
        lda #0
        sta HPOSP2              ; enemies start hidden
        sta HPOSP3
        lda #$55
        sta SIZEM               ; missiles double width: 4 x 4cc = flash
        jsr gamecolours
        lda #3
        sta GRACTL
                                ; (gcdone follows in INITA)
.segment "RODATA"
; arrows: the automap's player marker, 5 rows of 5 pixels (bits 7-3) for each
;         of 8 directions: east, south-east, south ... north-east (y is down)
arrows:
        .byte %00100000, %00010000, %11111000, %00010000, %00100000
        .byte %10000000, %01000000, %00101000, %00011000, %00111000
        .byte %00100000, %00100000, %10101000, %01110000, %00100000
        .byte %00001000, %00010000, %10100000, %11000000, %11100000
        .byte %00100000, %01000000, %11111000, %01000000, %00100000
        .byte %11100000, %11000000, %10100000, %00010000, %00001000
        .byte %00100000, %01110000, %10101000, %00100000, %00100000
        .byte %00111000, %00011000, %00101000, %01000000, %10000000
.segment "CODE"
; seenear: the 3x3 tiles around you (curl, curh) count as seen, so the
;          automap shows the walls beside you even if you never looked at them
seenear:sec
        lda curl
        sbc #33
        sta gptr
        lda curh
        sbc #0
        and #3
        ora #>SEEN
        sta gptr+1
        ldx #2
@r:     ldy #2
        lda #1
@c:     sta (gptr),y
        dey
        bpl @c
        clc
        lda gptr
        adc #32
        sta gptr
        bcc @n
        inc gptr+1
@n:     dex
        bpl @r
        rts

; pickup_touch: X = pickup thing.  Collect it if you're within 0.4 tiles.
pickup_touch:
        stx ei
        sec
        lda px
        sbc EXL,x
        tay
        lda px+1
        sbc EXH,x
        jsr close
        bcc @far
        ldx ei
        sec
        lda py
        sbc EYL,x
        tay
        lda py+1
        sbc EYH,x
        jsr close
        bcs @take
@far:   ldx ei
        rts
@take:  ldx ei                   ; (nothing is taken while that stat is full)
        ldy ETYP,x
        cpy #PK_AMMO
        bne @t1
        ldx #2                  ; super ammo: full while every gun you have
@sf:    lda owned,x             ;   is full
        beq @sn
        lda ammop,x
        cmp wcap,x
        bcc @t3
@sn:    dex
        bpl @sf
        bmi @fu
@t1:    cpy #PK_HEALTH
        bne @t2
        lda health
        cmp #100
        bcs @fu
        bcc @t3
@t2:    cpy #PK_TIME
        bne @t4
        lda mins
        cmp #T_CAPM
        bcs @fu
        bcc @t3
@t4:    lda pkwpn-PK_AMMO,y     ; a gun's ammo: full while you have that gun
        bmi @t3                 ;   and it's full (the keycard: never)
        tax
        lda owned,x
        beq @t3
        lda ammop,x
        cmp wcap,x
        bcc @t3
        ldy #PK_AMMO            ; (AMMO MAX)
@fu:    jmp pkfull              ; full: say so, leave it there
@t3:    ldx ei
        lda #0
        sta EST,x
        lda #4                  ; blip
        sta thump
        lda ETYP,x
        cmp #PK_AMMO
        bne @n1
        ldx #2                  ; super ammo: every gun full
@sa:    lda wcap,x
        sta ammop,x
        dex
        bpl @sa
        lda #<msg_super
        ldy #>msg_super
        bne @msg
@n1:    cmp #PK_HEALTH
        bne @n2
        clc
        lda health
        adc #HEALTH_PK
        cmp #101
        bcc @h
        lda #100
@h:     sta health
        lda #<msg_health
        ldy #>msg_health
        bne @msg
@n2:    cmp #PK_TIME
        bne @n3
        clc
        lda tadm
        adc #TIME_PK
        sta tadm
        lda #<msg_time
        ldy #>msg_time
        bne @msg
@n3:    cmp #PK_KEY
        bne @gun
        lda #1                  ; the key: the exit opens
        sta havekey
        lda #2
        jsr setdoor
        lda #<msg_gotkey
        ldy #>msg_gotkey
@msg:   jsr showmsg
        jsr drawhud
        ldx ei
        rts
@gun:   tay                     ; a gun (or its ammo: the same picture)
        ldx pkwpn-PK_AMMO,y
        stx pkw
        lda owned,x
        bne @amm
        lda #1                  ; not yours yet: it is now, in your hand,
        sta owned,x             ;   with its first load
        stx weapon
        lda wfirst,x
        jsr addammo
        jsr setgun
        ldx pkw
        lda wmsgl,x
        ldy wmsgh,x
        bne @msg
@amm:   lda thp                 ; ammo: 10 + 2 x this level's imp toughness
        clc                     ;   (thp: in half points), shotgun shells half
        adc #AMMO_PK-5          ;   that, SMG rounds twice that
        cpx #1
        bne @a2
        lsr
@a2:    cpx #2
        bne @af
        asl
@af:    sta dtmp
        jsr addammo
        ldx pkw
        lda wamsl,x
        ldy wamsh,x
        jsr showmsg
        lda dtmp                ; the amount, into the message
        jsr div10
        ldy pkw
        pha
        lda wdig,y
        tay
        pla
        cpx #$10                ; (one digit: no leading 0)
        bne @d2
        sta a:HUD+40,y
        lda #0
        sta a:HUD+40+1,y
        beq @dd
@d2:    sta a:HUD+40+1,y
        txa
        sta a:HUD+40,y
@dd:    jsr drawhud
        ldx ei
        rts

; addammo: gun X's ammo += A, at most what it holds (wcap).  Keeps X.
addammo:clc
        adc ammop,x
        bcs @c
        cmp wcap,x
        bcc @a
@c:     lda wcap,x
@a:     sta ammop,x
        rts

; exitammo: reaching the exit: ammo for each gun you have
exitammo:
        ldx #2
@l:     lda owned,x
        beq @n
        lda wexit,x
        jsr addammo
@n:     dex
        bpl @l
        rts

; pktype: A = a pickup type for placepk.  Ammo (PK_AMMO) is ammo for a gun
;         found on this level or earlier; one roll a level (the last ammo
;         placed) makes it super ammo instead, 1 time in 20, on every level.
pktype: cmp #PK_AMMO
        bne @x
        lda pcnt
        cmp #1
        bne @w
        jsr rnd
        cmp #13                 ; (13 / 256: 5%)
        bcc @s
@w:     jsr rnd
        and #3
        cmp #3
        bcs @w
        tay
        lda level
        cmp wlvl,y
        bcc @w
        lda wpk,y
        rts
@s:     lda #PK_AMMO
@x:     rts

; by gun (pistol, shotgun, SMG)
wpk:    .byte PK_PISTOL, PK_SHOTGUN, PK_CHAIN   ; its ammo pickup
wlvl:   .byte 0, SHOTLEVEL, CHAINLEVEL          ; its ammo is placed from this level
wcap:   .byte 100, 30, 200                      ; the most it holds
wfirst: .byte 0, 10, 40                         ; ammo with the gun when you find it
wexit:  .byte 20, 10, 40                        ; ammo for reaching the exit
wmsgl:  .byte <msg_shotgun, <msg_shotgun, <msg_chain
wmsgh:  .byte >msg_shotgun, >msg_shotgun, >msg_chain
wamsl:  .byte <msg_pammo, <msg_sammo, <msg_mammo
wamsh:  .byte >msg_pammo, >msg_sammo, >msg_mammo
wdig:   .byte PAMDIG, SAMDIG, MAMDIG            ; where the amount goes in those
; pkwpn: by pickup type - PK_AMMO: the gun it's for ($FF: not a gun's)
pkwpn:  .byte $FF, $FF, $FF, 1, 2, $FF, 0

; corpse: X = a dying monster, once a tick.  It falls (ETIM 80-68), lies
;         there, and at DROPAT turns into a health pack or ammo for one of
;         your guns, at random, where it lay.  The keycard's carrier (EHP = $FF) dropped
;         its keycard as it died: its body just fades at 0.
DROPAT  = 48                    ; (32 ticks, 1.6 s, after the kill)
corpse: dec ETIM,x
        beq @gone
        lda ETIM,x
        cmp #DROPAT
        bne @x
        lda EHP,x
        bne @x
        lda RANDOM              ; health, or ammo for a gun you have
        and #1
        bne @h
@w:     lda RANDOM
        and #3
        cmp #3
        bcs @w
        tay
        lda owned,y
        beq @w
        lda wpk,y
        bne @st
@h:     lda #PK_HEALTH
@st:    sta ETYP,x
        lda #1
        sta EST,x
        lda #0
        sta EWAKE,x             ; (not seen yet: off the automap)
@x:     rts
@gone:  lda #0
        sta EST,x
        rts

gamecolours:
        lda #120
        sta HPOSM3
        lda #124
        sta HPOSM2
        lda #128
        sta HPOSM1
        lda #132
        sta HPOSM0
        ldx weapon              ; the colour of the gun in hand (a new level
        lda wcolor,x            ;   used to turn a shotgun or SMG black)
        sta PCOLR0
        sta guncol
        lda #C_HAND
        sta PCOLR1
        lda #C_FLASH
        sta COLOR3

        lda #PRI_STD            ; players over playfield, missiles = 5th player
        sta GPRIOR              ; (the view's DLI switches GTIA mode 9 on)

        ; ---- colour shadows (DLIs also force these each frame)
        lda #C_PF0
        sta COLOR0
        lda #C_PF1
        sta COLOR1
        lda #C_PF2
        sta COLOR2
        lda #0
        sta COLOR4
        rts
.segment "INITA"
gcdone:

        ; ---- sound
        lda #0
        sta AUDCTL
        sta AUDC1
        sta AUDC2

        lda #1
        sta muson               ; music on by default
        jsr music_init
        lda #1
        sta dead

        ; ---- show (blank) buffer 2 first, draw into 0
        lda #1
        sta dlsel
        lda #2
        sta buf
        jsr dlprep
        lda nextdl
        sta SDLSTL
        lda nextdlh
        sta SDLSTL+1
        lda #0
        sta scrmap
        sta buf
        sta pending
        jsr setbuf

        ; ---- interrupts: DLI + deferred VBI
        lda #<dli
        sta VDSLST
        lda #>dli
        sta VDSLST+1
        ldy #<ivbi              ; our own immediate VBI (instead of the OS's;
        ldx #>ivbi              ;   the OS ROM is off: osram.s calls it)
        sty VVBLKI
        stx VVBLKI+1
        lda #$C0
        sta NMIEN
        lda #$2E                ; normal playfield, PM DMA (2-line), DL DMA
        sta SDMCTL
        jmp gomenu

; =====================================================================
.segment "CODE"
mainloop:
        jsr frameck             ; exit found?  automap mark put away?
        jsr ticks               ; the game runs in ticks of 1/20 s, however
@tk:    jsr input               ;   long a frame takes (osram.s): 1-4 of
        jsr pausek              ;   them per frame
        jsr tick
        jsr enemy_ai
        dec ntick
        bne @tk
        lda secs
        cmp lsec
        beq @nt
        sta lsec
        jsr drawtime
@nt:    lda tout                ; clock ran out?
        beq @nto
        lda #0
        sta tout
        lda dead
        bne @nto
        jsr time_up
@nto:   lda amreq               ; SELECT pressed (seen by the VBI)?
        beq @nam
        lda #0
        sta amreq
        jsr toggle_map
@nam:   lda won
        beq @nowin
        jsr do_win
@nowin:
        jsr drawdir
        lda amap
        beq @view
        jsr drawmap             ; automap instead of the 3D view
@wqm:   lda pending
        bne @wqm
        lda #0                  ; no imps over the map
        sta sls
        sta sls+1
        ldx #0
        jsr drawslot
        ldx #1
        jsr drawslot
        jmp @flip
@view:  jsr same                ; the view as on screen?  Then only the
        bcc @cast               ;   sprites are new (osram.s)
        jmp still
@cast:
.ifdef PROF
        lda RTCLOK+2
        sta $0BF8
        lda VCOUNT
        sta $0BF9
.endif
        lda #0
        sta rayi
        ; ---- rays 0, 8, 16 .. 72, 76, 78 and 79 are cast.  The rest lie between
        ;      two known rays: if those hit the same face of the same tile, the
        ;      wall between is that plane, so scale (1/distance), texture column
        ;      and shade are the average of theirs.  Otherwise the ray is cast.
@c8:    jsr castray
        jsr keep
        lda rayi
        clc
        adc #8
        sta rayi
        cmp #80
        bcc @c8
        lda #76
        sta rayi
        jsr castray
        jsr keep
        lda #78
        sta rayi
        jsr castray
        jsr keep
        inc rayi
        jsr castray
        lda ccur
        sta RCC+79
        jsr interp              ; the rest from their neighbours (osram.s)
        jsr firechk             ; (the trigger again, mid-frame)
        jsr dpairs              ; ---- draw the pairs (osram.s)
.ifdef PROF
        lda RTCLOK+2
        sta $0BF0
        lda VCOUNT
        sta $0BF1
.endif
@wq:    lda pending             ; previous frame must be on screen before
        bne @wq                 ; we overwrite the sprite staging
.ifndef NOSPR
        jsr sprites             ; project enemies into the staging buffers
.endif
.ifdef PROF
        lda RTCLOK+2
        sta $0BF2
        lda VCOUNT
        sta $0BF3
.endif

@flip:  lda #$2E                ; (screen on: dark after the menu until now)
        sta SDMCTL
        ; ---- hand the finished buffer to the VBI, which flips it in
        ; together with the sprites.  Triple buffering: the next buffer
        ; is neither on screen nor queued, so we can start at once.
        jsr dlprep              ; the spare list now shows this buffer
        lda intro               ; a new run: wake up first (overlay code)
        beq @ni
        jsr INTRO
@ni:    lda #1
        sta pending
        ldx buf
        stx shownb
        inx
        cpx #3
        bcc @b
        ldx #0
@b:     stx buf
        jsr setbuf
        inc fcount
        lda #0
        sta ATRACT
        jmp mainloop


; =====================================================================
; Display lists.  The game's (GTIA mode 9 view) are fixed, one per frame
; buffer, in the RAM under the OS (osram.s).  The automap uses two small
; mode D lists (MDLA, MDLB) built here, which take turns.
;   DLIs: top bar colours / view on (GTIA 9) / view off (text colours).
GDL_ROWS = 8                    ; offset of line 0's LMS high byte
.segment "INITA"
gen_dlists:
        ; ---- map lists: mode D, 64 lines from one LMS
        ldx #1
@m:     stx tmp2
        lda mdllo,x
        sta gptr
        lda #>MDLA
        sta gptr+1
        jsr dlhead
        lda #$4D
        jsr dput
        lda #0
        jsr dput
        lda #$10
        jsr dput
        ldx #62
        lda #$0D
@m2:    jsr dput
        dex
        bne @m2
        lda #$8D                ; last line + DLI
        jsr dput
        jsr dltail
        ldx tmp2
        dex
        bpl @m
        rts
; dput: store A at (gptr),Y and step on (across pages)
dput:   sta (gptr),y
        iny
        bne @x
        inc gptr+1
@x:     rts
; dlhead: blank, DLI, top bar.  Y = 0 in, Y = next out.
dlhead: ldy #0
        lda #$70
        jsr dput
        lda #$F0                ; blank 8 + DLI: top bar colours
        jsr dput
        lda #$42
        jsr dput
        lda #<HUD3
        jsr dput
        lda #>HUD3
        jsr dput
        lda #$82                ; second top line + DLI: the view
        jsr dput
        rts
; dltail: bottom bar, then JVB to the list's own start (gptr may have moved
;         on by a page: recompute from the tables)
dltail: lda #$42
        jsr dput
        lda #<HUD
        jsr dput
        lda #>HUD
        jsr dput
        lda #$02
        jsr dput
        lda #$41
        jsr dput
        ldx tmp2
        lda mdllo,x
        jsr dput
        lda #>MDLA
        sta (gptr),y
        rts
.segment "CODE"
gdlo:   .byte <gdl0, <gdl1, <gdl2
gdhi:   .byte >gdl0, >gdl1, >gdl2
; rowhi: display row r (0-63, a pair of scanlines) -> the high byte of its
;   buffer row's offset (rows 32-63 mirror 31-0; VROWS rows are drawn).  For
;   the wake-up's eyelids, which rewrite the shown list (menu.s: lid).
rowhi:  .repeat 64, r
        .if r < 32
        .byte ((r * VROWS / 32) * 40) >> 8
        .else
        .byte (((63 - r) * VROWS / 32) * 40) >> 8
        .endif
        .endrepeat
mdllo:  .byte <MDLA, <MDLB

; dlprep: point the spare list at buffer `buf` (game or map list), and
;         queue it (nextdl) for the VBI
dlprep: lda dlsel
        eor #1
        sta dlsel
        tay
        ldx buf
        lda bufhi,x
        sta tmp
        lda amap
        sta nextmap
        bne @map
        lda gdlo,x              ; (each buffer has its own list: osram.s)
        sta nextdl
        lda gdhi,x
        sta nextdlh
        rts
@map:   lda mdllo,y
        sta nextdl
        sta gptr
        lda #>MDLA
        sta nextdlh
        sta gptr+1
        ldy #GDL_ROWS
        lda tmp
        sta (gptr),y
        rts

; copy8k: 32 pages from page A to page X
; gomenu: (from anywhere) the main menu, then a new game or the demo
gomenu: ldx #$FF
        txs
        lda #1
        sta dead                ; (clock stopped)
        lda #0
        sta paused
@w:     lda pending
        bne @w
        lda demo                ; after the demo: the player's seed back
        beq @nd
        ldx #4
@r:     lda dsave,x
        sta seedd,x
        dex
        bpl @r
@nd:    jsr ovload
        jsr MENU
        sta demo
        beq @pl
        ldx #4                  ; the demo plays a random seed
@s:     lda seedd,x
        sta dsave,x
        dex
        bpl @s
        jsr randseed
@pl:    lda #$FF
        sta CH
        lda #0
        sta srreq
        sta amreq
        sta SDMCTL              ; dark until the first frame is drawn
        jsr gamecolours
        lda #1                  ; gun back, map off, full redraw
        sta amap
        jsr toggle_map
        jsr reset_game
        jsr showseed
        lda demo
        bne @dm
        lda #1                  ; the wake-up scene: its code is in the
        sta intro               ;   overlay under buffer 0, so the first
        tax                     ;   frame goes to buffer 1
        stx buf
        jsr setbuf
        jmp mainloop
@dm:    jsr BOTINIT
        jsr showlevel
        jmp mainloop

; ovload: the overlay (menu, demo bot, banner) from cartridge bank 4 to
;         RAM $1000-$1AFF.  Runs from image A: the cartridge covers $8000+.
OVL_BANK = 4
ovload: lda #OVL_BANK
ovloadb:ldx #0                  ; (A = bank: 5 is the ending)
        stx NMIEN               ; (interrupts would read under the cartridge)
        stx DMACTL
        sta CARTCTL
        lda #$80
        sta sptr+1
        lda #$10
        sta gptr+1
        ldy #0
        sty sptr
        sty gptr
        ldx #11
@c:     lda (sptr),y
        sta (gptr),y
        iny
        bne @c
        inc sptr+1
        inc gptr+1
        dex
        bne @c
        lda #$80                ; cartridge off again
        sta CARTCTL
        lda #$C0
        sta NMIEN
        rts

.segment "INITA"
copy8k: sta sptr+1
        stx gptr+1
        ldy #0
        sty sptr
        sty gptr
        ldx #$20
@c:     lda (sptr),y
        sta (gptr),y
        iny
        bne @c
        inc sptr+1
        inc gptr+1
        dex
        bne @c
        rts

; ---------------------------------------------------------------------
.segment "CODE"
; setbuf: point writer/prev pointers at back buffer `buf`
setbuf:
        lda #0
        sta cpptr
        ldx buf
        lda cwhi,x
        sta cpptr+1
        sta jptr+1
        lda prevlo,x
        sta prevptr
        lda #>PREV0
        sta prevptr+1
        rts
cwhi:   .byte >CW0, >CW1, >CW2
prevlo: .byte <PREV0, <PREV1, <PREV2

; =====================================================================
; DLI: VCOUNT-indexed. <16 = top of view, >=79 = HUD, else gradient band
dli:    pha
        txa
        pha
        ldx VCOUNT
        cpx #VTOP-4             ; top bar
        bcc @hud
        cpx #VTOP               ; after the view: GTIA off, text colours
        bcs @off
        lda scrmap
        bne @map
        lda hurtofs             ; the view's hue: red when hurt, else the level's
        beq @lv
        lda #$40
        bne @hu
@lv:    lda wallc1
@hu:    ldx #PRI_GT9
        sta WSYNC
        sta COLBK
        stx PRIOR
        pla
        tax
        pla
        rti
@map:   lda #0                  ; automap: black background, map colours
        sta WSYNC
        sta COLBK
        lda #C_MDOOR
        sta COLPF0
        lda #C_MWALL
        sta COLPF1
        lda #C_MYOU
        sta COLPF2
        pla
        tax
        pla
        rti
@off:
        lda #PRI_STD
        sta WSYNC
        sta PRIOR
@hud:   lda #$32
        sta WSYNC
        sta COLPF2
        lda #0
        sta COLBK
        lda #$0E
        sta COLPF1
        pla
        tax
        pla
        rti

dlipr = @hu                     ; (the tunnel patches the view's mode to 10)

; =====================================================================
; ivbi: replaces the OS vertical-blank work with just what the game uses:
;       the clock, the shadow registers it writes (colours, display list,
;       DMA, priority), the joystick and trigger, and the keyboard debounce.
;       No attract mode, no SIO timers.  Then the game's own VBI.
ivbi:   inc RTCLOK+2
        bne @r
        inc RTCLOK+1
        bne @r
        inc RTCLOK
@r:     ldx #8                  ; PCOLR0-3, COLOR0-4
@c:     lda PCOLR0,x
        sta COLPM0,x
        dex
        bpl @c
        lda SDMCTL
        sta DMACTL
        lda GPRIOR
        sta PRIOR
        lda SDLSTL
        sta DLISTL
        lda SDLSTL+1
        sta DLISTL+1
        lda PORTA
        and #15
        sta STICK0
        lda TRIG0
        sta STRIG0
        lda KEYDEL
        beq vbi
        dec KEYDEL
        ; fall through

; =====================================================================
; deferred VBI: gun flash + shot sound
vbi:    lda tunon               ; the tunnel between levels: its colours
        beq @tn
        jsr tunvbi
@tn:    ; ---- countdown clock.  The main program never writes the clock: it
        ;      bumps tadm, and only this handler applies the difference.
        lda tadm
        sec
        sbc tadv
        beq @nadd
        clc
        adc secs
@sx:    cmp #60
        bcc @s60
        sbc #60
        ldx mins
        cpx #99
        bcs @cap
        inc mins
        bne @sx
@cap:   lda #59
@s60:   sta secs
        lda mins                ; the clock never holds more than T_CAPM:00
        cmp #T_CAPM
        bcc @cok
        lda #T_CAPM
        sta mins
        lda #0
        sta secs
@cok:   lda tadm
        sta tadv
        lda #$FF                ; (the main loop redraws the clock)
        sta lsec
@nadd:  lda #0                  ; clock not inverted unless blinking
        sta tinv
        lda MBUF+MT_TICK        ; normal tempo unless time is short
        sta mtickv
        lda dead
        ora paused
        ora god                 ; (god mode: the clock holds)
        bne @nt0
        lda mins
        ora secs
        beq @nt0                ; already 0:00
        inc jif
        lda jif
        cmp #60
        bcc @cue
        lda #0
        sta jif
        lda secs
        bne @ds
        lda #60
        sta secs
        dec mins
@ds:    dec secs
        lda mins
        ora secs
        bne @cue
        lda #1                  ; time's up: the main loop ends the game
        sta tout
@cue:   lda mins                ; ---- pressure cues
        bne @nt0
        lda secs
        cmp #T_BLINK
        bcs @nt0
        lda jif                 ; clock blinks: inverse for half of each second
        cmp #30
        bcs @nb
        lda #$80
        sta tinv
@nb:    lda secs
        cmp #T_PANIC
        bcs @nt0
        lda MBUF+MT_FAST        ; music races
        sta mtickv
        lda secs
        cmp #T_FLASH
        bcs @nt0
        lda jif
        bne @nk
        lda #3                  ; tick each second
        sta thump
@nk:
@nt0:   ldx #4                  ; the clock's 5 characters, inverted or not
@blk:   lda a:HUD3+TIMEPOS,x
        and #$7F
        ora tinv
        sta a:HUD3+TIMEPOS,x
        dex
        bpl @blk
        lda CONSOL              ; console keys: 0 = pressed
        eor #7
        and #7
        tax
        eor cprev
        stx cprev
        and cprev               ; newly pressed
        tax
        and #2                  ; SELECT -> automap request
        beq @ns
        lda #1
        sta amreq
@ns:    txa
        lsr                     ; START -> new random seed (title/game over)
        bcc @nst
        lda #1
        sta srreq
@nst:   txa
        and #4                  ; OPTION -> music on/off
        beq @nop
        lda muson
        eor #1
        sta muson
@nop:   lda STRIG0              ; every 1/60 s: a fresh press (up last frame,
        cmp trigp               ;   down now) is latched until the game
        sta trigp               ;   fires it, so no tap is ever lost
        bcs @nt
        inc trigl
@nt:    lda pending
        beq @nf
        lda nextdl              ; flip the frame buffer and the sprites together
        sta SDLSTL
        sta DLISTL
        lda nextdlh
        sta SDLSTL+1
        sta DLISTL+1
        lda nextmap
        sta scrmap
        jsr sprcopy
        lda #0
        sta pending
@nf:    lda paused              ; (paused: no music or sound)
        beq @nf2
        jmp XITVBV
@nf2:   jsr music               ; after the time-critical flip
        lda thump
        beq @nth
        dec thump
        lda thump
        asl
        ora #$C0                ; buzzy 4-bit poly, volume = 2*thump
        sta AUDC2
        lda #8
        sec
        sbc thump
        asl
        asl
        asl
        ora #$C0                ; pitch drops as it fades
        sta AUDF2
@nth:
        lda fcool               ; weapon refire timer
        beq @fc
        dec fcool
@fc:    lda flash
        beq @idle
        dec flash
        lda flash               ; distortion 0 (noise): loud, (flash + 15) / 2
        beq @fz
        clc
        adc #15
        lsr
@fz:    sta AUDC1
        lda flash
        asl
        asl
        asl
        eor #$FF
        sta AUDF1               ; pitch drops as it fades
        lda flash
        cmp #6
        bcc @nof
        ldx #7
@fl:    lda flashgfx,x
        sta MISMEM+GUNTOP-8,x
        dex
        bpl @fl
        lda #C_GUNHI
        sta PCOLR0
        jmp XITVBV
@nof:   ldx #7
        lda #0
@cl:    sta MISMEM+GUNTOP-8,x
        dex
        bpl @cl
        lda guncol
        sta PCOLR0
@idle:  lda msnt                ; a monster's sound on channel 1 (when the
        beq @q                  ;   gun isn't using it)
        jmp msnd
@q:     jmp XITVBV

; =====================================================================
; Music (runs in the VBI).  Original tune; see the song in gentables.py.
; =====================================================================

.segment "INITA"
music_init:
        ldx #2
@i:     lda #0
        sta mord,x
        sta mvol,x
        sta mtr,x
        lda #1
        sta mdur,x
        lda #<mend              ; first tick reads an end marker -> loads bar 1
        sta mptr,x
        lda #>mend
        sta mptr+1,x
        dex
        dex
        bpl @i
        lda #0
        sta mfr
        rts
.segment "CODE"
mend:   .byte $FF

music:  lda muson
        bne @on
        sta AUDC3
        sta AUDC4
        rts
@on:    dec mfr
        bpl @env
        lda mtickv
        sta mfr
        ldx #0
        jsr mtick
        ldx #2
        jsr mtick
        jsr mdrum
@env:   lda mvol                ; bass: decays 1 step per frame to its floor
        cmp MBUF+MT_BFLOOR
        bcc @b
        beq @b
        dec mvol
@b:     lda RTCLOK+2            ; lead: 1 step every 2/4/8 frames, to its floor
        and MBUF+MT_LRATE
        bne @l
        lda mvol+2
        cmp MBUF+MT_LFLOOR
        bcc @l
        beq @l
        dec mvol+2
@l:     lda mvol
        beq @b0
        ora MBUF+MT_BDIST       ; (the track's tone: pure, or buzzy)
@b0:    sta AUDC3
        lda mvol+2
        beq @l0
        ora MBUF+MT_LDIST
@l0:    sta AUDC4
        rts

; mdrum: once a 16th: the track's drum step, on the hit-sound channel
mdrum:  inc mstep
        lda mstep
        and #15
        tay
        lda MBUF+MT_DRUM,y
        beq @x
        cmp thump               ; (never cut a louder sound short)
        bcc @x
        sta thump
@x:     rts



; mtick: X = 0 (bass) / 2 (lead); advance one 16th note
mtick:  dec mdur,x
        beq @ev
        rts
@ev:    lda (mptr,x)
        cmp #$FF
        bne @note
        jsr mnext               ; end of bar: next entry in the order list
        jmp @ev
@note:  inc mptr,x
        bne @n1
        inc mptr+1,x
@n1:    tay                     ; note (0 = rest)
        lda (mptr,x)
        sta mdur,x
        inc mptr,x
        bne @n2
        inc mptr+1,x
@n2:    tya
        beq @rest
        clc
        adc mtr,x
        tay
        lda mfreq-1,y           ; lead: the pure-tone table
        cpx #0
        bne @lf
        lda MBUF+MT_BFREQ-1,y   ; bass: the track's own 16 notes
@lf:    sta AUDF3,x             ; AUDF3 / AUDF4 are 2 apart, like X
        lda mattack,x
        sta mvol,x
        rts
@rest:  lda #0
        sta mvol,x
        rts

mnext:  ldy mord,x
        cpx #0
        bne @ld
        lda mordb,y
        cmp #$FF
        bne @bo
        ldy #0                  ; loop the song
        lda mordb,y
@bo:    sta mpi
        lda mordb+1,y
        jmp @set
@ld:    lda mordl,y
        cmp #$FF
        bne @lo
        ldy #0
        lda mordl,y
@lo:    sta mpi
        lda mordl+1,y
@set:   sta mtr,x
        iny
        iny
        tya
        sta mord,x
        ldy mpi
        lda mplo,y
        sta mptr,x
        lda mphi,y
        sta mptr+1,x
        rts

; =====================================================================
; input: turn, move with collision, fire
input:
        lda dead
        beq @alive
        rts
@alive: lda demo                ; the demo: the bot holds the stick
        beq @rs
        jsr BOT
        jmp @st
@rs:    lda STICK0
@st:    sta stick
        and #12                 ; left or right held? ramp the turn rate
        cmp #12
        bne @tr
        lda #TURN0-TURNUP       ; released: next press starts slow
        sta trate
        bne @t0
@tr:    lda trate
        clc
        adc #TURNUP
        cmp #TURNMAX+1
        bcc @t1
        lda #TURNMAX
@t1:    sta trate
@t0:    lda stick
        and #4
        bne @nl
        sec
        lda pa
        sbc trate
        sta pa
        lda pa+1
        sbc #0
        and #3
        sta pa+1
@nl:    lda stick
        and #8
        bne @nr
        clc
        lda pa
        adc trate
        sta pa
        lda pa+1
        adc #0
        and #3
        sta pa+1
@nr:    ; movement table index = pa >> 2
        lda pa+1
        sta tmp
        lda pa
        lsr tmp
        ror
        lsr tmp
        ror
        tax
        lda stick
        and #1
        bne @nu
        lda movxl,x
        sta mdxl
        lda movxh,x
        sta mdxh
        lda movyl,x
        sta mdyl
        lda movyh,x
        sta mdyh
        jsr trymove
        jmp @fire
@nu:    lda stick
        and #2
        bne @fire
        sec
        lda #0
        sbc movxl,x
        sta mdxl
        lda #0
        sbc movxh,x
        sta mdxh
        sec
        lda #0
        sbc movyl,x
        sta mdyl
        lda #0
        sbc movyh,x
        sta mdyh
        jsr trymove
@fire:  lda CH                  ; weapon keys 1-3
        cmp #$FF
        beq firechk
        ldx #$FF
        stx CH
        and #$3F
        cmp #$2D                ; T: textures on/off
        bne @np
        jsr textoggle
        jmp firechk
@np:    cmp #$0A                ; P: pause
        bne @nm
        jsr pause
        jmp firechk
@nm:    cmp #$25                ; M: automap (as SELECT)
        bne @nk
        ldx #1
        stx amreq
        jmp firechk
@nk:    cmp #$3E                ; S: music on/off (as OPTION)
        bne @nt
        lda muson
        eor #1
        sta muson
        jmp firechk
@nt:    jsr CHEAT               ; G: god mode, L: level select (keeps A)
        ldx #2
@wk:    cmp wkeys,x
        beq @sel
        dex
        bpl @wk
        bmi firechk
@sel:   jsr selweapon
        ; fall through
; firechk: shoot if the trigger says so.  Twice a frame (input, and again
;          between casting and drawing) so a press waits less.
firechk:lda amap                ; no shooting while the map is up (and no
        beq @fc                 ;   press saved for later)
        lda #0
        sta trigl
        rts
@fc:    lda fcool               ; still recovering from the last shot: a press
        bne @done               ;   stays latched and fires when it's over
        jsr readfire
        bne @done
        ldx weapon
        lda ammop,x
        cmp wcost,x
        bcc @empty
        sbc wcost,x
        ldy god                 ; (god mode: ammo never runs down)
        bne @ga
        sta ammop,x
@ga:
        lda wcool,x
        sta fcool
        lda wflash,x
        sta flash
        jsr drawhud
        jmp hitscan
@done:  rts
@empty: lda #<msg_empty
        ldy #>msg_empty
        jmp showmsg

; ---------------------------------------------------------------------


; ---------------------------------------------------------------------
; trymove: apply (mdx, mdy) per axis if the probe tile is open
trymove:
        ; ---- X axis
        clc
        lda px
        adc mdxl
        sta nxl
        lda px+1
        adc mdxh
        sta nxh
        lda mdxh
        bmi @xn
        clc
        lda nxl
        adc #MARGIN
        lda nxh
        adc #0
        jmp @xp
@xn:    sec
        lda nxl
        sbc #MARGIN
        lda nxh
        sbc #0
@xp:    tay                     ; probe tile x
        lda py+1
        jsr tileval
        beq @xok
        cmp #2
        beq @xd
        cmp #4
        bne @y
@xd:    jmp touchdoor
@xok:   lda nxl
        sta px
        lda nxh
        sta px+1
@y:     ; ---- Y axis
        clc
        lda py
        adc mdyl
        sta nxl
        lda py+1
        adc mdyh
        sta nxh
        lda mdyh
        bmi @yn
        clc
        lda nxl
        adc #MARGIN
        lda nxh
        adc #0
        jmp @yp
@yn:    sec
        lda nxl
        sbc #MARGIN
        lda nxh
        sbc #0
@yp:    ldy px+1                ; probe tile y
        jsr tileval
        beq @yok
        cmp #2
        beq @yd
        cmp #4
        bne @ret
@yd:    jmp touchdoor
@yok:   lda nxl
        sta py
        lda nxh
        sta py+1
@ret:   rts

; tileval: A = row (0-31), Y = column -> A = map tile, Z set if open.
;          Keeps X.
tileval:sty tcol
        pha
        lsr
        lsr
        lsr
        ora #>map
        sta tvp+1
        pla
        asl
        asl
        asl
        asl
        asl
        ora tcol
        tay
        lda #0
        sta tvp
        lda (tvp),y
        rts

; =====================================================================
; multiply helpers (quarter squares).  setmul: A = a.  mul8: Y = b
setmul: sta msl
        sta msh
        eor #$FF
        sta mml
        sta mmh
        rts


; =====================================================================
; castray: ray `rayi` -> hcur (half height rows 0-32), ccur (colour 1-3)
; keep: after castray: the ray's shade, and (even rays) what it hit
keep:   ldx rayi
        lda ccur
        sta RCC,x
keepid: lda rayi
        lsr
        tax
        lda hitlo
        sta RIDL,x
        lda hitid
        sta RIDH,x
        rts

; tryint: ray rayi lies between rays rl and rr.  If both hit the same face of
;         the same tile (and are both textured or both not), average them;
;         else cast it.  hitlo / hitid = what it hit, either way.
tryint: lda rl
        lsr
        tax
        lda rr
        lsr
        tay
        lda RIDL,x
        cmp RIDL,y
        bne @cast
        lda RIDH,x
        cmp RIDH,y
        bne @cast
        sta hitid
        lda RIDL,x
        sta hitlo
        ldx rl
        ldy rr
        lda ZB,x
        cmp lods
        ror tmp
        lda ZB,y
        cmp lods
        ror
        eor tmp
        bmi @cast
        clc
        lda RCC,x
        adc RCC,y
        lsr
        sta tmp
        clc
        lda TID,x
        adc TID,y
        ror
        pha
        clc
        lda ZB,x
        adc ZB,y
        ror
        ldx rayi
        sta ZB,x
        pla
        sta TID,x
        lda tmp
        sta RCC,x
        rts
@cast:  jsr castray
        ldx rayi
        lda ccur
        sta RCC,x
        rts

castray:
        ldx rayi
        clc
        lda pa
        adc offlo,x
        sta ra
        lda pa+1
        adc offhi,x
        and #3
        sta quad
        tax
        ldy ra
        txa
        lsr
        bcs @odd
        lda invcl,y
        sta dxl
        lda invch,y
        sta dxh
        lda invsl,y
        sta dyl
        lda invsh,y
        sta dyh
        jmp @gotd
@odd:   lda invsl,y
        sta dxl
        lda invsh,y
        sta dxh
        lda invcl,y
        sta dyl
        lda invch,y
        sta dyh
@gotd:  lda stxtab,x
        sta stepx
        lda stytab,x
        sta stepy

        ; ---- side distance X = frac * deltaX
        lda px
        ldy stepx
        bmi @fx
        eor #$FF
@fx:    SETMUL
        ldy dxl
        MUL8
        lda prodh
        sta tmp
        ldy dxh
        MUL8
        clc
        lda prodl
        adc tmp
        sta sxl
        lda prodh
        adc #0
        sta sxh
        lda stepx               ; stepping +x: distance is (256-frac)*d,
        bmi @sdx                ; we computed (255-frac)*d, so add d/256
        clc
        lda sxl
        adc dxh
        sta sxl
        bcc @sdx
        inc sxh
@sdx:
        ; ---- side distance Y
        lda py
        ldy stepy
        bmi @fy
        eor #$FF
@fy:    SETMUL
        ldy dyl
        MUL8
        lda prodh
        sta tmp
        ldy dyh
        MUL8
        clc
        lda prodl
        adc tmp
        sta syl
        lda prodh
        adc #0
        sta syh
        lda stepy
        bmi @sdy
        clc
        lda syl
        adc dyh
        sta syl
        bcc @sdy
        inc syh
@sdy:

        ; ---- map index (kept in X through the DDA); x steps are INX/DEX,
        ;      patched per ray
        lda stepx
        bmi @dx
        lda #$E8                ; INX
        bne @dp
@dx:    lda #$CA                ; DEX
@dp:    sta @sxop
        lda py+1                ; map page of the start tile, patched into
        lsr                     ;   both loads (rays cross pages on y steps)
        lsr
        lsr
        ora #>map
        sta @lx+2
        sta @ly+2
        lda stepy               ; a y step crosses a page: +32 carries,
        bmi @ym                 ;   -32 (+$E0) doesn't carry
        lda #$B0                ; BCS
        bne @yb
@ym:    lda #$90                ; BCC
@yb:    sta @ybr
        lda py+1
        asl
        asl
        asl
        asl
        asl
        ora px+1
        tax

        ; ---- DDA
@dda:   lda sxh
        cmp syh
        bcc @sx
        bne @sy
        lda sxl
        cmp syl
        bcs @sy
@sx:
@sxop:  inx
@lx:    lda map,x
        bne @hitx
        clc
        lda sxl
        adc dxl
        sta sxl
        lda sxh
        adc dxh
        sta sxh
        bcc @dda
        lda #$FF
        sta sxl
        sta sxh
        bne @dda
@sy:    txa
        clc
        adc stepy
        tax
@ybr:   bcs @pg                 ; (patched: page change)
@ly:    lda map,x
        bne @hity
        clc
        lda syl
        adc dyl
        sta syl
        lda syh
        adc dyh
        sta syh
        bcc @dda
        lda #$FF
        sta syl
        sta syh
        bne @dda
@pg:    lda stepy
        bmi @pd
        inc @lx+2
        inc @ly+2
        jmp @ly
@pd:    dec @lx+2
        dec @ly+2
        jmp @ly
@hitx:  sta hitv
        lda @lx+2               ; automap: this wall has been seen
        eor #(>map ^ >SEEN)
        sta @sv1+2
        lda #1
@sv1:   sta SEEN,x
        lda sxl
        sta distl
        lda sxh
        sta disth
        lda #0
        sta hitside
        beq @hit
@hity:  sta hitv
        lda @lx+2
        eor #(>map ^ >SEEN)
        sta @sv2+2
        lda #1
@sv2:   sta SEEN,x
        lda syl
        sta distl
        lda syh
        sta disth
        lda #1
        sta hitside

        ; ---- fisheye correction: perp = dist * cos(offset)
@hit:   stx hitlo               ; what was hit: tile and face (for the
        lda @lx+2               ;   ray interpolation)
        asl
        ora hitside
        sta hitid
        ldx rayi
        lda cosfix,x
        SETMUL
        ldy distl
        MUL8
        lda prodh
        sta tmp
        ldy disth
        MUL8
        clc
        lda prodl
        adc tmp
        sta pl
        lda prodh
        adc #0
        sta ph

        ; ---- scale lookup -> depth buffer, wall height = min(scale, 32)
        jsr scale_of
        ldx rayi
        sta ZB,x
        cmp #33
        bcc @gh
        lda #32
@gh:    sta hcur
        lda hitv
        asl
        ora hitside
        tax
        lda coltab,x            ; 0 wall (fogged), 1 exit (glows), 2 locked exit
        beq @fog
        tay
        lda doorlum-1,y
        jmp @cc
@fog:   ldy rayi
        lda ZB,y
        lsr
        lsr
        tay
        lda hitside
        bne @shd
        lda fogl,y
        jmp @cc
@shd:   lda fogs,y
@cc:    sta ccur
        ldy rayi                ; far walls are drawn solid: no texture column
        lda ZB,y
        cmp lods
        bcs @tx
        rts
@tx:    lda hitid               ; (textured: bit 7 of the hit id, so rays
        ora #$80                ;   either side of the texture distance
        sta hitid               ;   never interpolate)
        lda texbase,x
        sta tmp2
        beq @tx1                ; corridor hull: the same down every column
        cmp #$FF
        bne @tx2
@tx1:   ldx rayi
        sta TID,x
        rts
@tx2:
        ; ---- texture column: how far along the wall the ray hit.
        ;      offset = dist x |dir| along the wall (s.7), added to the start
        ;      coordinate's fraction; sin or cos depending on side and quadrant
        ldy ra
        lda quad
        and #1
        eor hitside
        bne @uc
        tya                     ; sin(a) = cos(256 - a): qcos[255 - a + 1]
        eor #$FF
        tay
        lda qcos+1,y
        jmp @um
@uc:    lda qcos,y
@um:    SETMUL
        lda disth
        bne @far
        ldy distl               ; under a tile: offset = distl x m >> 7
        MUL8
        lda prodh
        asl prodl
        rol
        jmp @off
@far:   cmp #8                  ; (drawn solid that far anyway)
        bcs @far8
        lsr                     ; distance as 3.5: (disth:distl) >> 3
        ror distl
        lsr
        ror distl
        lsr
        ror distl
        ora distl
        tay
        MUL8                    ; offset = d35 x m >> 4
        lda prodl
        lsr prodh
        ror
        lsr prodh
        ror
        lsr prodh
        ror
        lsr prodh
        ror
        jmp @off
@far8:  lda #0
@off:   sta tmp                 ; offset fraction
        lda hitside
        bne @ux
        lda py
        ldy stepy
        jmp @us
@ux:    lda px
        ldy stepx
@us:    cpy #$80
        bcs @un
        clc
        adc tmp
        jmp @uu
@un:    sec
        sbc tmp
@uu:    lsr
        lsr
        lsr
        lsr
        ldy tmp2                ; the exit's stripes: mirrored on the tiles west
        cpy #HAZID              ;   and north of it, so they point at the door
        bne @ua
        tay
        lda hitid
        and #$7E
        ldx hitlo
        cpx mirl
        bne @m2
        cmp mirp
        beq @mr
@m2:    cpx mirl+1
        bne @mn
        cmp mirp+1
        bne @mn
@mr:    tya
        ora #HZMID
        bne @st
@mn:    tya
@ua:    clc
        adc tmp2
@st:    ldx rayi
        sta TID,x
        rts

; by tile*2+side: 1 (and spare 3) corridor hull, 2 and 4 doors; 5-9 and 11-15
; room styles, 10 the stripes around the exit.  $FF would be a solid wall.
texbase:.byte 0, 0, 0, 0, $FF, $FF, 16, 16, 16, 16   ; (open exit: plain glow; 3: entrance)
        .byte 32, 32, 48, 48, 64, 64, 80, 80, 96, 96, 112, 112
        .byte 128, 128, 144, 144, 160, 160, 176, 176, 192, 192

stxtab: .byte 1, $FF, $FF, 1
stytab: .byte 32, 32, $E0, $E0          ; +y for quadrants 0-1 (angles 0-180)
shl6:   .byte 0, 64, 128, 192
; colour code by (tile*2 + side): tile1 lit/shaded, tile2 = door
coltab: .byte 0, 0, 0, 0, 1, 1, 2, 2, 2, 2   ; 0 wall, 1 exit, 2 locked exit / entrance
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
doorlum:.byte 15, 3                         ; exit: glowing / locked: dark

; =====================================================================
; Wall columns: dpairs (osram.s) draws them.  mkruns turns the 8 texture
; bands of a pair into runs (equal neighbours merged).
rkt:    .repeat NBAND - 1, k
        .byte (>bendt) + k
        .endrepeat
; mkruns: bands -> runs (equal neighbours merged): rt/rb values, rk = the
;         page of bendt for the end band (0 for the last run).  Keeps X.
mkruns: stx tmp
        ldx #0
        stx rdirty
        ldy #0
@l:     cpy #NBAND-1
        beq @last
        lda bt,y
        cmp bt+1,y
        bne @e
        lda bb,y
        cmp bb+1,y
        beq @n
@e:     lda bt,y
        sta rt,x
        lda bb,y
        sta rb,x
        lda rkt,y               ; (band + 1)'s table
        sta rk,x
        inx
@n:     iny
        bne @l
@last:  lda bt+NBAND-1
        sta rt,x
        lda bb+NBAND-1
        sta rb,x
        lda #0
        sta rk,x
        ldx tmp
        rts

; =====================================================================
; scale_of: (ph,pl) perpendicular distance 8.8 -> A = scale (0-255),
;           and sfh:sfl = the same scale in 8.8
scale_of:
        lda ph
        cmp #4
        bcs @far
        tay
        lda pl
        lsr
        lsr
        ora shl6,y
        tax
        lda s88la,x
        sta sfl
        lda s88ha,x
        sta sfh
        jmp @rnd
@far:   cmp #32
        bcc @f2
        lda #0
        sta sfl
        sta sfh
        rts
@f2:    asl
        asl
        asl
        sta tmp
        lda pl
        lsr
        lsr
        lsr
        lsr
        lsr
        ora tmp
        tax
        lda s88lb,x
        sta sfl
        lda s88hb,x
        sta sfh
@rnd:   lda sfl                 ; integer scale = round(8.8 scale), max 255
        asl
        lda sfh
        adc #0
        bcc @x
        lda #255
@x:     rts

; getcos: A = angle bits 9-8, gptr = bits 7-0  ->  A = cos (s.7)
;         (half-circle table: cos(a + 512) = -cos(a))
getcos: and #3
        sta tmp
        and #1
        clc
        adc #>cs9
        sta gptr+1
        ldy #0
        lda (gptr),y
        ldy tmp
        cpy #2
        bcc @p
        eor #$FF
        clc
        adc #1
@p:     and #$FF                ; return with N/Z set from the result
        rts

; =====================================================================

; pmul: (p1,p2) = (vl,vh) * a >> 7, all unsigned
pmul:   ldy vl
        MUL8
        lda prodl
        sta p0
        lda prodh
        sta p1
        ldy vh
        MUL8
        clc
        lda prodl
        adc p1
        sta p1
        lda prodh
        adc #0
        sta p2
        asl p0
        rol p1
        rol p2
        rts

; addp: acc[X] += (A bit 7 ? -p : +p)
; (tests A itself: callers load X after A, which clobbers the N flag)
addp:   cmp #$80
        bcs @sub
        clc
        lda accl,x
        adc p1
        sta accl,x
        lda acch,x
        adc p2
        sta acch,x
        rts
@sub:   sec
        lda accl,x
        sbc p1
        sta accl,x
        lda acch,x
        sbc p2
        sta acch,x
        rts

; ---------------------------------------------------------------------
; sprcopy: runs in the VBI, together with the frame-buffer flip
sprcopy:
        lda slemp               ; both columns blank, and already copied
        and slemp+1             ;   blank: only the positions and colours
        beq @cp0
        cmp pmcl
        beq @pos
@cp0:   sta pmcl
        ldx #63
@c:     lda STAGE2,x
        sta P2MEM+VIEWPM,x
        lda STAGE3,x
        sta P3MEM+VIEWPM,x
        dex
        bpl @c
@pos:   lda slhpos
        sta HPOSP2
        lda slhpos+1
        sta HPOSP3
        lda slsize
        sta SIZEP2
        lda slsize+1
        sta SIZEP3
        lda slcol
        sta PCOLR2
        sta COLPM2
        lda slcol+1
        sta PCOLR3
        sta COLPM3
        rts


; =====================================================================
;  Image B: runs from RAM $8000-$B7FF (copied from cartridge banks 2-3 at
;  start-up).  Nothing here may run from an interrupt: later stages page the
;  cartridge back in over $8000-$BFFF to load content.
; =====================================================================
.segment "CODE2"
; =====================================================================
; gen_writers: per buffer, a page of "STA row_addr,X" x65 + RTS
.segment "INITB"               ; (boot only: reused after start-up, see RB)
gen_writers:                    ; per buffer: 32 entries of STA row,X (the
        ldx #2                  ;   display lists show rows 32-63 as 31-0)
@buf:   stx tmp
        lda #0
        sta gptr
        lda cwhi,x
        sta gptr+1
        lda #0                  ; genl/genh = row r
        sta genl
        lda bufhi,x
        sta genh
        ldx #VROWS              ; (rows drawn: the top half's, VROWS of them)
        ldy #0
@row:   lda #$9D
        sta (gptr),y
        iny
        lda genl
        sta (gptr),y
        iny
        lda genh
        sta (gptr),y
        iny
        clc
        lda genl
        adc #NPAIRS
        sta genl
        bcc @nm
        inc genh
@nm:    dex
        bne @row
        lda #$9D                ; entry 32 -> dummy sink, then RTS
        sta (gptr),y
        iny
        lda #<DUMMY
        sta (gptr),y
        iny
        lda #>DUMMY
        sta (gptr),y
        iny
        lda #$60
        sta (gptr),y
        ldx tmp
        dex
        bpl @buf
        rts
.segment "CODE2"
bufhi:  .byte >BUF0, >BUF1, >BUF2

; =====================================================================
; Game / level setup
; =====================================================================
reset_game:                     ; new game: level 1, full health and ammo
        lda #0                  ; (dead is still set, so the clock is stopped)
        sta level
        sta score
        sta score+1
        sta score+2
        sta mins
        sta secs
        sta jif
        lda #$FF                ; (redraw the clock)
        sta lsec
        lda tadm                ; drop any pending time
        sta tadv
        lda #50                 ; 50 pistol rounds, nothing for the others
        sta ammop
        lda #100
        sta health
        sta owned               ; (pistol)
        lda #0
        sta owned+1
        sta owned+2
        sta ammop+1
        sta ammop+2
        sta weapon
        sta msgt
        sta trigl               ; (no shot saved from the game-over screen)
        jsr do_win
        lda #0
        sta dead                ; start the clock
        jmp setgun

; endgame: level 15 cleared.  The ending overlay (bank 5) takes over.
LASTLEVEL = 15
endgame:ldx #$FF
        txs
        lda #1
        sta dead
        sta paused
@w:     lda pending
        bne @w
        lda #5
        jsr ovloadb
        jmp ENDING

do_win:                         ; also entered from the exit door
        lda level
        bne @bonus
        jmp @first
@bonus: ; ---- score: 500 x level, plus 10 per second left on the clock
        sta cnt
@lv:    lda #<500
        ldx #>500
        jsr addscore
        dec cnt
        bne @lv
@rd:    lda mins                ; consistent snapshot (the VBI is counting down)
        sta cnt
        lda secs
        sta tmp2
        lda mins
        cmp cnt
        bne @rd
        lda #0                  ; T = mins * 60 + secs
        sta th
        lda cnt
        asl
        asl
        sta tl                  ; mins * 4 (< 400: may carry)
        rol th
        lda #0
        sta tt1
        lda cnt                 ; mins * 64
        lsr
        ror tt1
        lsr
        ror tt1
        sta tt0
        sec
        lda tt1
        sbc tl
        sta tl
        lda tt0
        sbc th
        sta th                  ; mins * 60
        clc
        lda tl
        adc tmp2
        sta tl
        bcc @t1
        inc th
@t1:    asl tl                  ; x 10 = x 2 + x 8
        rol th
        lda tl
        ldx th
        jsr addscore
        asl tl
        rol th
        asl tl
        rol th
        lda tl
        ldx th
        jsr addscore
@nob:   lda level
        cmp #LASTLEVEL          ; the last level: out of the maze for good
        bcc @more
        jmp endgame
@more:  jsr tunnel              ; the zooming tunnel to the next level
        ; ---- reward for finishing: ammo for each gun you have (max 99), +25 health
        jsr exitammo
        clc
        lda health
        adc #25
        cmp #101
        bcc @h
        lda #100
@h:     sta health
@first: inc level
        ; fall through

new_level:
        lda #$FF
        sta ptx
        ldx level               ; imps get faster each level
        lda #E_SPEED-ESTEP
@spd:   clc
        adc #ESTEP
        cmp #ESPMAX
        bcc @sp1
        lda #ESPMAX
@sp1:   dex
        bne @spd
        sta espeed
        lda #0
        sta won
        sta kills
        sta hurt
        sta atkcool
.ifdef PROF
        lda RTCLOK+2
        sta $1BE0
.endif
        ldx level               ; wall colours: a theme per level
        dex
@th:    cpx #6
        bcc @th1
        txa
        sbc #6
        tax
        bcs @th
@th1:   lda theme1,x
        sta wallc1
        lda theme2,x
        sta wallc2
        jsr seedlevel           ; this level = f(seed, level)
        jsr genmaze
.ifdef PROF
        lda RTCLOK+2
        sta $1BE4
.endif
        lda bestd               ; this level's time, on top of what's left:
        asl                     ;   T_LEVEL + 2 s per step to the exit
        bcs @tbc
        adc #T_LEVEL
        bcs @tbc
        cmp #241
        bcc @tbn
@tbc:   lda #240                ; (< 256 s in one go)
@tbn:   ldx level               ; a new game starts with exactly T_START
        cpx #1
        bne @tbx
        lda #T_START
@tbx:   clc
        adc tadm
        sta tadm
        ; ---- imps: level + 3, at most MAXEN; then pickups and the key
        clc
        lda level
        adc #3
        cmp #MAXEN+1
        bcc @n
        lda #MAXEN
@n:     sta nimp
        ; ---- toughness: imps take 3 hits to level 3, then +1 per level
        lda level
        cmp #E_HP+1
        bcs @h1
        lda #E_HP
@h1:    cmp #HPMAX+1
        bcc @h2
        lda #HPMAX
@h2:    sta thp                 ; imp
        lsr
        clc
        adc thp
        adc #2
        sta thp+1               ; brute: 1.5 x imp + 2
        ldx thp
        inx
        stx thp+2               ; spitter: imp + 1
        asl thp                 ; (in half points: the SMG does 1.5)
        asl thp+1
        asl thp+2
        ; ---- the mix: brutes from BRUTELEVEL ((level-1)/2, at most 3),
        ;      spitters from SPITLEVEL ((level-3)/2, at most 3), rest imps
        lda #0
        ldx level
        cpx #BRUTELEVEL
        bcc @b1
        dex
        txa
        lsr
        cmp #4
        bcc @b1
        lda #3
@b1:    sta nbrute
        lda #0
        ldx level
        cpx #SPITLEVEL
        bcc @s1
        txa
        sec
        sbc #3
        lsr
        cmp #4
        bcc @s1
        lda #3
@s1:    sta nspit
        lda #0
        sta havekey
        jsr place_enemies
.ifdef PROF
        lda RTCLOK+2
        sta $1BE5
.endif
        lda #>SEEN              ; nothing seen yet (SEEN was key-placement scratch)
        sta mp+1
        lda #0
        sta mp
        ldx #4
        ldy #0
@sc:    sta (mp),y
        iny
        bne @sc
        inc mp+1
        dex
        bne @sc
        jsr tickrs              ; (game time starts now)
        inc forcer
        jsr showlevel
        jsr showlvt
        jsr drawscore
        jsr drawtime
        jmp drawhud

theme1: .byte $00, $20, $00, $60, $00, $A0    ; view hue: gray, gold, gray, lavender, gray, teal
theme2: .byte $08, $28, $08, $68, $08, $A8    ; shaded
; (gold is hue 2: hue 1 reads as yellow-green on many NTSC sets)

; showlevel: the level's instruction on the message line
showlevel:
        lda demo
        beq @nd
        lda #<msg_demo
        ldy #>msg_demo
        jmp putmsg
@nd:    lda exitsn              ; locked, and the exit has been seen
        beq @u
        lda keyby               ; a monster still has the keycard
        bmi @kc
        lda #<msg_kill
        ldy #>msg_kill
        jmp putmsg
@kc:    lda #<kmsg
        ldy #>kmsg
        jmp putmsg
@u:     lda #<msg_level
        ldy #>msg_level
        jmp putmsg              ; (the level number is on the top bar)

; showlvt: level number in the top bar
showlvt:lda level
        jsr div10
        sta a:HUD3+LVLTPOS+1
        stx a:HUD3+LVLTPOS
        lda #$FF                ; and redraw the heading
        sta lastdir
        rts

; drawdir: the heading tape in the top bar, 9 marks centred on where you
;          face (32 steps around the circle; centre mark in inverse video)
drawdir:clc
        lda pa
        adc #16
        sta tmp
        lda pa+1
        adc #0
        and #3
        asl
        asl
        asl
        sta tmp2
        lda tmp
        lsr
        lsr
        lsr
        lsr
        lsr
        ora tmp2
        cmp lastdir
        beq @x
        sta lastdir
        sec
        sbc #4
        and #31
        tax
        ldy #0
@l:     lda tapech,x
        cpy #4
        bne @n
        ora #$80
@n:     sta HUD3+DIRPOS,y
        inx
        txa
        and #31
        tax
        iny
        cpy #9
        bne @l
@x:     rts
; around the circle from east (angle 0), clockwise as seen on the map
tapech: .byte $25,0,$0E,0,$0B,0,$0E,0, $33,0,$0E,0,$0B,0,$0E,0
        .byte $37,0,$0E,0,$0B,0,$0E,0, $2E,0,$0E,0,$0B,0,$0E,0

; putmsg: A/Y = a message for the message row (stays up): its left pad,
;         then its characters, ending in $FF
putmsg: sta gptr
        sty gptr+1
        ldx #39
        lda #0
@c:     sta HUD+40,x
        dex
        bpl @c
        sta msgt
        tay
        lda (gptr),y
        tax
@m:     iny
        lda (gptr),y
        cmp #$FF                ; (the end: other bytes with bit 7 set are
        beq @x                  ;   inverse characters, for key names)
        sta HUD+40,x
        inx
        bne @m
@x:     rts
; showmsg: same, but reverts to the level line after a couple of seconds
showmsg:
        jsr putmsg
        lda #MSGTIME
        sta msgt
        rts

; ---------------------------------------------------------------------
; rnd: A = pseudo-random byte.  16-bit xorshift (7,9,8), purely software, so
;      a level is the same every time for the same seed.
rnd:    lda rs+1
        lsr
        lda rs
        ror
        eor rs+1
        sta rs+1
        ror
        eor rs
        sta rs
        eor rs+1
        sta rs+1
        rts

; ---------------------------------------------------------------------
; Seeds.  seedd = 4 digits; the generator state for a level is built from the
; digits (as BCD) and the level number.
seedlevel:
        lda seedd
        asl
        asl
        asl
        asl
        ora seedd+1
        eor level
        sta rs+1
        lda seedd+2
        asl
        asl
        asl
        asl
        ora seedd+3
        eor #$A5                ; BCD never reaches $A5: rs is never 0
        sta rs
        ldx #8                  ; stir
@s:     jsr rnd
        dex
        bne @s
        rts

randseed:                       ; 4 random digits from POKEY
        ldx #3
@r:     lda RANDOM
        and #15
        cmp #10
        bcs @r
        sta seedd,x
        dex
        bpl @r
        lda #1
        sta seedset
        ; fall through
showseed:
        ldx #3
@d:     lda #$0D                ; '-' until a seed has been chosen
        ldy seedset
        beq @w
        lda seedd,x
        ora #$10
@w:     sta a:HUD3+SEEDPOS,x
        dex
        bpl @d
        rts


; =====================================================================
; genmaze: 7x7-cell maze in the 16x16 map (cells at odd x,y = 1..13)
;   1. fill with wall          2. recursive backtracker
;   3. knock out extra walls (loops)   4. carve two 3x3 rooms
;   5. BFS from a random mstart cell: exit door beside the farthest tile
; =====================================================================
genmaze:
        ; ---- size: the same every level (MAZEN x MAZEN cells)
        lda #MAZEN
@nc:    sta ncell
        asl
        sta maxc                ; last tile row/column of the maze (a wall)
        sec
        sbc #2
        sta lim                 ; a cell below this has a neighbour to its +x/+y
        ldx ncell
        dex
        stx ncm1
        ; ---- walls everywhere (the whole 32x32)
        lda #>map
        sta mp+1
        lda #0
        sta mp
        ldx #4
        lda #1
        ldy #0
@fl:    sta (mp),y
        iny
        bne @fl
        inc mp+1
        dex
        bne @fl

        ; ---- random start cell
        jsr rndcell
        lda curl
        sta mstl
        sta MSTKL
        lda curh
        sta msth
        sta MSTKH
        jsr opencur
        lda #1
        sta sp
        lda #$FF
        sta ldir

        ; ---- backtracker
@step:  ldx sp
        bne @top
        jmp @carved
@top:   lda MSTKL-1,x
        sta curl
        lda MSTKH-1,x
        sta curh
        jsr idxxy
        jsr bpage
        lda #0
        sta nnb
        lda cx                  ; cell +x (two tiles over, same row)
        cmp lim
        bcs @d1
        ldy curl
        iny
        iny
        lda (mp),y
        beq @d1
        lda #4
        jsr addnb
@d1:    lda cx                  ; cell -x
        cmp #3
        bcc @d2
        ldy curl
        dey
        dey
        lda (mp),y
        beq @d2
        lda #5
        jsr addnb
@d2:    lda cy                  ; cell +y (two rows down: may be the next page)
        cmp lim
        bcs @d3
        lda curl
        clc
        adc #64
        tay
        bcc @e2
        inc mp+1
        lda (mp),y
        dec mp+1
        tax                     ; (flags from the tile, not the DEC)
        jmp @f2
@e2:    lda (mp),y
@f2:    beq @d3
        lda #6
        jsr addnb
@d3:    lda cy                  ; cell -y
        cmp #3
        bcc @dd
        lda curl
        sec
        sbc #64
        tay
        bcs @e3
        dec mp+1
        lda (mp),y
        inc mp+1
        tax
        jmp @f3
@e3:    lda (mp),y
@f3:    beq @dd
        lda #7
        jsr addnb
@dd:    lda nnb
        bne @pick
        dec sp                  ; dead end: backtrack
        lda #$FF
        sta ldir
        jmp @step
@pick:  lda ldir                ; straight on, if that way is open (STRAIGHT in 4)
        bmi @rnd
.if STRAIGHT = 0
        jmp @rnd
.endif
        jsr rnd
        and #3
        cmp #STRAIGHT
        bcs @rnd
        ldx nnb
@fd:    dex
        bmi @rnd
        lda nbdir,x
        cmp ldir
        bne @fd
        txa
        jmp @got
@rnd:   jsr rnd
        and #3
        cmp nnb
        bcs @rnd
@got:   tax
        lda nbdir,x
        sta dir
        sta ldir
        sec
        sbc #4
        tay
        jsr step                ; the wall in between
        lda #0
        jsr stmap
        ldy dir
        jsr step                ; the new cell
        lda #0
        jsr stmap
        ldx sp
        lda nl
        sta MSTKL,x
        lda nh
        sta MSTKH,x
        inc sp
        jmp @step

@carved:
.ifdef PROF
        lda RTCLOK+2
        sta $1BE1
.endif
        ; ---- extra openings for loops: LOOPS per cell row
        lda ncell
.repeat LOOPS-1
        clc
        adc ncell
.endrepeat
        sta cnt
@br:    jsr rnd
        and #3
        sta dir
        jsr rndcell
        jsr dirok
        bcc @brn
        ldy dir
        jsr step
        lda #0
        jsr stmap
@brn:   dec cnt
        bne @br

        ; ---- halls: 2 in the smallest mazes, up to 4; each 2-4 cells a side
        ;      (3-5 in the bigger mazes), with columns one tile in from the
        ;      corners (a 2-cell hall has one in the middle)
        jsr rnd                 ; 2 or 3 small rooms
        and #1
        clc
        adc #2
        sta nroom
        sta cnt
@hall0: lda #40                 ; tries to keep it clear of the other rooms
        sta tries
@hall:  jsr rnd                 ; width and height in cells
        and #3
        ldx ncell
        cpx #13
        bcc @hs
        ora #4
@hs:    tax
        lda hsize,x
        sta tmp
        jsr rnd
        and #3
        ldx ncell
        cpx #13
        bcc @hs2
        ora #4
@hs2:   tax
        lda hsize,x
        sta tmp2
        lda ncell               ; top-left cell 0 .. ncell - size
        sec
        sbc tmp
        sta tmp3
@hx:    jsr rnd
        and #15
        cmp tmp3
        beq @hx1
        bcs @hx
@hx1:   asl
        ora #1
        ldx cnt
        sta hallx-1,x
        lda ncell
        sec
        sbc tmp2
        sta tmp3
@hy:    jsr rnd
        and #15
        cmp tmp3
        beq @hy1
        bcs @hy
@hy1:   asl
        ora #1
        sta hally-1,x
        lda tmp                 ; size in tiles: 2 * cells - 1
        asl
        sbc #0                  ; (C clear after ASL of a small value: -1)
        sta hallw-1,x
        lda tmp2
        asl
        sbc #0
        sta hallh-1,x
        dec tries
        beq @place              ; (no clear spot: let it touch)
        jsr hallok
        bcc @place
        jmp @hall
@place: ldx cnt
        jsr carvehall
        dec cnt
        beq @halls
        jmp @hall0
@halls:
        jsr braid               ; no long dead ends

        ; ---- walking distances from the start
        lda mstl
        sta bsl
        lda msth
        sta bsh
        lda #1
        sta bfull
        lda #255
        sta blim
.ifdef PROF
        lda RTCLOK+2
        sta $1BE7
.endif
        jsr bfs
.ifdef PROF
        lda RTCLOK+2
        sta $1BE2
.endif
        ; ---- exit door: the wall whose NEAREST open side is farthest from
        ;      the start (a wall bordering two corridors can be touched from either)
        lda #0
        sta bestd
        sta cy
@dwy:   jsr rowptrs
        ldy #0
@dwx:   lda (gpc),y
        cmp #1
        bne @dn
        lda #$FF
        sta tmp2                ; nearest open side so far
        lda (gpu),y             ; up
        bne @u
        lda (gdu),y
        cmp tmp2
        bcs @u
        sta tmp2
@u:     lda (gpd),y             ; down
        bne @d
        lda (gdd),y
        cmp tmp2
        bcs @d
        sta tmp2
@d:     iny                     ; right
        lda (gpc),y
        bne @r
        lda (gdc),y
        cmp tmp2
        bcs @r
        sta tmp2
@r:     dey
        beq @l                  ; (column 0 has nothing to its left)
        dey                     ; left
        lda (gpc),y
        bne @l1
        lda (gdc),y
        cmp tmp2
        bcs @l1
        sta tmp2
@l1:    iny
@l:     lda tmp2
        cmp #$FF                ; no open side: not a candidate
        beq @dn
        cmp bestd
        bcc @dn
        beq @dn
        sta bestd
        sty pkx
        lda cy
        sta pky
@dn:    iny
        cpy maxc
        bcc @dwx
        beq @dwx
        inc cy
        lda cy
        cmp maxc
        bcc @dwy
        beq @dwy
        lda pkx
        sta cx
        lda pky
        sta cy
        jsr xyidx
        lda curl
        sta btl
        lda curh
        sta bth
        lda btl
        sta nl
        lda bth
        sta nh
.ifdef PROF
        lda RTCLOK+2
        sta $1BE3
.endif
        lda #2
        jsr stmap
        ; ---- the walls around the halls, and their columns, are bulkhead
        ;      (after the door, so the exit is where it always was for this seed)
        ldx nroom
@sr:    stx cnt
        jsr ringhall
        ldx cnt
        dex
        bne @sr

        ; ---- stripes on the walls either side of the exit (a landmark)
        lda btl
        sta curl
        lda bth
        sta curh
        ldy #3
@hz:    sty dir
        jsr step
        lda dir                 ; west (1) and north (3): note the tile for
        lsr                     ;   the mirrored stripes
        bcc @he
        tax
        lda nl
        sta mirl,x
        lda nh
        ora #>map
        asl
        sta mirp,x
@he:    jsr ldmap
        beq @hn
        cmp #2
        beq @hn
        lda #10
        jsr stmap
@hn:    ldy dir
        dey
        bpl @hz

        ; ---- player at the start cell, facing an open direction
        lda mstl
        sta curl
        lda msth
        sta curh
        jsr idxxy
        lda cx
        sta px+1
        lda cy
        sta py+1
        lda #$80
        sta px
        sta py
        ldy #0
@face:  sty dir
        jsr step
        jsr ldmap
        beq @fok
        ldy dir
        iny
        cpy #3
        bne @face
        sty dir                 ; (none of the first three: the last one)
@fok:   ldy dir
        lda faceang,y
        sta pa+1
        lda #0
        sta pa
        rts

; ---------------------------------------------------------------------
; Tiles are 16-bit: index = row * 32 + column, kept as a low byte and a
; page (0-3).  map, MDIST and SEEN all start on a 1K boundary, so the page
; ORed into the base's high byte addresses any of them.
;
; xyidx: (cx, cy) -> curl/curh
xyidx:  lda cy
        lsr
        lsr
        lsr
        sta curh
        lda cy
        asl
        asl
        asl
        asl
        asl
        ora cx
        sta curl
        rts
; idxxy: curl/curh -> (cx, cy)
idxxy:  lda curl
        and #31
        sta cx
        lda curh
        asl
        asl
        asl
        sta cy
        lda curl
        lsr
        lsr
        lsr
        lsr
        lsr
        ora cy
        sta cy
        rts
; step: Y = direction (0-3: neighbour +x -x +y -y; 4-7: the cell two away)
;       nl/nh = cur + offset
step:   clc
        lda curl
        adc dofl,y
        sta nl
        lda curh
        adc dofh,y
        and #3
        sta nh
        rts
dofl:   .byte 1, $FF, 32, $E0, 2, $FE, 64, $C0
dofh:   .byte 0, $FF, 0, $FF, 0, $FF, 0, $FF
; ldmap: A = map at (nl, nh), Z set if open.  Y = nl, mp+1 set.
ldmap:  lda nh
        ora #>map
        sta mp+1
        ldy nl
        lda (mp),y
        rts
; stmap: map at (nl, nh) = A
stmap:  pha
        lda nh
        ora #>map
        sta mp+1
        ldy nl
        pla
        sta (mp),y
        rts
; lddst / stdst: MDIST at (nl, nh)
lddst:  lda nh
        ora #>MDIST
        sta dp+1
        ldy nl
        lda (dp),y
        rts
stdst:  pha
        lda nh
        ora #>MDIST
        sta dp+1
        ldy nl
        pla
        sta (dp),y
        rts
; opencur: map at cur = 0
opencur:lda curh
        ora #>map
        sta mp+1
        ldy curl
        lda #0
        sta (mp),y
        rts

; ---------------------------------------------------------------------
; bfs: (bsl, bsh) = start tile.  MDIST = walking distance (saturating at 254)
;      of every open tile up to blim steps away, $FF elsewhere.  bfull = 1
;      clears all of MDIST first; otherwise only the tiles the last search
;      visited (the queue still lists them) are reset.
bfs:    lda bfull
        beq @reset
        lda #>MDIST
        sta dp+1
        lda #0
        sta dp
        ldx #4
        lda #$FF
        ldy #0
@f:     sta (dp),y
        iny
        bne @f
        inc dp+1
        dex
        bne @f
        beq @go
@reset: lda #<MQ
        sta qhp
        lda #>MQ
        sta qhp+1
@rl:    lda qhp
        cmp qtp
        bne @r1
        lda qhp+1
        cmp qtp+1
        beq @go
@r1:    ldy #1
        lda (qhp),y             ; page
        ora #>MDIST
        sta dp+1
        dey
        lda (qhp),y             ; low byte
        tay
        lda #$FF
        sta (dp),y
        clc
        lda qhp
        adc #2
        sta qhp
        bcc @rl
        inc qhp+1
        bne @rl
@go:    lda #<MQ
        sta qhp
        sta qtp
        lda #>MQ
        sta qhp+1
        sta qtp+1
        lda bsh
        sta curh
        jsr bpage
        ldy bsl
        lda #0
        sta (dp),y
        jsr benq
@loop:  lda qhp
        cmp qtp
        bne @pop
        lda qhp+1
        cmp qtp+1
        bne @pop
        rts
@pop:   ldy #0
        lda (qhp),y
        sta curl
        iny
        lda (qhp),y
        sta curh
        clc
        lda qhp
        adc #2
        sta qhp
        bcc @p1
        inc qhp+1
@p1:    jsr bpage
        ldy curl
        lda (dp),y
        cmp blim
        bcs @loop               ; as far as this search goes
        cmp #254
        bcs @sat
        adc #1
@sat:   sta tmp2                ; distance for its neighbours
        iny                     ; +x, -x: same page (a row never spans two)
        jsr btry
        dey
        dey
        jsr btry
        lda curl                ; +y
        clc
        adc #32
        tay
        bcc @n1
        inc curh
        jsr bpage
        jsr btry
        dec curh
        jsr bpage
        jmp @n2
@n1:    jsr btry
@n2:    lda curl                ; -y
        sec
        sbc #32
        tay
        bcs @n3
        dec curh
        jsr bpage
        jsr btry
        inc curh
        jmp @loop
@n3:    jsr btry
        jmp @loop

; bpage: mp/dp -> page curh (0-3) of map / MDIST
bpage:  lda curh
        and #3
        sta curh
        ora #>map
        sta mp+1
        eor #(>map ^ >MDIST)
        sta dp+1
        rts

; btry: tile Y on the current page: open and not yet reached -> distance
;       tmp2, onto the queue.  Keeps Y.
btry:   lda (mp),y
        bne @no
        lda (dp),y
        cmp #$FF
        bne @no
        lda tmp2
        sta (dp),y
        jmp benq
@no:    rts
; benq: (Y, curh) onto the queue's tail.  Keeps Y.
benq:   lda qtp+1
        cmp #>(MQ+$400)
        bcs @x                  ; (full: never happens, 512 > open tiles)
        sty nl
        tya
        ldy #0
        sta (qtp),y
        iny
        lda curh
        sta (qtp),y
        clc
        lda qtp
        adc #2
        sta qtp
        bcc @y
        inc qtp+1
@y:     ldy nl
@x:     rts

; addnb: A = cell direction (4-7) -> nbdir
addnb:  ldx nnb
        sta nbdir,x
        inc nnb
        rts

; dirok: carry set if a cell exists in direction dir (0-3) from (cx, cy)
dirok:  ldy dir
        lda cx
        cpy #0
        bne @1
        cmp lim
        bcs @no
        bcc @yes
@1:     cpy #1
        bne @2
        cmp #3
        bcc @no
        bcs @yes
@2:     lda cy
        cpy #2
        bne @3
        cmp lim
        bcs @no
        bcc @yes
@3:     cmp #3
        bcc @no
@yes:   sec
        rts
@no:    clc
        rts

; rndcell: a random cell: (cx, cy) odd, 1 .. 2*ncell-1; cur = its tile
rndcell:
@x:     jsr rnd
        and #15
        cmp ncell
        bcs @x
        asl
        ora #1
        sta cx
@y:     jsr rnd
        and #15
        cmp ncell
        bcs @y
        asl
        ora #1
        sta cy
        jmp xyidx

hsize:  .byte 2, 2, 3, 3, 2, 2, 3, 3   ; room sides in cells (3 or 5 tiles)

; hallok: X = hall being placed.  C set if it comes closer than a corridor to a room
;         already placed (X+1 .. nroom).
hallok: txa
        tay
@l:     iny
        cpy nroom
        beq @t
        bcs @ok
@t:     lda hallx-1,y           ; clear if x >= xj + wj + 1 ...
        clc
        adc hallw-1,y
        adc #3
        sta tmp
        lda hallx-1,x
        cmp tmp
        bcs @l
        lda hallx-1,x           ; ... or xj >= x + w + 1
        clc
        adc hallw-1,x
        adc #3
        sta tmp
        lda hallx-1,y
        cmp tmp
        bcs @l
        lda hally-1,y           ; same for y
        clc
        adc hallh-1,y
        adc #3
        sta tmp
        lda hally-1,x
        cmp tmp
        bcs @l
        lda hally-1,x
        clc
        adc hallh-1,x
        adc #3
        sta tmp
        lda hally-1,y
        cmp tmp
        bcs @l
        sec                     ; overlaps
        rts
@ok:    clc
        rts

; carvehall: X = hall (1-based).  Open its rectangle except the columns.
carvehall:
        lda hallw-1,x
        sta hw
        sec
        sbc #2
        sta hw2
        lda hallh-1,x
        sta hh
        sec
        sbc #2
        sta hh2
        lda hallx-1,x
        sta hx0
        lda hally-1,x
        sta cy
        lda #0
        sta hry
        lda hw                  ; columns only in halls 7+ tiles both ways
        cmp #7
        bcc @nopil
        lda hh
        cmp #7
        bcs @row
@nopil: lda #$FF                ; (no row matches: no columns)
        sta hh2
@row:   lda hx0
        sta cx
        jsr xyidx
        lda curh
        ora #>map
        sta mp+1
        ldx #0
@col:   lda hry                 ; a column at (1 or w-2, 1 or h-2)?
        cmp #1
        beq @c1
        cmp hh2
        beq @py
        bne @open
@c1:    lda hh2
        cmp #$FF
        beq @open
        lda hry
        cmp #1
        beq @py
        cmp hh2
        bne @open
@py:    cpx #1
        beq @next
        cpx hw2
        beq @next
@open:  txa
        clc
        adc curl
        tay
        lda #0
        sta (mp),y
@next:  inx
        cpx hw
        bne @col
        inc cy
        inc hry
        lda hry
        cmp hh
        bne @row
        rts

; ringhall: X = hall (1-based).  Walls in its rectangle and the ring around
;           it (columns included) become bulkhead (3).
ringhall:
        jsr rnd                 ; this room's wall style: 5-9 or 11-15
        and #15
        cmp #10
        bcs ringhall
        cmp #5
        bcc @s5
        adc #0                  ; (C set: +1, skipping 10)
@s5:    adc #5
        sta hsty
        lda hallw-1,x
        clc
        adc #2
        sta hw
        lda hallh-1,x
        clc
        adc #2
        sta hh
        lda hallx-1,x
        sec
        sbc #1
        sta hx0
        lda hally-1,x
        sec
        sbc #1
        sta cy
        lda #0
        sta hry
@row:   lda hx0
        sta cx
        jsr xyidx
        lda curh
        ora #>map
        sta mp+1
        ldy curl
        ldx hw
@col:   lda (mp),y
        cmp #1
        bne @n
        lda hsty
        sta (mp),y
@n:     iny
        dex
        bne @col
        inc cy
        inc hry
        lda hry
        cmp hh
        bne @row
        rts

; rowptrs: row cy -> gpc/gdc, the row above -> gpu/gdu, below -> gpd/gdd
;          (map / MDIST; rows wrap 0-31, and rows 31 and 0 are walls)
rowptrs:lda cy
        jsr @rb
        sta gpc+1
        eor #(>map ^ >MDIST)
        sta gdc+1
        lda tmp
        sta gpc
        sta gdc
        lda cy
        sec
        sbc #1
        jsr @rb
        sta gpu+1
        eor #(>map ^ >MDIST)
        sta gdu+1
        lda tmp
        sta gpu
        sta gdu
        lda cy
        clc
        adc #1
        jsr @rb
        sta gpd+1
        eor #(>map ^ >MDIST)
        sta gdd+1
        lda tmp
        sta gpd
        sta gdd
        rts
@rb:    and #31                 ; A = row -> tmp = low byte, A = map page
        pha
        asl
        asl
        asl
        asl
        asl
        sta tmp
        pla
        lsr
        lsr
        lsr
        ora #>map
        rts

faceang: .byte 0, 2, 1, 3              ; pa high byte facing +x, -x, +y, -y

; =====================================================================
; place_enemies: nimp imps, then this level's pickups, then (from KEYLEVEL)
; the blue key.  Uses MDIST = walking distance from the start.
place_enemies:
        ldx #0
@e:     cpx nimp
        beq @pk
        ldy #TY_SPIT            ; spitters first, then brutes, then imps
        cpx nspit
        bcc @ty
        ldy #TY_BRUTE
        txa
        sec
        sbc nspit
        cmp nbrute
        bcc @ty
        ldy #TY_IMP
@ty:    lda #6
        jsr placething
        ldy ETYP,x
        lda thp,y
        sta EHP,x
        lda #SPITCOOL           ; (spitters: don't fire the instant you appear)
        sta ETIM,x
        lda #0
        sta EATK,x
        sta ESEE,x
        inx
        bne @e
@pk:    stx nen
        jsr placepk             ; ammo, health, time: more on later levels
        ; ---- a weapon you don't have yet.  The tile is always drawn from the
        ;      generator, so a seed's later levels don't depend on what you own.
        ldy #PK_CHAIN
        lda level
        cmp #CHAINLEVEL
        bcc @nc
        lda owned+2
        beq @wp
@nc:    ldy #PK_SHOTGUN
        lda level
        cmp #SHOTLEVEL
        bcc @nw
        lda owned+1
        beq @wp
@nw:    ldy #$FF                ; nothing to hand out
@wp:    sty tmp2
        ldx nen
        lda #8
        ldy #PK_AMMO
        jsr placething
        lda tmp2
        cmp #$FF                ; (pickup types are $80+: test for "none")
        beq @off
        sta ETYP,x
        inc nen
        bne @key
@off:   lda #0
        sta EST,x
        ; ---- the key: from KEYLEVEL, the exit is locked
@key:   lda #0
        sta locked
        lda level
        cmp #KEYLEVEL
        bcc @clr
        lda #1
        sta locked
        lda #4
        jsr setdoor
        jsr placekey
.ifdef PROF
        lda RTCLOK+2
        sta $1BE6
.endif
@clr:   ldx nen                 ; clear unused slots so stale things never show
        lda #0
@cl:    cpx #MAXTH
        beq @x
        sta EST,x
        inx
        bne @cl
@x:     jmp keyhide             ; keycard carrier, music, then lvlextra

; addpk: A = pickup type; place it at least 3 steps from the start
addpk:  tay
        lda #3
        ldx nen
        jsr placething
        inc nen
        rts

; placething: X = thing, A = minimum distance from the start, Y = type.
;             Random open tile that no earlier thing occupies.  Keeps X.
placething:
        sta thr
        tya
        sta ETYP,x
        stx ei
        lda #0
        sta tries
@try:   inc tries
        bne @t1
        lda thr                 ; 256 misses: accept closer tiles
        cmp #2
        beq @t1
        dec thr
@t1:    jsr rnd
        and #31
        cmp maxc
        bcs @try
        sta cx
@t2:    jsr rnd
        and #31
        cmp maxc
        bcs @t2
        sta cy
        jsr xyidx
        lda curl
        sta nl
        lda curh
        sta nh
        jsr ldmap
        bne @try
        jsr lddst
        cmp #$FF
        beq @try
        cmp thr
        bcc @try
        ldx ei
        beq @ok
@dup:   dex
        lda cx
        cmp EXH,x
        bne @nx
        lda cy
        cmp EYH,x
        beq @again
@nx:    cpx #0
        bne @dup
@ok:    ldx ei
        jmp setthing
@again: ldx ei
        jmp @try

; setthing: X = thing, (cx, cy) = tile.  Centre of the tile, active, fresh.
setthing:
        lda cx
        sta EXH,x
        lda cy
        sta EYH,x
        lda #$80
        sta EXL,x
        sta EYL,x
        lda #1
        sta EST,x
        lda #E_HP
        sta EHP,x
        lda #0
        sta EPAIN,x
        sta EWAKE,x
        sta ETIM,x
        rts

; placekey: the open tile farthest from BOTH the start and the exit (the
; larger of the two walking distances' minimum), and extra time for the detour.
; SEEN (cleared afterwards) holds the distances from the start meanwhile.
placekey:
        lda #>MDIST             ; SEEN <- MDIST (distance from the start)
        sta dp+1
        lda #>SEEN
        sta mp+1
        lda #0
        sta dp
        sta mp
        ldx #4
        ldy #0
@c:     lda (dp),y
        sta (mp),y
        iny
        bne @c
        inc dp+1
        inc mp+1
        dex
        bne @c
        lda btl                 ; distances from the open side of the exit
        sta curl
        lda bth
        sta curh
        ldy #3
@f:     sty dir
        jsr step
        jsr ldmap
        beq @got
        ldy dir
        dey
        bpl @f
@got:   lda nl
        sta bsl
        lda nh
        sta bsh
        lda #0
        sta bfull
        lda #255
        sta blim
        jsr bfs
        lda #0
        sta tmp3                ; best so far
        sta cy
@ky:    jsr rowptrs
        lda gpc+1               ; this row of SEEN (distances from the start)
        eor #(>map ^ >SEEN)
        sta gpu+1
        lda gpc
        sta gpu
        ldy #0
@kx:    lda (gpc),y
        bne @kn
        lda (gdc),y             ; from the exit ...
        cmp (gpu),y             ; ... and from the start: the smaller
        bcc @m
        lda (gpu),y
@m:     cmp #$FF
        beq @kn
        cmp tmp3
        bcc @kn
        beq @kn
        sta tmp3
        sty pkx
        lda cy
        sta pky
@kn:    iny
        cpy maxc
        bcc @kx
        inc cy
        lda cy
        cmp maxc
        bcc @ky
        ldx nen
        lda #PK_KEY
        sta ETYP,x
        lda pkx
        sta cx
        lda pky
        sta cy
        jsr setthing
        inc nen
        ; ---- time for the detour: 3/4 s per extra step (start->key->exit),
        ;      at most 50 s
        jsr xyidx
        lda curl
        sta nl
        lda curh
        sta nh
        jsr lddst
        sta tmp
        lda nh
        ora #>SEEN
        sta mp+1
        lda (mp),y
        clc
        adc tmp
        bcc @d1
        lda #255
@d1:    sec
        sbc bestd
        bcs @d2
        lda #0
@d2:    asl                     ; 2 s per step of the detour, at most 120
        bcs @dc
        cmp #121
        bcc @d3
@dc:    lda #120
@d3:    clc
        adc tadm
        sta tadm
        rts

; ---------------------------------------------------------------------
; bin2dec: A (0-255) -> dg2 dg1 dg0 screen codes, leading zeros blank
bin2dec:
        ldx #0
@h:     cmp #100
        bcc @t
        sbc #100
        inx
        bne @h
@t:     stx dg2
        ldx #0
@t2:    cmp #10
        bcc @o
        sbc #10
        inx
        bne @t2
@o:     ora #$10
        sta dg0
        txa
        ora #$10
        sta dg1
        lda dg2
        bne @x
        sta dg2                 ; 0 = blank
        lda dg1
        cmp #$10
        bne @x
        lda #0
        sta dg1
        rts
@x:     lda dg2
        beq @r
        ora #$10
        sta dg2
@r:     rts

; =====================================================================
; Automap
; =====================================================================
toggle_map:
        inc forcer              ; (the view must be drawn again)
        lda amap
        eor #1
        sta amap
        beq @off
        lda #0                  ; hide gun and hand
        sta HPOSP0
        sta HPOSP1
        rts
@off:   lda #120
        sta HPOSP0
        lda #112
        sta HPOSP1
        ldx #NPAIRS-1           ; every buffer needs a full redraw
        lda #0
@p:     sta PREV0,x
        sta PREV1,x
        sta PREV2,x
        dex
        bpl @p
        rts

; drawmap: 32x32 tiles as 4x2-pixel blocks (seen walls only) + player marker
drawmap:
        ldx buf
        lda bufhi,x
        sta sptr+1
        lda #0
        sta sptr
        sta mp
        sta dp
        sta mty
@trow:  lda mty                 ; this tile row's SEEN and map pointers
        lsr
        lsr
        lsr
        sta tmp
        ora #>SEEN
        sta dp+1
        lda tmp
        ora #>map
        sta mp+1
        lda mty
        asl
        asl
        asl
        asl
        asl
        sta tmp                 ; row's low byte
        ldx #0
@tc:    txa
        ora tmp
        tay
        lda (dp),y
        beq @blk
        lda (mp),y
        tay
        lda mapcol,y
@blk:   sta mrow,x
        inx
        cpx #32
        bne @tc
        lda #2                  ; two screen rows per tile row
        sta cnt
@sr:    lda #0
        ldy #3
@m1:    sta (sptr),y
        dey
        bpl @m1
        ldy #36
@m2:    sta (sptr),y
        iny
        cpy #40
        bne @m2
        ldx #0
        ldy #4
@m3:    lda mrow,x
        sta (sptr),y
        iny
        inx
        cpx #32
        bne @m3
        clc
        lda sptr
        adc #40
        sta sptr
        bcc @nc
        inc sptr+1
@nc:    dec cnt
        bne @sr
        inc mty
        lda mty
        cmp #32
        bne @trow
        ; ---- player: an arrow (5x5, one of 8 directions) centred on you
        ;      x = 16 + 4 * px, y = 2 * py
        lda px
        rol
        rol
        rol
        and #3
        sta tmp
        lda px+1
        asl
        asl
        clc
        adc tmp
        adc #16
        sta mpx
        lda py
        asl
        lda py+1
        rol
        sta mpy
        lda pa                  ; direction: (angle + 1/16 turn) / 8
        clc
        adc #64
        sta tmp
        lda pa+1
        adc #0
        asl tmp
        rol
        and #7
        sta tmp
        asl
        asl
        adc tmp                 ; (C clear) x 5: its first row in arrows
        sta mnx
        lda mpy
        sec
        sbc #2
        sta tmp2                ; row being drawn
        lda #5
        sta cnt
@ar:    ldy mnx
        lda arrows,y
        sta tmp
        ldx mpx
        dex
        dex
        ldy tmp2
@ab:    asl tmp
        bcc @an
        jsr plot
@an:    inx
        lda tmp                 ; (the low 3 bits are always 0)
        bne @ab
        inc mnx
        inc tmp2
        dec cnt
        bne @ar
        lda #$FF
        sta pcol
        ldy #0                  ; compass rose in the right margin
@cp:    lda compass,y
        cmp #$FF
        beq @cpx
        tax
        iny
        lda compass,y
        iny
        sty mnx
        tay
        jsr plot
        ldy mnx
        jmp @cp
@cpx:   jmp mapextra            ; the entrance and the pickups you've seen
mapcol: .byte $00, $AA, $55, $AA, $55, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA ; open, walls, exits

; plot: set pixel X (0-159), row Y (0-63) to colour 3 in the back buffer.
;       Preserves X and Y.
plot:   stx mtx
        sty mty
        ldx buf
        lda bufhi,x
        sta gptr+1
        lda #0
        sta gptr
        cpy #0                  ; + row * 40
        beq @r0
@rw:    clc
        lda gptr
        adc #40
        sta gptr
        bcc @rn
        inc gptr+1
@rn:    dey
        bne @rw
@r0:
        lda mtx
        lsr
        lsr
        tay
        lda mtx
        and #3
        tax
        lda pxmask,x            ; replace the pixel (don't mix colours)
        eor #$FF
        and (gptr),y
        sta ptmp
        lda pxmask,x
        and pcol
        ora ptmp
        sta (gptr),y
        ldx mtx
        ldy mty
        rts
pxmask: .byte $C0, $30, $0C, $03

; ---------------------------------------------------------------------
; addscore: score (24-bit) += X:A, keeping the high score up to date
;           (call drawscore afterwards to show it)
addscore:
        clc
        adc score
        sta score
        txa
        adc score+1
        sta score+1
        bcc @c
        inc score+2
@c:     lda demo                ; (the demo doesn't set high scores)
        bne @x
        lda score+2             ; score > high ?
        cmp high+2
        bne @cmp
        lda score+1
        cmp high+1
        bne @cmp
        lda score
        cmp high
@cmp:   bcc @x
        beq @x
        ldx #2
@cp:    lda score,x
        sta high,x
        dex
        bpl @cp
@x:     rts

drawscore:
        ldx #2
@s:     lda score,x
        sta nn,x
        dex
        bpl @s
        ldx #SCOREPOS
        jsr dec6
        ldx #2
@h:     lda high,x
        sta nn,x
        dex
        bpl @h
        ldx #HIGHPOS
        ; fall through
; dec6: nn (24-bit) -> six digits at HUD3+X
dec6:   ldy #0
@d:     lda #$10                ; '0'
        sta dg
@sub:   sec
        lda nn
        sbc p10l,y
        sta tt0
        lda nn+1
        sbc p10m,y
        sta tt1
        lda nn+2
        sbc p10h,y
        bcc @nd
        sta nn+2
        lda tt1
        sta nn+1
        lda tt0
        sta nn
        inc dg
        bne @sub
@nd:    lda dg
        sta HUD3,x
        inx
        iny
        cpy #6
        bne @d
        rts
p10l:   .byte $A0, $10, $E8, $64, $0A, $01   ; 100000 10000 1000 100 10 1
p10m:   .byte $86, $27, $03, $00, $00, $00
p10h:   .byte $01, $00, $00, $00, $00, $00

; drawtime: level clock as MM:SS
drawtime:
        lda mins
        jsr div10
        ora tinv                ; (keep the blink the VBI set)
        sta a:HUD3+TIMEPOS+1
        txa
        ora tinv
        sta a:HUD3+TIMEPOS
        lda secs
        jsr div10
        ora tinv
        sta a:HUD3+TIMEPOS+4
        txa
        ora tinv
        sta a:HUD3+TIMEPOS+3
        rts
; div10: A (0-99) -> X = tens digit, A = ones digit (screen codes)
div10:  ldx #$10
@t:     cmp #10
        bcc @o
        sbc #10
        inx
        bne @t
@o:     ora #$10
        rts

; drawhud: ammo, kills, health
drawhud:
        lda weapon              ; weapon name (7 characters)
        asl
        asl
        asl
        sec
        sbc weapon
        tax
        ldy #0
@w:     lda wpnname,x
        sta a:HUD+WPNPOS,y
        inx
        iny
        cpy #7
        bne @w
        ldx #2                  ; key: --- needed, KEY (inverse) held, blank
@k:     lda #0
        ldy locked
        beq @ks
        lda #$0D
        ldy havekey
        beq @ks
        lda keytxt,x
        ora #$80
@ks:    sta a:HUD+KEYPOS,x
        dex
        bpl @k
        ldx weapon              ; the gun in hand's ammo
        lda ammop,x
        sta ammo
        jsr bin2dec             ; (up to 200: three digits)
        lda dg2
        sta a:HUD+AMMOPOS
        lda dg1
        sta a:HUD+AMMOPOS+1
        lda dg0
        sta a:HUD+AMMOPOS+2
        lda kills
        jsr bin2dec
        lda dg0
        sta a:HUD+KILLPOS
        lda nimp
        ora #$10
        sta a:HUD+KILLPOS+2
        lda health
        jsr bin2dec
        lda dg2
        sta a:HUD+HEALTHPOS
        lda dg1
        sta a:HUD+HEALTHPOS+1
        lda dg0
        sta a:HUD+HEALTHPOS+2
        rts

.segment "CODE"                 ; (game over: in image A, which has room)
; ---------------------------------------------------------------------
player_dies:
        ldx #$40                ; the view turns red
        lda #<msg_died
        ldy #>msg_died
gameover:                       ; A/Y = message, X = the view's tint
        stx wallc1
        jsr putmsg
        lda #0                  ; (no hurt flash over the tint)
        sta hurt
        sta hurtofs
        lda #$FF                ; forget keys pressed during play
        sta CH
        lda #1
        sta dead
@w:     lda pending             ; the last frame on screen, then GAME OVER
        bne @w
        lda #0                  ; monsters off the screen (sprites would
        sta HPOSP2              ;   cover the banner)
        sta HPOSP3
        jsr unmir               ; (the banner isn't symmetric: the frame's
        jsr BANNER              ;   whole picture, through a plain list)
        jsr plaindl
        jmp deadloop
time_up:
        ldx #$20                ; the view turns yellow
        lda #<msg_tout
        ldy #>msg_tout
        jmp gameover

; deadloop: after a game over.  R retries the same seed, START goes to the
;           main menu (fire does nothing).  The demo returns to the menu.
deadloop:
        ldx #$FF
        txs
        lda #0
        sta dwait
@w:     lda RTCLOK+2
@v:     cmp RTCLOK+2
        beq @v
        lda demo
        beq @k
        inc dwait
        lda dwait
        cmp #180
        bcs @m
        lda STRIG0
        beq @m
        lda CH
        cmp #$FF
        bne @m
@k:     lda srreq
        beq @r
@m:     jmp gomenu
@r:     lda CH
        cmp #$FF
        beq @w
        ldx #$FF
        stx CH
        and #$3F
        cmp #$28                ; R
        bne @w
        lda #1                  ; same seed from level 1, full redraw
        sta amap
        jsr toggle_map
        jsr reset_game
        jmp mainloop

.segment "CODE2"
; =====================================================================
; enemy_ai: dying timers, chase, melee
enemy_ai:
        inc aifr
        lda atkcool
        beq @c0
        dec atkcool
@c0:    ; re-map walking distances whenever the player enters a new tile
        lda px+1
        cmp ptx
        bne @new
        lda py+1
        cmp pty
        beq @same
@new:   lda px+1
        sta ptx
        sta cx
        lda py+1
        sta pty
        sta cy
        jsr xyidx
        jsr seenear             ; (the walls around you go on the automap)
        lda curl
        sta bsl
        lda curh
        sta bsh
        lda #0
        sta bfull
        lda #AIRANGE
        sta blim
        jsr bfs
@same:  ldx #MAXTH-1
@loop:  lda EST,x
        cmp #2
        bne @nd
        jsr corpse              ; (falls, lies there, may turn into a pickup)
@nx0:   jmp @next
@nd:    cmp #1
        bne @nx0
        lda ETYP,x
        bpl @mon
        jsr pickup_touch        ; pickups just wait to be walked over
        jmp @next
@mon:   cmp #TY_FIRE
        bne @mo
        jsr fireball
        jmp @next
@mo:    lda EPAIN,x
        beq @np
        dec EPAIN,x
@np:    lda EATK,x
        beq @na
        dec EATK,x
@na:    lda ESEE,x
        beq @ns
        dec ESEE,x
@ns:    lda EWAKE,x
        bne @awake
        jmp @next
@awake: ldy ETYP,x              ; this monster's speed
        lda espeed
        cpy #TY_BRUTE
        bne @sp1
        lsr                     ; brute: 1.5 x
        clc
        adc espeed
        jmp @sp3
@sp1:   cpy #TY_SPIT
        bne @sp3
        lsr                     ; spitter: 3/4
        sta tmp
        lsr
        clc
        adc tmp
@sp3:   sta mspd
        lda EXH,x
        sta cx
        lda EYH,x
        sta cy
        jsr xyidx
        lda curl
        sta nl
        lda curh
        sta nh
        jsr lddst
        sta edist
        sec
        lda px
        sbc EXL,x
        sta edxl
        lda px+1
        sbc EXH,x
        sta edxh
        sec
        lda py
        sbc EYL,x
        sta edyl
        lda py+1
        sbc EYH,x
        sta edyh
        ; ---- spitter: reloads; in sight and not adjacent, it spits and
        ;      holds its ground (closing in only when you're far away)
        lda ETYP,x
        cmp #TY_SPIT
        bne @melee
        lda ETIM,x
        beq @sp0
        dec ETIM,x
@sp0:   lda edist
        cmp #2
        bcc @melee
        lda ESEE,x
        beq @melee
        lda ETIM,x
        bne @hold
        jsr spit
@hold:  lda edist
        cmp #5
        bcs @melee              ; (edist >= 2: walks)
        jmp @next
        ; same or connected neighbouring tile, within one tile -> attack
@melee: lda edist
        cmp #2
        bcs @move
        lda edxh
        beq @inx
        cmp #$FF
        bne @move
@inx:   lda edyh
        beq @atk
        cmp #$FF
        bne @move
@atk:   lda dead
        bne @next
        lda atkcool
        bne @next
        lda #ATKCOOL
        sta atkcool
        jsr msatk               ; attack pose, and a swipe
        ldy ETYP,x
        lda edmg,y
        jsr hurtme
@next:  dex
        bmi @end
        jmp @loop
@end:   rts

@move:  ; ---- target: the player if close, else the next tile along the path
        lda #$80                ; stop half a tile short of the player
        sta pthr
        sta nthr
        lda edist
        cmp #2
        bcc @gr0
        cmp #$FF
        bne @path
@gr0:   jmp @greedy
@path:  sec
        sbc #1
        sta tmp2                ; distance of the tile we want
        stx ei
        lda EXH,x
        sta cx
        lda EYH,x
        sta cy
        jsr xyidx
        ldy #3
@fl:    sty dir
        jsr step
        jsr lddst
        cmp tmp2
        beq @tgt
        ldy dir
        dey
        bpl @fl
        ldx ei
        jmp @greedy
@tgt:   ldx ei
        lda nl
        and #31
        sta tmp                 ; target column
        lda nh
        asl
        asl
        asl
        sta tmp2
        lda nl
        lsr
        lsr
        lsr
        lsr
        lsr
        ora tmp2
        sta tmp2                ; target row
        sec                     ; delta = target tile centre - imp
        lda #$80
        sbc EXL,x
        sta edxl
        lda tmp
        sbc EXH,x
        sta edxh
        sec
        lda #$80
        sbc EYL,x
        sta edyl
        lda tmp2
        sbc EYH,x
        sta edyh
        lda mspd                ; walk all the way to tile centres
        sta pthr
        lda #1
        sec
        sbc mspd                ; 257 - speed
        sta nthr
@greedy:; ---- X: step toward the target unless already close enough
        lda edxh
        bmi @xneg
        bne @xpos
        lda edxl
        cmp pthr
        bcc @ydo
@xpos:  clc
        lda EXL,x
        adc mspd
        sta nxl
        lda EXH,x
        adc #0
        sta nxh
        clc
        lda nxl
        adc #E_MARG
        lda nxh
        adc #0
        jmp @xchk
@xneg:  cmp #$FF
        bne @xn2
        lda edxl
        cmp nthr
        bcs @ydo
@xn2:   sec
        lda EXL,x
        sbc mspd
        sta nxl
        lda EXH,x
        sbc #0
        sta nxh
        sec
        lda nxl
        sbc #E_MARG
        lda nxh
        sbc #0
@xchk:  sta tmp                 ; probe column; check both rows the body spans
        lda EYL,x
        cmp #E_MARG
        lda EYH,x
        sbc #0
        jsr solid
        bne @ydo
        lda EYL,x
        clc
        adc #E_MARG
        lda EYH,x
        adc #0
        jsr solid
        bne @ydo
        lda nxl
        sta EXL,x
        lda nxh
        sta EXH,x
@ydo:   ; ---- Y
        lda edyh
        bmi @yneg
        bne @ypos
        lda edyl
        cmp pthr
        bcc @ny
@ypos:  clc
        lda EYL,x
        adc mspd
        sta nxl
        lda EYH,x
        adc #0
        sta nxh
        clc
        lda nxl
        adc #E_MARG
        lda nxh
        adc #0
        jmp @ychk
@yneg:  cmp #$FF
        bne @yn2
        lda edyl
        cmp nthr
        bcs @ny
@yn2:   sec
        lda EYL,x
        sbc mspd
        sta nxl
        lda EYH,x
        sbc #0
        sta nxh
        sec
        lda nxl
        sbc #E_MARG
        lda nxh
        sbc #0
@ychk:  sta tmp2                ; probe row; check both columns the body spans
        lda EXL,x
        cmp #E_MARG
        lda EXH,x
        sbc #0
        sta tmp
        lda tmp2
        jsr solid
        bne @ny
        lda EXL,x
        clc
        adc #E_MARG
        lda EXH,x
        adc #0
        sta tmp
        lda tmp2
        jsr solid
        bne @ny
        lda nxl
        sta EYL,x
        lda nxh
        sta EYH,x
@ny:    jmp @next

edmg:   .byte DMG, 15, DMG          ; melee damage: imp, brute, spitter
mcol:   .byte C_IMP, C_BRUTE, C_SPIT
kscore: .byte 100, 200, 250         ; points per kill

; hurtme: A = damage to the player (keeps X)
hurtme: sta tmp
        lda dead
        ora god                 ; (god mode: no damage)
        bne @x
        lda #12                 ; (ticks)
        sta hurt
        lda #8                  ; hit sound on its own channel
        sta thump
        sec
        lda health
        sbc tmp
        bcs @hp
        lda #0
@hp:    sta health
        stx ei
        jsr drawhud             ; (first: a fatal hit shows 0%, not what was left)
        lda health
        bne @alive
        jsr player_dies
@alive: ldx ei
@x:     rts

; spit: X = spitter, edx/edy = player - spitter.  Launch a fireball from one
;       of the two reserved things (if both are in flight, try next frame)
spit:   ldy #FB0
        lda EST,y
        beq @got
        iny
        lda EST,y
        beq @got
        rts
@got:   lda #1
        sta EST,y
        sta EWAKE,y
        lda #TY_FIRE
        sta ETYP,y
        lda #FB_LIFE
        sta ETIM,y
        lda #0
        sta EPAIN,y
        sta EATK,y
        lda EXL,x
        sta EXL,y
        lda EXH,x
        sta EXH,y
        lda EYL,x
        sta EYL,y
        lda EYH,x
        sta EYH,y
        ; ---- velocity: (dx, dy) halved until the larger is below FBS,
        ;      then x1.5 if it's under 3/4 of that (speed stays in range)
        lda edxh
        sta rxs
        sta rxh
        lda edxl
        sta rxl
        bit rxs
        bpl @ax
        sec
        lda #0
        sbc rxl
        sta rxl
        lda #0
        sbc rxh
        sta rxh
@ax:    lda edyh
        sta rys
        sta ryh
        lda edyl
        sta ryl
        bit rys
        bpl @nrm
        sec
        lda #0
        sbc ryl
        sta ryl
        lda #0
        sbc ryh
        sta ryh
@nrm:   lda rxh
        ora ryh
        bne @sh
        lda rxl
        cmp #FBS
        bcs @sh
        lda ryl
        cmp #FBS
        bcc @nd
@sh:    lsr rxh
        ror rxl
        lsr ryh
        ror ryl
        jmp @nrm
@nd:    lda rxl
        cmp #FBS*3/4
        bcs @ok
        lda ryl
        cmp #FBS*3/4
        bcs @ok
        lda rxl
        lsr
        clc
        adc rxl
        sta rxl
        lda ryl
        lsr
        clc
        adc ryl
        sta ryl
@ok:    lda rxl
        bit rxs
        bpl @px
        eor #$FF
        clc
        adc #1
@px:    sta EVX,y
        lda ryl
        bit rys
        bpl @py
        eor #$FF
        clc
        adc #1
@py:    sta EVY,y
        lda RANDOM              ; reload time
        and #30
        clc
        adc #SPITCOOL
        sta ETIM,x
        lda #12
        sta EATK,x              ; mouth open
        lda #3                  ; a hiss (channel 1)
        jmp msplay

; fireball: X = thing.  Fly, fizzle on walls or with age, burn the player.
fireball:
        dec ETIM,x
        beq @gone
        clc
        lda EXL,x
        adc EVX,x
        sta EXL,x
        lda EVX,x
        and #$80
        beq @xp
        lda #$FF
@xp:    adc EXH,x
        and #31                 ; (stay on the map whatever happens)
        sta EXH,x
        clc
        lda EYL,x
        adc EVY,x
        sta EYL,x
        lda EVY,x
        and #$80
        beq @yp
        lda #$FF
@yp:    adc EYH,x
        and #31
        sta EYH,x
        lda EXH,x
        sta tmp
        lda EYH,x
        jsr solid
        bne @gone
        stx ei
        sec
        lda px
        sbc EXL,x
        tay
        lda px+1
        sbc EXH,x
        jsr close
        bcc @miss
        ldx ei
        sec
        lda py
        sbc EYL,x
        tay
        lda py+1
        sbc EYH,x
        jsr close
        bcc @miss
        ldx ei
        lda #FB_DMG
        jsr hurtme
@gone:  lda #0
        sta EST,x
        rts
@miss:  ldx ei
        rts

; solid: A = row, tmp = column -> A = map tile (Z clear if not open)
solid:  ldy tmp
        jmp tileval

; =====================================================================
; sprites: pick the two nearest visible enemies and stage them
sprites:
        lda #0
        sta sls
        sta sls+1
        sta slr
        sta slr+1
        ; camera cos/sin (s.7) at the full 10-bit angle; sin = cos(a - 256)
        lda pa
        sta gptr
        lda pa+1
        jsr getcos
        sta csgn
        bpl @cp
        eor #$FF
        clc
        adc #1
@cp:    sta acos
        lda pa+1
        sec
        sbc #1
        jsr getcos
        sta ssgn
        bpl @sp
        eor #$FF
        clc
        adc #1
@sp:    sta asin

        ldx #MAXTH-1
@e:     stx ei
        lda EST,x
        bne @live
        jmp @next
@live:  sec
        lda EXL,x
        sbc px
        sta rxl
        lda EXH,x
        sbc px+1
        sta rxh
        sec
        lda EYL,x
        sbc py
        sta ryl
        lda EYH,x
        sbc py+1
        sta ryh
        ; |rx|, |ry| and signs
        lda rxh
        sta rxs
        bpl @rxp
        sec
        lda #0
        sbc rxl
        sta rxl
        lda #0
        sbc rxh
        sta rxh
@rxp:   lda ryh
        sta rys
        bpl @ryp
        sec
        lda #0
        sbc ryl
        sta ryl
        lda #0
        sbc ryh
        sta ryh
@ryp:   lda #0
        sta accl
        sta acch
        sta accl+1
        sta acch+1
        ; depth = rx*cos + ry*sin  (reject early if behind)
        lda acos
        jsr setmul
        lda rxl
        sta vl
        lda rxh
        sta vh
        jsr pmul
        lda rxs
        eor csgn
        ldx #0
        jsr addp
        lda asin
        jsr setmul
        lda ryl
        sta vl
        lda ryh
        sta vh
        jsr pmul
        lda rys
        eor ssgn
        ldx #0
        jsr addp
        lda acch
        bmi @skA                ; behind the camera
        bne @dok
        lda accl
        cmp #$40                ; closer than 1/4 tile: don't draw
        bcs @dok
@skA:   jmp @next
@dok:   ; lateral = ry*cos - rx*sin  (+ = right); a is still |sin|
        lda rxl
        sta vl
        lda rxh
        sta vh
        jsr pmul
        lda rxs
        eor ssgn
        eor #$80
        ldx #1
        jsr addp
        lda acos
        jsr setmul
        lda ryl
        sta vl
        lda ryh
        sta vh
        jsr pmul
        lda rys
        eor csgn
        ldx #1
        jsr addp
        lda accl+1
        sta latl
        lda acch+1
        sta lath
        ; scale
        lda accl
        sta pl
        lda acch
        sta ph
        jsr scale_of
        sta es
        bne @sok
        jmp @next
@sok:   ; |lateral|
        lda lath
        sta lsgn
        bpl @lp
        sec
        lda #0
        sbc latl
        sta latl
        lda #0
        sbc lath
        sta lath
@lp:    ; P = |lat| * S >> 8 with S the 8.8 scale  (P = t * 256)
        ; x offset = round(2.5 t) = (5P + 256) >> 9
        ; (scale_of above already left the 8.8 scale in sfh:sfl)
        lda latl
        jsr setmul
        ldy sfl
        MUL8                    ; lo*lo: only its high byte counts
        lda prodh
        sta tl
        lda #0
        sta th
        ldy sfh
        MUL8                    ; lo*hi
        clc
        lda tl
        adc prodl
        sta tl
        lda th
        adc prodh
        sta th
        lda lath
        jsr setmul
        ldy sfl
        MUL8                    ; hi*lo
        clc
        lda tl
        adc prodl
        sta tl
        lda th
        adc prodh
        sta th
        bcs @skip
        ldy sfh
        MUL8                    ; hi*hi, lands in the high byte
        lda prodh
        bne @skip
        clc
        lda th
        adc prodl
        bcs @skip
        sta th
        cmp #38                 ; t >= 38: off screen
        bcs @skip
        lda tl
        sta p0
        lda th
        sta p1
        asl p0
        rol p1
        asl p0
        rol p1                  ; 4P
        clc
        lda p0
        adc tl
        lda p1
        adc th                  ; high byte of 5P
        clc
        adc #1                  ; + 256 (round)
        lsr                     ; >> 9
        ldy lsgn
        bmi @lft
        clc
        adc #112                ; X' = screen x + 32
        jmp @gx
@skip:  jmp @next
@lft:   sta tmp
        lda #112
        sec
        sbc tmp
@gx:    sta exq
        ; ---- completely behind walls?  Then it doesn't compete for a slot
        ;      (centre and both edges checked against the depth buffer)
        lda exq
        jsr colvis
        bcs @seen
        ldy es
        lda sprhw,y
        sta tmp
        dec tmp
        lda exq
        sec
        sbc tmp
        jsr colvis
        bcs @seen
        lda exq
        clc
        adc tmp
        jsr colvis
        bcs @seen
        jmp @next
@seen:
        ; ---- insert into the two slots by rank: live monsters first (so a
        ;      pickup can never hide an imp), then nearest first
        ldx ei
        lda es
        lsr
        sta erank
        lda EST,x
        cmp #1
        bne @rk
        lda ETYP,x
        bmi @rk
        lda erank
        ora #$80
        sta erank
@rk:    lda erank
        cmp slr
        bcc @try1
        beq @try1
        lda sle
        sta sle+1
        lda sls
        sta sls+1
        lda slx
        sta slx+1
        lda slr
        sta slr+1
        stx sle
        lda es
        sta sls
        lda exq
        sta slx
        lda erank
        sta slr
        jmp @next
@try1:  lda erank
        cmp slr+1
        bcc @next
        beq @next
        sta slr+1
        stx sle+1
        lda es
        sta sls+1
        lda exq
        sta slx+1
@next:  ldx ei
        dex
        bmi @draw
        jmp @e
@draw:
.ifdef PROF
        lda RTCLOK+2
        sta $0BF4
        lda VCOUNT
        sta $0BF5
.endif
        ldx #0
        jsr drawslot
.ifdef PROF
        lda RTCLOK+2
        sta $0BF6
        lda VCOUNT
        sta $0BF7
.endif
        ldx #1
        jmp drawslot

stglo:  .byte <STAGE2, <STAGE3
bitmask:.byte $80, $40, $20, $10, $08, $04, $02, $01

; ---------------------------------------------------------------------
; drawslot: X = slot.  Resample, occlude and scale one enemy into staging.
drawslot:
        stx slot
        lda stglo,x
        sta sptr
        lda #>STAGE2
        sta sptr+1
        lda #0
        sta slhit,x
        sta slhitw,x
        sta slhpos,x
        lda sls,x
        bne @go
        lda slemp,x             ; empty slot: blank the column (once)
        bne @r
        inc slemp,x
        ldy #63
        lda #0
@clr:   sta (sptr),y
        dey
        bpl @clr
@r:     rts
@go:    sta es
        lda #0
        sta slemp,x
        ldy es
        lda sprm,y
        sta em
        lda sprhw,y
        sta ehw
        lda sprsz,y
        sta slsize,x
        lda slx,x
        clc
        adc #16
        sec
        sbc ehw
        sta slhpos,x            ; HPOS = 48 + screen x - half width
        ; ---- occlusion: a strip is drawn only if the walls at both of its
        ;      edges are farther than the imp (never overlaps a nearer wall)
        ldx slot
        lda slx,x
        sec
        sbc ehw
        sta tmp                 ; X' of bit 0's left edge
        lda #0
        sta vis
        ldy #8
@v:     lda tmp
        jsr colvis
        bcc @vsh
        clc
        lda tmp
        adc em
        sbc #0                  ; (carry clear) -> + em - 1: right edge
        jsr colvis
@vsh:   rol vis
        clc
        lda tmp
        adc em
        sta tmp
        dey
        bne @v
        ; ---- texture + colour by state; tlo = baked + pattern*16
        ldy es
        lda spat,y
        sta tmp
        lda #0
        sta tmp2
        lda tmp
        asl
        rol tmp2
        asl
        rol tmp2
        asl
        rol tmp2
        asl
        rol tmp2
        sta tmp                 ; (tmp2:tmp) = pattern * 16
        ldx slot
        ldy sle,x
        lda ETYP,y
        bpl @mon
        and #$7F                ; pickup: its own picture and colour
        tay
        clc
        lda tmp
        adc pklo,y
        sta tlo
        lda tmp2
        adc pkhi,y
        sta tlo+1
        lda pkcol,y
        jmp @col
@mon:   lda EST,y
        cmp #2
        beq @dying
        lda ETYP,y
        cmp #TY_FIRE
        beq @fire
        sta dtyp
        asl
        adc dtyp                ; 3 frames per type: walk, walk, attack
        sta dtmp
        lda EATK,y
        beq @walk
        lda #2
        bne @fr
@walk:  lda EWAKE,y             ; awake ones step: frame flips every 4 AI ticks
        beq @fr
        lda aifr
        lsr
        lsr
        sta dtyp
        tya
        clc
        adc dtyp
        and #1
@fr:    clc
        adc dtmp
        jsr settex
        ldy sle,x
        lda EPAIN,y
        beq @norm
        lda #C_PAIN
        bne @col
@norm:  ldx ETYP,y
        lda mcol,x
        ldx slot
        jmp @col
@fire:  lda #FIREIDX
        jsr settex
        lda aifr                ; flickers
        lsr
        and #1
        tay
        lda firecol,y
        jmp @col
@dying: lda ETIM,y              ; falls first, then lies there
        cmp #68
        lda #FALLIDX
        bcs @dy
        lda #CORPSEIDX
@dy:    jsr settex
        lda #C_DEAD
@col:
        sta slcol,x
        ; ---- copy the 16 baked rows, clipped by the visibility mask
        lda #0
        sta occ
        ldy #15
@row:   lda (tlo),y
        and vis
        sta OUTROW,y
        ora occ
        sta occ
        dey
        bpl @row
        ; ---- anything visible?  wake it, and see if it covers the crosshair
        ldx slot
        lda occ
        beq @vert
        ldy sle,x
        jsr mswake              ; (a growl the first time it sees you)
        lda #6                  ; (ticks)
        sta ESEE,y
        lda ETYP,y
        cmp #TY_FIRE            ; fireballs never block your shots
        bne @tg
        jmp @vert
@tg:
        lda slx,x               ; shotgun: anything within ehw + 12 of centre
        sec
        sbc #112
        bcs @pp
        eor #$FF
        adc #1
@pp:    sta tmp
        lda ehw
        clc
        adc #12
        cmp tmp
        bcc @nw
        lda #1
        sta slhitw,x
@nw:    lda slx,x
        sec
        sbc ehw
        sta tmp                 ; X' left edge
        lda #112                ; X' of screen centre
        sec
        sbc tmp
        bcc @vert               ; centre left of sprite
        ldy es
        ldx sprsh,y
        beq @sh0
@sh:    lsr
        dex
        bne @sh
@sh0:   cmp #8
        bcs @vert
        tax
        lda bitmask,x
        and occ
        beq @vert
        ldx slot
        lda #1
        sta slhit,x
@vert:  ; ---- vertical scaling into view rows
        ldy es
        lda htab,y
        sta eH
        lda dvl,y
        sta dvlo
        lda dvh,y
        sta dvhi
        ldx slot                ; pickups stand half as tall, on the floor
        ldy sle,x
        lda ETYP,y
        bpl @full
        lsr eH
        bne @h1
        inc eH
@h1:    asl dvlo
        rol dvhi
@full:
        lda es
        cmp #32
        bcc @b1
        lda #32
@b1:    clc
        adc #32
        sta ebot                ; one past the bottom row (<= 64)
        clc
        lda #32
        adc es
        sta tl
        lda #0
        adc #0
        sta th
        sec
        lda tl
        sbc eH
        sta tl
        lda th
        sbc #0
        sta th                  ; top row, signed
        bpl @tpos
        lda #0
        sec
        sbc tl                  ; rows clipped off the top
        jsr setmul
        ldy dvlo
        jsr mul8
        lda prodh
        sta tmp
        ldy dvhi
        jsr mul8
        clc
        lda prodl
        adc tmp
        sta vlo
        lda prodh
        adc #0
        sta vhi
        lda #0
        sta rstart
        beq @rows
@tpos:  lda tl
        sta rstart
        lda #0
        sta vlo
        sta vhi
@rows:  ldy #0                  ; blank rows above the sprite
        lda #0
@ab:    cpy rstart
        bcs @rl
        sta (sptr),y
        iny
        bne @ab
@rl:    cpy ebot
        bcs @below
        ldx vhi
        cpx #16
        bcs @below
        lda OUTROW,x
        sta (sptr),y
        clc
        lda vlo
        adc dvlo
        sta vlo
        lda vhi
        adc dvhi
        sta vhi
        iny
        bne @rl
@below: lda #0                  ; ... and below it
@bl:    cpy #64
        bcs @done
        sta (sptr),y
        iny
        bne @bl
@done:  rts

; settex: A = texture number -> tlo = its baked rows for pattern (tmp2:tmp)
settex: tay
        clc
        lda tmp
        adc texlo,y
        sta tlo
        lda tmp2
        adc texhi,y
        sta tlo+1
        rts
firecol:.byte $2E, $3A

; ---------------------------------------------------------------------
; colvis: A = X' (screen x + 32).  Carry set if the wall in that column is
;         farther than the current imp (scale es); off-screen counts as hidden
colvis: cmp #32
        bcc @no
        cmp #192
        bcs @no
        sbc #31                 ; carry clear here: subtracts 32
        lsr
        tax
        lda ZB,x
        cmp es                  ; wall scale < imp scale -> wall is behind
        bcs @no
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------------
; hitscan: damage the nearest enemy under the crosshair last frame
hitscan:
        ldx weapon
        lda wdmg,x
        sta dmg
        cpx #1
        bne @single
        ldx #0                  ; shotgun: every monster in the blast
        lda slhitw
        beq @s2
        jsr hurtslot
@s2:    ldx #1
        lda slhitw+1
        beq @x
        jmp hurtslot
@single:ldx #0                  ; nearest monster under the crosshair
        lda slhit
        bne @h
        inx
        lda slhit+1
        beq @x
@h:     jmp hurtslot
@x:     rts

; hurtslot: X = sprite slot; damage its thing by dmg if it's a live monster
hurtslot:
        ldy sle,x
        lda EST,y
        cmp #1
        bne @no
        lda ETYP,y
        bmi @no
        cmp #TY_FIRE
        beq @no
        lda #12                 ; (ticks)
        sta EPAIN,y
        jsr mswake
        lda EHP,y
        sec
        sbc dmg
        beq @kill
        bcc @kill
        sta EHP,y
@no:    rts
@kill:  lda #0                  ; (a dead monster's hit points mark what its body
        cpy keyby               ;   drops: 0 ammo or health (corpse), $FF nothing
        bne @kd                 ;   more: the keycard's carrier)
        lda #$FF
@kd:    sta EHP,y
        jsr mskill               ; death cry; the keycard's carrier drops it
        lda #2
        sta EST,y
        lda #80                 ; corpse stays ~4 seconds (ticks)
        sta ETIM,y
        inc kills
        clc
        lda tadm                ; +time for the kill
        adc #T_KILL
        sta tadm
        ldx ETYP,y
        lda kscore,x
        ldx #0
        jsr addscore
        jsr drawscore
        jmp drawhud

; ---------------------------------------------------------------------
; Weapons:            pistol shotgun chaingun
wdmg:   .byte 6, 12, 3          ; damage per hit, in half points: 3, 6 and 1.5
wcost:  .byte 1, 1, 1           ; ammo per shot (each gun has its own)
wcool:  .byte 12, 45, 7         ; frames (1/60 s) between shots
wauto:  .byte 0, 0, 1           ; fires while held
wflash: .byte 8, 13, 7          ; muzzle flash / shot sound length
wcolor: .byte $00, $30, $06     ; gun colour: pistol black, shotgun dark red-brown, SMG dark silver
wkeys:  .byte $1F, $1E, $1A     ; keys 1, 2, 3
keytxt: .byte $2B, $25, $39     ; "KEY"

; setgun: draw the current weapon into players 0/1
setgun: lda weapon
        asl
        asl
        asl
        asl
        tax
        ldy #0
@g:     lda gungfx3,x
        sta P0MEM+GUNTOP,y
        lda handq3,x
        sta P1MEM+GUNTOP,y
        inx
        iny
        cpy #16
        bne @g
        ldx weapon
        lda wcolor,x
        sta guncol
        sta PCOLR0
        rts

; pausek: START during play pauses (on the title / game over it rolls a seed)
pausek: lda srreq
        beq @x
        lda dead
        beq pause
@x:     rts
; pause: hold everything (the VBI stops the clock and sound) until P or START
pause:  lda #1
        sta paused
        lda #0
        sta srreq
        sta AUDC1
        sta AUDC2
        sta AUDC3
        sta AUDC4
        lda #<msg_pause
        ldy #>msg_pause
        jsr putmsg
@w:     lda srreq
        bne @go
        lda CH
        cmp #$FF
        beq @w
        ldx #$FF
        stx CH
        and #$3F
        cmp #$0A                ; P
        bne @w
@go:    lda #0
        sta srreq
        sta paused
        jsr tickrs              ; (no catching up on the paused time)
        jmp showlevel

textoggle:
        lda lods
        cmp #LODS
        bne @on
        lda #255
        sta lods
        lda #<msg_texoff
        ldy #>msg_texoff
        jmp showmsg
@on:    lda #LODS
        sta lods
        lda #<msg_texon
        ldy #>msg_texon
        jmp showmsg

; selweapon: X = weapon wanted (keys 1-3)
selweapon:
        lda owned,x
        bne @own
        lda #<msg_noweapon
        ldy #>msg_noweapon
        jmp showmsg
@own:   stx weapon
        jsr setgun
        jmp drawhud

; touchdoor: walked into the exit
touchdoor:
        lda locked
        beq @open
        lda havekey
        bne @open
        lda #<nmsg
        ldy #>nmsg
        jmp showmsg
@open:  lda #1
        sta won
        rts

; setdoor: A = exit tile value (2 open, 4 barred)
setdoor:inc forcer              ; (a door changes: draw the view again)
        pha
        lda btl
        sta nl
        lda bth
        sta nh
        pla
        jmp stmap

; close: Y/A = low/high of a signed 8.8 distance; C set if |d| < 0.4 tile
close:  cmp #0
        beq @pos
        cmp #$FF
        bne @no
        cpy #$9A
        rts
@pos:   cpy #$66
        bcs @no
        sec
        rts
@no:    clc
        rts

; =====================================================================
; Image B variables (RAM $B800-$BFFF; main program only, never interrupts)
.segment "BSS3"
nimp:   .res 1          ; imps this level
weapon: .res 1          ; 0 pistol, 1 shotgun, 2 chaingun
owned:  .res 3          ; weapons you have
havekey:.res 1
locked: .res 1          ; this level's exit needs the key
msgt:   .res 1          ; game frames until the message line reverts
slr:    .res 2          ; slot rank (monsters outrank pickups)
slhitw: .res 2          ; slot hit by a shotgun blast
erank:  .res 1
dmg:    .res 1
hallx:  .res 4          ; halls: top-left tile, size in tiles
hally:  .res 4
hallw:  .res 4
hallh:  .res 4
hw:     .res 1          ; carvehall / ringhall work
hh:     .res 1
hw2:    .res 1
hh2:    .res 1
hx0:    .res 1
hry:    .res 1
hsty:   .res 1          ; room wall style
ldir:   .res 1          ; backtracker: last direction carved
lastdir:.res 1          ; heading tape: last heading drawn
nroom:  .res 1
ncell:  .res 1          ; maze size this level, in cells per side
maxc:   .res 1          ; 2 * ncell: the last tile row/column (wall)
lim:    .res 1
ncm1:   .res 1
curl:   .res 1          ; tile being worked on (low byte, page) ...
curh:   .res 1
nl:     .res 1          ;   ... and a neighbour of it
nh:     .res 1
dir:    .res 1
mstl:   .res 1          ; start tile
msth:   .res 1
btl:    .res 1          ; exit door tile
bth:    .res 1
bsl:    .res 1          ; bfs start, limit, clear-all flag
bsh:    .res 1
blim:   .res 1
bfull:  .res 1
pkx:    .res 1
pky:    .res 1
tmp3:   .res 1
lx:     .res 1          ; braid: cell being looked at ...
ly:     .res 1
bod:    .res 1          ;   ... its one opening
bdr:    .res 1          ;   ... walking its corridor
blen:   .res 1
svl:    .res 1
svh:    .res 1
bt:     .res 8          ; per band: taller ray's nibble ...
bb:     .res 8          ;   ... and both rays' byte
rt:     .res 8          ; band runs: taller ray's nibble, both rays' byte,
rb:     .res 8
rk:     .res 8          ;   end band * 32 (0 = the last)
rdirty: .res 1          ; bt / bb changed: rebuild the runs
bk:     .res 1          ; run number
tbase:  .res 1          ; the ray's shade (for its band offsets)
kside:  .res 1          ; band cache: which ray, texture id and shade bt holds
ktid:   .res 1
kshade: .res 1
kstid:  .res 1          ;   and the shorter ray's that bb holds
ksshade:.res 1
ptx:    .res 1          ; player tile the monsters' distance map is from
pty:    .res 1
EATK:   .res MAXTH      ; attack-pose frames left
ESEE:   .res MAXTH      ; frames since it was last seen on screen (counts down)
EVX:    .res MAXTH      ; fireball velocity, signed 1/256 tile per frame
EVY:    .res MAXTH
nbrute: .res 1
nspit:  .res 1
thp:    .res 3          ; hit points by monster type this level
mspd:   .res 1          ; this monster's speed
aifr:   .res 1          ; AI frame counter (animation)
dtyp:   .res 1          ; drawslot scratch
dtmp:   .res 1
RCC:    .res 80         ; per ray: shade
RIDL:   .res 40         ; per even ray: tile hit (low byte) ...
RIDH:   .res 40         ;   ... and page * 2 + face

.include "menu.s"
.include "ending.s"

; things, part 1: page 4 (the OS's cassette buffer; no cassette here)

.segment "BSS5"                 ; ($BA00: free since the display lists moved under the OS)
ammop:  .res 3          ; ammo for each gun (ammo, in zero page: the gun in hand's)
pkw:    .res 1          ; pickup_touch: the gun whose ammo it was
mirl:   .res 2          ; the stripe tiles west and north of the exit (map index low,
mirp:   .res 2          ;   page * 2 as in hitid): mirrored stripes
.segment "BSS4"
EXL:    .res MAXTH      ; things: position 8.8
EXH:    .res MAXTH
EYL:    .res MAXTH
EYH:    .res MAXTH
EST:    .res MAXTH      ; 0 gone, 1 active, 2 dying (corpse)
EHP:    .res MAXTH
EPAIN:  .res MAXTH
EWAKE:  .res MAXTH
ETIM:   .res MAXTH
ETYP:   .res MAXTH      ; TY_* / PK_*

.include "items.s"
.include "tunnel.s"

; small routines moved out of image A, into RAM the OS never uses here
; (copied there by the menu, like the rest of the overlay's resident code)
.segment "ZRF"                  ; ($03B6: IOCB 7 tail and the printer buffer)
; readfire: Z set to fire: a fresh press (taken), or, for the SMG, held
readfire:
        lda demo
        beq @rf
        lda bfirev
        rts
@rf:    lda trigl
        beq @held
        lda #0
        sta trigl
        rts
@held:  ldx weapon
        lda wauto,x             ; the SMG fires while held
        beq @no
        lda STRIG0
        rts
@no:    lda #1
        rts
.segment "ZMU"                  ; ($04F0: page 4, after the things)
mul8:   sec
        lda (msl),y
        sbc (mml),y
        sta prodl
        lda (msh),y
        sbc (mmh),y
        sta prodh
        rts
.include "osram.s"
