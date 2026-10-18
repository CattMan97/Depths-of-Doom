# Depths of Doom

A maze-based first-person shooter for Atari 8-bit computers.

The bigger-cartridge sequel to **Mazes of Doom**: the same seeded, timed maze runs, plus
weapons, pickups, locked exits that need a key, three kinds of animated monster,
bigger mazes (23x23 tiles), and a heading tape and compass.

- **Machine:** any Atari XL/XE with **64K RAM, including the RAM under the OS ROM**, such
  as an 800XL, 130XE or a 600XL with a 64K (or larger) upgrade. Every stock 64K XL/XE has
  it; on a machine without it the cartridge says so on a red screen instead of starting.
  Extended memory banks aren't needed. NTSC.
  `tools/memtest/MEMTEST.CAR` (an 8K cartridge) checks a machine: RAM under the OS ROM,
  extended banks, and a looping test of all of it.
- **Cartridge:** `DEPTHS_OF_DOOM.CAR` is a **128K switchable XEGS** image (.CAR type 35). It
  runs on the A8PicoCart and similar flash carts.

**To play:** download `DEPTHS_OF_DOOM.CAR` from the repository's
[Releases](https://github.com/CattMan97/Depths-of-Doom/releases) and put it on a flash cartridge, or run it in an emulator
(Altirra or atari800) set up as a 64K XL/XE, NTSC. To build it yourself, see Building.

## How it boots
1. The loader in the cartridge's fixed bank (bank 15, `$A000-$BFFF`) checks that there is
   RAM under the OS ROM, then switches the **OS ROM off for good**: it copies the OS's
   character set into the RAM under it (`$E000-$E3FF`) and copies the game's code for that
   RAM from banks 10-11 (interrupt handlers, display lists, drawing code, tables; see
   `osram.s`). Then it copies image A from banks 0-1 into RAM at `$4000-$7FFF`. The
   screen is off throughout.
2. Image A copies image B from banks 2-3 to `$8000-$BFFF`. Each bank appears at `$8000`,
   which is also where it has to go, so it's staged through `$2000`, with the cartridge
   switched off between the two copies.
3. The game switches the cartridge **off** (bit 7 of `$D5xx`). It first turns off the
   built-in BASIC (`PORTB` bit 1). With a cartridge in, the XL OS leaves BASIC enabled,
   and once the cartridge goes away BASIC would appear at `$A000-$BFFF` instead of RAM.
   From then on `$8000-$BFFF` is ordinary RAM; the cartridge comes back only for a
   moment, with interrupts off, to fetch a music track, the tunnel picture, an overlay
   or the ending.
4. It sets up RESET (below) and opens the **main menu** (see below).

**RESET restarts the game.** On an XL, RESET resets the chips: the OS ROM and BASIC come
back and the OS warm-starts, which can't see the (switched-off) cartridge. But it calls
`DOSINI` first when `BOOT?` says a disk booted, so the game points that at a 22-byte stub
(`$01CA`, in the stack page below where the stack ever reaches) that switches the
cartridge back on and cold-starts. (Like a power-cycle, it clears the high score.)

## Weapons
| Weapon | Found | Ammo per shot | Damage | Fire |
|---|---|---|---|---|
| Pistol | at the start | 1 | 1 (an imp takes 3) | about 4 shots/s at most |
| Shotgun | from level 2 | 2 | 3 (kills an imp) | slow, and hits every imp near the crosshair |
| SMG | from level 4 | 1 | 1 | automatic while held, about 6 shots/s |

Picking up a weapon switches to it and gives some ammo (+10 for the shotgun, +20 for the
SMG). In your hand the pistol is black, the shotgun brown and the SMG silver. A weapon you don't have yet lies somewhere in each level until you find it.

## Pickups
Green **ammo** clips (+16 at first, growing with monster toughness: +18 on level 4,
+30 on level 10; max 99), red **health** packs (+25%, max 100%) and yellow
**hourglasses** (+30 s on the clock). Walk over them to collect. A pickup stays
where it is while that stat is full (99 ammo, 100% health, 5:00 on the clock), so you
can come back for it; standing on it says **AMMO MAX**, **HEALTH MAX** or **TIME MAX**. Later levels have more:

| Level | 1-3 | 4-6 | 7 | 8-9 | 10-12 | 13-14 | 15 |
|---|---|---|---|---|---|---|---|
| Ammo | 2 | 3 | 4 | 4 | 5 | 6 | 6 |
| Health, hourglasses (each) | 1 | 1 | 1 | 2 | 2 | 2 | 3 |

(Ammo: 2 + (level - 1) / 3. Health and time: 1 + (level - 1) / 7.)

## Keycards and locked exits
From level 3 the exit is **dark and locked**: the door panels, in the level's colour.
The **keycard** is the same colour (gray, gold, violet or teal). One of the level's
monsters, picked at random, carries it, and drops it where it dies; the level's clock
still includes time for a detour. The bottom line says **FIND THE EXIT DOOR!** until
you've seen the exit, then **FIND THE <colour> KEYCARD, THEN EXIT!** for a few
seconds, then **KILL THE MONSTERS TO GET THE KEYCARD!** (or the keycard line again once
it has been dropped). Once you have it, the HUD shows `KEY`, the exit opens
(**KEYCARD ACCEPTED - THE EXIT IS OPEN**), and the line goes back to finding the exit.

An open exit is plain glowing white, the same white as the chevron stripes beside it.

Every level also has an **entrance**: the door you came in by, on the wall behind you
at the start (or beside you, if you start in a straight corridor). It looks like a
locked exit, without the stripes, and never opens.

## Room to grow
| Space | Size | Planned use |
|---|---|---|
| Image A `$4000-$7FFF` | about 0.9K free (plus the start-up area, reused) | engine core and everything interrupts run |
| Image B `$8000-$B7FF` | about 140 bytes free | gameplay code |
| RAM under the OS ROM | about 2.8K free (`$CD00-$CFFF`, `$DC30-$DFFF`, `$FC00-$FFF9`) | more fast code and tables |
| RAM `$3A50-$3BDC`, `$BA00-$BB8C` | about 0.8K | (the old shared display lists) |
| RAM `$B800-$B9FF` | about 0.1K free | things (24 slots, with page 4), weapon and maze state |
| Cartridge bank 4 | about 4K free | the overlay (menu, wake-up scene, demo, game-over banner) and resident extras |
| Cartridge bank 5 | about 1.5K free | the ending's code (its area at `$1000` holds 2.75K) |
| Cartridge banks 6-7 | about 11K free | the ending's pictures and walking frames |
| Cartridge bank 8 | about 5.5K free | the tunnel picture |
| Cartridge bank 9 | 4K free | music: 16 tracks, a page each |
| Cartridge banks 10-11 | about 3K free | the code for the RAM under the OS (13K) |
| Cartridge banks 12-14 | 24K, empty | sound effects, more graphics, more levels |

Image A holds everything the interrupts touch, because cartridge banks are paged in
over `$8000-$BFFF` (with interrupts off) to load music, the tunnel and the overlays.
The 320K expansion's extended banks aren't used yet: they could hold more content on
machines that have them, but the game must keep running on a plain 64K machine.

## History
1. **Platform port** from Mazes of Doom (stock 16K) to a 128K cartridge.
2. **Weapons, pickups, keycards and locked doors.**
3. **New monster types and animation.**
4. **Textured walls and bigger 32x32 maps,** drawn in GTIA mode 9.
5. **Story and structure:** the wake-up scene, 15 levels and the ending, the tunnel
   between levels, braided mazes, the entrance door, keycards carried by monsters.
6. **Music and sound:** 16 tracks, monster sounds, louder gunshots.
7. **Speed:** the OS ROM switched off and its RAM used for the drawing code (about
   10 to 14 fps); RESET restarts the game.

Bug reports and ideas go in the repository's Issues.

## Controls (joystick, port 1)
- **Up / Down**: walk forward / back
- **Left / Right**: turn. Starts slow for fine aiming and speeds up while held.
- **Fire**: shoot. You start with 50 rounds; all weapons share the ammo. The trigger is
  read every 1/60 s and each press is kept until it fires, so quick taps are never
  lost, and a tap during the gun's recovery fires as soon as it's ready. The game
  checks for a shot every game tick (1/20 s) and again between casting the rays and
  drawing the walls.
- **1 / 2 / 3** (keyboard): pistol, shotgun, SMG, once you've found them
- **T** (keyboard): room textures on/off
- **P** (keyboard) or **START**: pause / resume. The clock, monsters and music all stop.
- **SELECT**: automap on/off
- **OPTION**: music on/off
- **G** (keyboard, for testing): god mode on/off. No damage, ammo never runs down,
  and the clock holds. The bottom line says GOD MODE when it goes on.
- **RESET**: restarts the game from the title (clears the high score, like turning the
  machine off and on).
- **L** (keyboard, for testing): level select. Everything holds; the stick up / down
  picks a level 1-15 (it wraps), fire goes there, any key cancels. You keep your
  health, weapons and score, and the clock gets that level's time on top.

Every level is a **new maze**, built from a 4-digit **seed** shown on the upper HUD.
- **Main menu:** the title (the DOOM drips blood: each letter grows drips that swell
  and let go of drops that fall down the screen), and two choices picked with the stick (up / down) and
  started with fire, START or RETURN: **Start with a random seed**, or **Play your own
  seed**. Typing 4 digits sets your seed (the newest digit shifts in from the right)
  and moves to that option. The menu also shows the high score.
- **Waking up:** a run started from the menu opens on your eyes: dark, a slit of
  light, a blink, then the corridor. You wake in the maze with no memory of how you
  got there; the story lines play on the bottom line, ending with a flashing **YOU
  MUST ESCAPE.** Then the clock starts. Fire skips it. (R retries and the demo skip it.)
- **Between levels:** walk through the exit and a zooming tunnel of colour fills the
  view, 2600-style, with a rushing noise, while the next level is built. The level's music
  stops for it, and the next level's starts when you arrive (about 1.5 s;
  the clock holds). It's GTIA mode 10: a picture of rectangular rings (bank 8) whose
  six colour registers rotate every few frames, so the rings rush at you while their
  hues drift.
- **15 levels, then the end:** clearing level 15 gets you out. The ending plays: you
  walk down the last corridor toward a door full of daylight, the light swallows
  everything, and out of the glare comes a ruined city under a dusty sun, with you
  standing on a ledge looking at it. **THE END** fades in. Any key, fire or START goes
  back to the menu (your score counts toward the high score).
- **Demo:** leave the menu alone for about 30 seconds and the game plays itself on a
  random seed: a bot wanders the maze (mostly straight on, turning at random at
  junctions) and shoots monsters in front of it. Any key, the stick, fire or a console
  key returns to the menu, and so does the demo ending (about 50 seconds) or dying.
  Your typed seed is kept, and the demo doesn't set high scores.
- **Same seed, same run:** each level is built from the seed and the level number
  only. Seed `0420` level 3 is the same maze, start and imp positions every time, even
  after a power cycle. Write a seed down to come back to a run, or share it.
- **After a game over:** **GAME OVER** appears across the view, tinted **red** if you
  died or **yellow** if the clock ran out (the monsters disappear), and the bottom line
  says why. **R** retries the same seed from level 1; **START** goes back to the main
  menu. Fire does nothing, so a stray press can't throw a run away.

## Walls and screen
- **The 3D view is in GTIA mode 9:** 80x64 chunky pixels in **16 shades of one hue**,
  instead of 4 colours. Walls fade into the dark with distance, and the ceiling and
  floor are gradients from light gray at the screen edges to black at the horizon.
- **Every wall is textured** (16 columns by 8 rows per half wall, mirrored below the
  horizon), as darker and lighter shades of the wall's own shade. Lit faces are a few
  shades lighter than shaded ones, and everything darkens with distance.
- **Corridor walls** have a dark trim at the top and bottom and a dark rail at eye
  level.
- **Each room has its own wall style**, picked at random from ten: bevelled plates,
  vents, pillars, framed tech panels with lights, bricks, pipes, light strips,
  grating, ribbed panels and circuit traces.
- **The exit door:** while it's locked it's a **dark** framed double door; once it's open
  it's plain **glowing white**, the brightest shade on screen. The walls either side of
  it have bright chevron stripes that scroll, so it stands out down a corridor. The
  entrance door looks like a locked exit, without the stripes.
- Walls farther than about 5 tiles are drawn solid. Keycards and monsters are still in colour (they're sprites).
- **Every level has a tint**, cycling gray, gold, gray, purple, gray, teal (`theme1` in
  `depthsofdoom.s`). The whole view turns red when you're hurt.
- **T** switches the textures off: plain shaded walls, a little faster to draw. The game
  runs in ticks of 1/20 s, so you and the monsters move at the same pace either way.

## Monsters
Monsters wake up once they've seen you and then hunt you through the maze. They follow
corridors around corners and attack when they reach you.

| Monster | From | Toughness (pistol hits) | Speed | Attack | Kill |
|---|---|---|---|---|---|
| **Imp** (brown) | level 1 | 3 until level 3, then +1 a level (4 on level 4 ... 12 max) | normal | claws, 10% | 100 pts |
| **Brute** (pink) | level 3 | 1.5 × imp + 2 (6 on level 3, 17 on level 10) | 1.5 × imp | bite, 15% | 200 pts |
| **Spitter** (green) | level 5 | imp + 1 | 3/4 × imp | fireballs, 12% each; claws up close | 250 pts |

- **Spitters** stop and hold their ground once they can see you within 4 steps. Every 2–4
  seconds they spit a fireball (flickering yellow) straight at where you were standing.
  Sidestep it or duck around a corner: fireballs burst on walls. You can shoot through a
  fireball at whatever is behind it. At most two fireballs are in the air at once.
- **Monsters per level:** level + 3, up to 8. Brutes: 1 on levels 3–4, 2 on levels 5–6,
  3 from level 7. Spitters: 1 on levels 5–6, 2 on levels 7–8, 3 from level 9. The rest
  are imps. Everything gets a little faster every level.
- **Animation:** awake monsters walk with a two-frame step, rear up when they attack,
  flash white when hit, and collapse before their corpse fades.
- **Reaching the exit door:** you get +20 ammo (max 99) and +25% health (max 100%),
  then the next level is generated. The door is always as far from your start as the maze
  allows, measured by walking distance to its nearest open side.
- **Game over:** at 0% health or when the clock hits 0:00. R retries the seed, START
  goes to the main menu.

## The clock
The clock (right end of the top bar) counts **down**.
- **A new game starts with 3:00** on the clock (`T_START`).
- **Each later level adds time:** 30 s, plus 2 s for every step from your start to
  the exit (about three times what walking straight there takes), plus 2 s per step
  of the keycard detour on locked levels.
- **Time carries over:** whatever is left when you reach the exit stays on the clock.
- **Each kill adds 10 s**, and an hourglass 30 s.
- **Maximum:** the clock never holds more than 5:00, so you can't bank an endless
  cushion. (A single level grants at most 240 s, plus at most 120 s for the key detour.)
- **Under 30 s** the clock blinks. **Under 15 s** the music speeds up, and **under
  10 s** it ticks every second.

The tuning constants are at the top of `depthsofdoom.s`: `T_LEVEL`, `T_KILL`, `T_CAPM`,
`T_PANIC`, `T_FLASH`, `E_SPEED`/`ESTEP`, and `TURN0`/`TURNUP`/`TURNMAX`.

## Automap
SELECT switches the view to a top-down map (in 4-colour mode D, so it keeps its colours) of the whole 32x32 area (each tile is 4x2
pixels). Only walls you've actually seen are shown:
every wall a ray hits gets marked. Walls are red, the exit door is yellow (once you've
seen it), the entrance is green, and you're the white block, with a yellow nose showing
which way you face. Pickups you've seen on screen are small dots: yellow, or white for
the keycard. (The green mark is missile 0, recoloured while the map is up, since mode D
has only four colours.) A
compass rose (north up) sits in the right margin. The game keeps running while the
map is up and you can walk, but you can't fire.

## Score
The top bar shows `SCORE`, `LEVEL`, `HIGH`, `SEED` and the clock.
- **Each monster killed:** 100 (imp), 200 (brute) or 250 (spitter) points.
- **Each level finished:** 500 × the level number.
- **Time bonus:** 10 points for every second left on the clock when you reach the exit.
- **High score:** kept until power-off.

## Music
Sixteen original tracks: a title theme and one for each level, in a dark industrial /
tech-noir style (written for this game; `music.py`): minor keys, a sequenced buzzing
bass and four-on-the-floor drums. Each is 12 bars that loop. The title runs at 100 BPM,
levels 1-7 at 112 BPM and levels 8-15 at 128 BPM.
- **Bass (POKEY channel 3):** sequenced lines (driving 8ths, octave flicks, gallops,
  tresillos) in a deep buzz (distortion C, down to E1). Each track carries its own
  24-note bass tuning table: the buzzy tone is only in tune for divider values coprime
  to 15.
- **Lead (channel 4):** a sparse pure-tone lament, after four bars of bass alone.
- **Drums (channel 2):** a mechanical beat (heartbeat, march, piston, machine...) on the
  hit-sound channel; a hit or pickup sound simply takes over for a moment.

The track playing sits in a 224-byte buffer in image A; the others wait in cartridge
bank 9, one page each, and are copied in when a level starts (the title theme when the
menu opens). The music still races when the clock is short. OPTION turns it off.

## Maze generation (6502, in RAM)
The map array is 32x32 tiles; every level's maze is the same size, **11x11 cells
(23x23 tiles)**, set by `MAZEN` at the top of `depthsofdoom.s` (7 = the original
15x15, 15 = the largest).

1. A recursive backtracker carves a perfect maze, turning freely, so corridors are
   short (`STRAIGHT` = chance in 4 of carrying straight on; 0 now).
2. Random walls are knocked out for loops: `LOOPS` per cell row (4 now, 44 a maze).
3. Two or three **small rooms** (3x3 or 5x5 tiles) are carved, always at least a
   corridor apart, so they're joined by corridors.
4. **Braiding:** every dead end is followed back to the nearest junction. If that's
   more than `SHORT` cells (2 now) away, the dead end is knocked through into the next
   cell, straight on where it can. So the only dead ends left are short stubs off a
   junction, and long blind corridors become cut-throughs. (This code runs from the
   unused half of the maze generator's stack pages, copied there by the menu.)
5. A breadth-first search from the start tile places the exit door on the wall whose
   nearest open side is farthest away. Monsters go on open tiles at least 6 steps from
   the start. Building a level takes about half a second.
6. The random source is a 16-bit xorshift generator, reseeded at the start of every
   level from the seed digits (as BCD) and the level number. It's purely software, so
   results are repeatable. POKEY's `RANDOM` register is only used to roll random seeds.

## How it works
- **Display:** GTIA mode 9: ANTIC mode F lines, 80 pixels across, each byte two
  4-bit pixels whose value is the **luminance**; the background register holds the hue.
  The frame buffer is 64 rows of 40 bytes, and the display list shows every row twice
  (128 scanlines, an LMS on every line). It's **triple-buffered**, with a fixed display
  list for each buffer (in the RAM under the OS), so a finished frame only needs its
  list's address. The VBI flips to it and swaps in its sprites at the same moment, so
  the main loop never waits for vblank.
  - **The bottom half is the top half's mirror,** row for row (the walls, the textures,
    the ceiling and floor are all symmetric about the horizon), so the display lists
    show rows 32-63 as rows 31-0 and only the top half is ever drawn. The GAME OVER
    banner isn't symmetric: game over copies the top half down and shows the frame
    through a plain list.
- **Interrupts:** a display-list interrupt turns GTIA mode 9 on (PRIOR) and sets the
  hue just before the view, and another turns it off for the bottom bar. The automap
  uses its own two mode D display lists, and the interrupt follows whichever list is
  actually on screen.
- **Shading:** each ray's wall shade comes from its distance (a fog table), with lit
  and shaded faces a few steps apart. Textures are stored as brightness offsets from
  that shade, clamped to 0-15. The ceiling and floor are 8 bands of 4 rows each,
  written as runs split at the band edges.
- **Walls:** Grid DDA in 8.8 fixed point, using quarter-square multiplies and 1/cos
  tables over a 1024-step circle, with fisheye correction. Each ray stores its
  projected scale in a depth buffer.
  - **Ray interpolation:** only rays 0, 8, 16 .. 72, 76, 78 and 79 are always cast
    (unrolled, every index a constant: `interp` in `osram.s`).
    Every other ray lies between two known rays; if both hit the same face of the same
    tile (and are both textured or both not: bit 7 of the hit id), the wall between
    them is one plane, so its scale (1/distance), texture column and shade are the
    average of theirs. Otherwise it's cast. Rays 4, 12 .. 68
    are filled in first, then 2, 6 .. 74, then the odd rays. In play only about 1 in 10
    needs casting. The exit stripes' scroll is added after this, so it doesn't break
    the averaging.
  - **No OS:** the OS ROM is switched off, and the game's own handlers (`osram.s`) take
    the 6502's vectors: the NMI sends DLIs through `VDSLST` and VBIs through `VVBLKI`
    as the OS did, and the IRQ handler reads the keyboard into `CH` with the OS's
    debounce. The VBI does only what the game needs (the clock, the colour /
    display-list / DMA / priority shadows, the joystick and trigger, keyboard debounce),
    then runs the game's VBI. No attract mode. The 14K of RAM under the ROM holds the
    fast code and tables below.
  - The map index lives in X during the DDA. Tiles are 16-bit (row x 32 + column), so
    the map page is patched into the DDA's load instructions and bumped when a ray
    crosses an 8-row boundary.
  - **Textures:** each ray works out where it hit along the wall (one multiply) and
    picks one of 16 texture columns (corridor walls are the same in every column, so
    they skip this). The top half of the wall is split into 8 bands; band k ends at
    row 32 - s + k s / 8 (a table, `bendt`: a page per band, by scale). Each band's shade is the ray's shade
    plus the texture's offset, through a 32-entry table that clamps it. Neighbouring bands with the same value
    are merged into one run, and a pair whose rays have the same textures and shades
    as the last pair reuses its runs.
  - The generated column writers (one `STA row,X` per row, per buffer) write a run
    of rows from one entry point to an `RTS` put in for the call. `dpairs` (in
    `osram.s`) draws the 40 byte columns: each is a handful of runs, top half only.
    Rows above the last frame's wall top in that buffer are already ceiling, so
    only the rows that changed are painted.
- **Enemies:** Player 2 and player 3 show the two nearest visible monsters, fireballs or pickups (live monsters and fireballs first). Each picture is one of 12 pre-baked frames (three per monster type, plus fireball, falling and corpse) chosen every frame from the thing's state.
  - Each imp is projected into camera space with signed s.7 sin/cos at the full
    1024-step angle. Its screen x uses an 8.8 fixed-point scale and is rounded, so it
    lands within about 2 pixels of the true perspective position.
  - It's scaled vertically row by row, and horizontally with the GTIA's 1x/2x/4x widths
    plus textures pre-baked for 23 horizontal scales.
  - Each of its 8 columns is drawn only if the depth buffer says the walls at both
    edges of that column are farther away.
  - **Chasing:** Whenever you step into a new tile, a breadth-first search re-maps the
    walking distance from you, out to 32 steps. Only the tiles the last search reached
    are reset, so it stays cheap on the big maps. Each monster walks to the neighbouring
    tile one step closer (farther away it heads straight for you). Collision checks the imp's whole body, so imps can't cut corners.
- **Other sprites:** Player 0 is the gun, player 1 the hand, and the four missiles,
  combined as a fifth player, are the muzzle flash.
- **Shooting:** Hitscan uses the sprites' visible columns under the crosshair.
- **Game time:** the game runs in **ticks of 1/20 s** (3 VBIs): walking, turning,
  monsters, fireballs and the game's timers are per tick, so the pace is the same
  however long a frame takes. Each frame runs the ticks that fell due while the last
  one was drawn (1-4; more than that and the rest are dropped), so a frame shows at
  most 20 times a second. (Before, they were per frame, at about 10 frames a second:
  a tick's steps are half a frame's were, and its timers twice as long.)
- **A still view isn't redrawn:** when you haven't moved or turned (and no exit
  stripes are scrolling on screen, nothing in the maze changed), the frame on screen
  stays and only the sprites are new, up to 20 times a second.
- **Speed:** about 14 fps on average with textures on (worst views about 7.5), against
  about 10 before the OS ROM was switched off (NTSC, in emulation; the benchmark is 100
  views on two seeds, with the monsters frozen). The gains: the drawing code rewritten
  for the RAM under the OS (about +2.5 fps), only the top half drawn (+1.2), the ray
  interpolation unrolled (+1), the band-end table (+0.5), the fixed display lists
  (+0.3). ANTIC takes about half the machine's cycles in this mode: it fetches every
  row twice.
- **Sound:** Gunshots use POKEY channel 1 (loud: volume (length + 15) / 2, so they cut
  through the music), as do the tunnel's rush, the ending's footsteps and the monsters:
  a buzzing growl when one first notices you (or is shot awake), a noise swipe when it
  attacks, a falling death cry and the spitter's hiss. One monster sound plays at a
  time, the newest wins, and a gunshot takes the channel over (the monster's sound
  carries on silently and ends on time). The music is never touched. The code lives in
  the OS's unused I/O control blocks (`$0340`). Hits, pickups and the music's drums
  share channel 2; the music's bass and lead use channels 3 and 4. The music player and level clock run in the vertical-blank
  interrupt, after the time-critical frame flip.

## Memory
| Range | Use |
|---|---|
| `$0080-$00FC` | Zero page |
| `$0100-$0176` | Tunnel colours, from the VBI (from the overlay) |
| `$0178-$01C9` | Keycard drop (from the overlay) |
| `$01CA-$01DF` | The RESET stub (switches the cartridge back on and cold-starts); the stack itself stays at `$01E0` and above (`tests/checks/system.py` checks it) |
| `$0340-$03B5` | Monster sounds (from the overlay; the game never uses CIO) |
| `$03B6-$03D8` | The trigger reader (from the overlay; IOCB 7's tail and the printer buffer) |
| `$0400-$04EF` | Things, part 1: positions, state, type (24 slots; the OS's cassette buffer, unused) |
| `$04F0-$04FD` | The 8x8 multiply (from the overlay) |
| `$0500-$07FF` | Generated column writers (one per buffer, `$xx00-$xx63`: one `STA row,X` per row of the top half) |
| `$05C8`, `$06C8`, `$07C8` | Track loader and keycard carrier (from the overlay), in the spare ends of the column-writer pages |
| `$0800-$089F` | Automap display lists (two) |
| `$08A0-$08FC` | Demo bot: route choosing (from the overlay) |
| `$0900-$099F` | Per-column bookkeeping |
| `$09A0-$09FA` | Game-over banner: bitmap and helpers (from the overlay) |
| `$0A00-$0A4F` | HUD |
| `$0A50-$0AAF` | Depth buffer, sprite rows |
| `$0AB0-$0AF8` | Demo message and bot variables (from the overlay) |
| `$0B00-$0BDD` | Sprite staging and variables |
| `$0BDE-$0BE4` | Level select: last step (from the overlay) |
| `$0BE5`, `$2BE5`, `$3FEF` | "Full" pickup messages and their routine (from the overlay) |
| `$0C00-$0FFF` | Maze (32x32) |
| `$1000`, `$2000`, `$3000` | Frame buffers (2560 bytes each). While the menu is up, the overlay runs from `$1000-$1648`; the first frame of a new run goes to `$2000` so the wake-up scene's code there survives |
| `$1A00-$1AFA` | Demo bot (from the overlay; stays put while the demo draws into `$1000`) |
| `$1B00-$1BC8` | Texture columns per ray, automap, music and score variables |
| `$1BC9-$1BFD` | Level select (from the overlay) |
| `$1C00-$1FFF` | Player/missile graphics (`$1C00-$1D27` is kept zero: the wake-up scene's closed eyelids point the display at it; `$1D28-$1D50` holds the braiding's wall counter, from the overlay) |
| `$1D51-$1D7F` | Tunnel picture copier (reads cartridge bank 8) |
| `$2A00-$2BFF` | Maze generator stack (first half of each page); the braiding code sits in the second halves (from the overlay) |
| `$2C00-$2FFF` | Walking distances (BFS) |
| `$3A00-$3A4F` | Top bar (two lines) |
| `$3A50-$3BDC` | Free (was a game display list) |
| `$3BDD-$3BFD` | GOD MODE and level select messages (from the overlay) |
| `$3C00-$3FFF` | BFS queue |
| `$3F80-$3FEE` | Automap pickup dots (from the overlay; the BFS queue never reaches this far) |
| `$4000-$7FFF` | Image A: engine, interrupts, tables, wall textures (about 960 bytes free) |
| `$7D80-$7FFC` | Start-up code, then (copied by the menu) level dressing: pickups per level, entrance, keycard lines, exit check, automap marks |
| `$8000-$B7FF` | Image B: gameplay code, sprites, messages (about 140 bytes free) |
| `$B780-$B7FF` | Start-up code, then the keycard lines and level-dressing variables |
| `$B800-$B97E` | Things (part 2), weapon and maze variables |
| `$B980-$B9F0` | Tunnel start and end (from the overlay, staged through `$2000`) |
| `$BA00-$BB8C` | Free (was a game display list) |
| `$BB90-$BBFA` | Game-over banner code (from the overlay) |
| `$BC00-$BFFF` | Automap: walls seen (also key-placement scratch) |
| `$C000-$C5FF` | RAM under the OS ROM: the three game display lists (mirrored), 512 bytes each |
| `$C600-$CCFF` | `bendt`: where each texture band ends, by scale |
| `$D800-$DC2C` | `dpairs`: drawing the wall columns |
| `$E000-$E3FF` | The character set (copied from the OS ROM) |
| `$E400-$F5E4` | Ray interpolation (unrolled), game ticks, the still-view check, NMI / IRQ handlers, RESET setup, game-over helpers |
| `$F600-$FBFF` | Plain (unmirrored) display lists, for GAME OVER |
| `$FFFA-$FFFF` | The 6502's vectors: NMI, (RESET), IRQ |

During the ending the game is over, so its overlay (bank 5) runs at `$1000`, its screen
is `$2000-$2EFF` (80x96, GTIA mode 9, each row shown twice) and its display list is at
`$3000`.

## Building
Needs `ca65`/`ld65` from cc65 and Python 3.

    sh build.sh        # -> DEPTHS_OF_DOOM.CAR

`tests/setup.sh` builds a pinned cc65 and everything the tests need (see Testing).


- `game.cfg` links the game image and the overlay (`menu.s`, written to `ovl.bin`).
- **RAM under the OS ROM:** `osram.s` is linked with the game into `osr.bin`
  (`$C000-$CFFF`, `$D800-$DFFF`, `$E400-$FFFF`: 13K), which goes in banks 10-11; the
  loader copies it in. Assembling with `-D BENCH` makes every frame a full redraw (for
  speed measurements).
- **Overlay:** the main menu, demo bot and game-over banner live in cartridge bank 4.
  Opening the menu copies the bank to `$1000-$1AFF` (frame buffer 0, free then) with the
  screen and interrupts off for a moment; the menu then copies its resident parts (bot,
  banner) into spare corners of RAM listed above.
- **Ending:** `ending.s` is overlay 2 (bank 5, `ovl2.bin`), copied to `$1000` when level
  15 is cleared. `endart.py` draws its pictures (the corridor, the wasteland), the
  walking and standing figure (players 0 and 1) and the THE END lettering, packs them
  (runs, literals and copy-the-row-above) into `end.bin` (banks 6-7), and writes
  `enddata.s`. The ending reads them straight from the cartridge with interrupts held
  off for a moment.
- **Level dressing:** `items.s` (more pickups on later levels, the entrance door, the
  keycard colour and lines, the exit check and the automap marks) is linked into bank 4
  after the overlay. The start-up code sits at a fixed place (`$7D80` in image A,
  `$B780` in image B); once it has run, the menu copies `items.s` over it from the
  cartridge.
- `loader.s` / `loader.cfg` build the fixed bank.
- `mkcar.py` assembles the 16 banks into the .CAR file.

| File | What it is |
|---|---|
| `depthsofdoom.s` | the game: engine, gameplay, VBI and DLIs (images A and B) |
| `osram.s` | code and tables for the RAM under the OS ROM, the interrupt handlers |
| `menu.s` | overlay 1: menu, wake-up scene, demo bot, cheats, game-over banner, braiding |
| `items.s` | level dressing, monster sounds, the track loader and other resident extras |
| `tunnel.s` | the tunnel between levels |
| `ending.s` | overlay 2: the ending |
| `loader.s` | the fixed bank: memory check, OS ROM off, start-up |
| `gentables.py` | lookup tables, HUD text, sprites, messages (writes `data.s`) |
| `music.py` | the 16 music tracks (used by `gentables.py`) |
| `endart.py` | the ending's pictures and the tunnel picture |
| `mkcar.py`, `build.sh`, `game.cfg`, `loader.cfg` | the build |
| `tests/` | the test suite (see Testing) |
| `tools/memtest/` | MEMTEST.CAR: RAM detection and test, an 8K cartridge |

`gentables.py` generates the lookup tables, HUD text, sprites and music data. Imp stats
(`E_HP`, `E_SPEED`, `DMG`, `ATKCOOL`) are constants at the top of `depthsofdoom.s`. Maze
shape settings (loop count, room count, minimum imp distance) are in `genmaze` and
`place_enemies`.

## Testing
Everything is tested headless in an emulated 64K XL (atari800's library, with the
built-in Altirra OS), driven by Python scripts:

    tests/setup.sh       # once: builds cc65, libatari800 and the harness into tests/.tools
    tests/run_all.sh     # build the cartridge, run every check (a few minutes)
    tests/run_all.sh items monsters      # just those checks

| Check | Covers |
|---|---|
| `gameplay` | levels 1-4: contents, pickups, the three weapons, the locked exit and keycard |
| `items` | pickups refused at full stats (HEALTH/AMMO/TIME MAX), the keycard carrier and its level lines |
| `monsters` | fireballs, brute speed, animation, death and score |
| `mazes` | all 15 levels on three seeds: one exit and entrance, reachable, dead ends at most 4 tiles |
| `seeds` | same seed, same levels; game over, retry, back to the menu |
| `flow` | the wake-up scene and skipping it, the demo, the ending |
| `input_sound` | fire taps and latency, being hurt, the music stopping for the tunnel |
| `system` | the stack page, the OS ROM off, RESET, 16K / 128K / 320K machines |

`tests/tools/` has the speed tools: `bench.py` (100 fixed views, monsters frozen: the
number quoted under Speed), `compare.py` (the same 32 views from two builds, picture by
picture: an optimisation should report 0 differ), `profile.py` (cycles per routine) and
`fps.py`. `tests/lib/dod.py` is the library they share (drive the emulator, read the
game's variables by name).

## License and remixing
Depths of Doom is free software: copyright (C) 2026 CattMan97, released under the
**GNU General Public License, version 3 or later** (see `LICENSE`). You may copy it,
change it and share your changes, as long as what you share is under the same license
with its source available.

**Remixes are welcome.** Fork the repository and make it your own. Please give your
version a new name, so it isn't mistaken for the original Depths of Doom; credit and a
link back here are appreciated.

The test harness (`tests/harness/`) builds on the atari800 emulator (GPL, version 2 or
later), and the build uses cc65 (zlib license). Both are downloaded by `tests/setup.sh`
rather than included here.

