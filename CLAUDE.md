# Depths of Doom: notes for Claude

A first-person maze shooter for the Atari 8-bit: a 128K XEGS cartridge (.CAR type 35)
for 64K XL/XE machines, written in 6502 assembly (ca65). The README is the design
document: what the game does, how it works, the memory map, and where free space is.
Read the relevant README section before changing a system, and **keep the README in
step with the code** (behaviour, memory map, "Room to grow", speed figures).

## The player and the hardware
- Zach plays on a real **600XL with a 320K upgrade** (5cfab, parallel bus; RAM under
  the OS ROM and 16 extended banks, verified with `tools/memtest`), an **A8PicoCart**,
  and an **NTSC** TV. Changes are judged on that machine, so give him the built
  `DEPTHS_OF_DOOM.CAR` when a change is ready.
- His TV crops the edges (overscan): keep important text away from the screen's top
  and bottom lines.

## Build and test
    tests/setup.sh          # once per machine: pinned cc65 + libatari800 + harness, in tests/.tools
    tests/run_all.sh        # build + every check; must end "ALL CHECKS PASSED"
    tests/run_all.sh items  # one check (tests/checks/items.py)

- Run the whole suite before every commit. If a check fails, decide whether the game
  or the check is wrong before changing either. Several "failures" so far were checks
  sampling too early: a faster frame rate moves when things happen.
- New behaviour gets a check in `tests/checks/` (use `tests/lib/dod.py`: `Game`,
  `SYM['name']` for any variable, `check()` / `done()`).
- Speed work: `tests/tools/bench.py` before and after (the README's Speed figures come
  from it), and `tests/tools/compare.py OLD.car NEW.car` must report `0 differ`, unless
  the picture is meant to change. `tests/tools/profile.py` shows where the cycles go.
- Harness input: stick is a **bit mask of directions pressed** (1 up, 2 down, 4 left,
  8 right; 0 = centred) and trig **1 = pressed**. This is not the hardware's
  active-low convention.
- A still view is not redrawn: after teleporting the player (`g.place`), run ~20
  frames before judging the picture. RAM snapshots can land mid-update: poll a few
  frames rather than reading one.
- The built files (`*.CAR`, `*.bin`, `data.s`, `enddata.s`) are not in git; `build.sh`
  makes them. Release builds go on GitHub as release attachments.

## Rules learned the hard way
- **The OS ROM is switched off** for the whole game (`osram.s`). No OS calls (CIO,
  SIO, SETVBV...). `XITVBV`, the NMI/IRQ handlers, the keyboard (`CH`) and the OS
  shadow registers (colours, `SDLSTL`, `SDMCTL`, `STICK0`, `STRIG0`, `RTCLOK`) are all
  serviced by the game's own code. The character set is copied to `$E000`.
- **Cartridge access only with `NMIEN` = 0**: the interrupts live in RAM that the
  cartridge window covers. With the cartridge on, `$8000-$BFFF` is cartridge (XEGS maps
  its fixed bank at `$A000`), so anything destined for `$A000+` is staged through
  `$2000` and copied with the cartridge off.
- **The stack page holds code**: `$0100-$0176` tunnel VBI, `$0178-$01C9` keycard drop,
  `$01CA-$01DF` the RESET stub. The stack must stay at `$01E0` and above
  (`tests/checks/system.py` guards this). Don't add deep call chains or big pushes.
- **RESET** on an XL resets the chips (the OS ROM comes back); the game survives it
  through `DOSINI` and the stub, which switches the cartridge back on and cold-starts.
- **Memory is nearly full** in images A and B. Before adding code, check "Room to grow"
  in the README; the RAM under the OS (`$CD00-$CFFF`, `$DC30-$DFFF`, `$FC00-$FFF9`) is
  the main free space for engine code. Overlay code (bank 4) is copied into spare
  corners of RAM by the menu (`xcptab`/`cptab` in `menu.s`). Record every new placement
  in the README memory table and `game.cfg`.
- **Game logic runs in fixed ticks** (at most 20 a second), separate from the frame
  rate, so speed-ups don't change how the game plays.
- **Sound channels**: 1 gun (it has priority), tunnel rush, ending footsteps, monster
  sounds; 2 thumps, pickups and drums; 3-4 music. Keep the music on 3-4.
- **Music** (`music.py`, 16 tracks, a page each in bank 9): the distortion-C bass is in
  tune only when AUDF+1 is coprime to 15.
- ca65: a global label ends the scope of `@local` labels, and branches reach only
  ±127 bytes (use `jmp` past them).

## Git
- Commit as `CattMan97 <344101925+CattMan97@users.noreply.github.com>` (Zach's private
  GitHub address: never his personal email).
- `main` on GitHub (CattMan97/Depths-of-Doom). Commit working, tested states with
  messages that say what changed for the player and why.
- Tags mark versions given to Zach (`v1.0-osram` = the OS-RAM speed rework).
