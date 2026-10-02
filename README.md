# Skyra

**Skyra** is a fast 2D side-view jetpack arena shooter for Linux, inspired by *Mini Militia*:
you are **Skyra**, alone against 3, 5 or 7 bots (Alpha, Beta, Gamma, Delta, Theta, Phi, Chi)
on one hand-made map, **Outpost Skyra**. Built with Godot 4.4 and GDScript, it needs no
external assets: the characters, weapons and map are procedural vector art and every sound
is synthesized.

---

## Quick start

The repository includes the engine at `tools/bin/godot` (if it is missing, run
`tools/setup_godot.sh` to download Godot 4.4.1).

```bash
./tools/bin/godot --path .                      # play (preset menu, fullscreen per settings)
./tools/bin/godot --path . -- --windowed        # play in a 1600 x 900 window
./tools/bin/godot --path . -- --autostart       # skip the menu (also: --mode=sniper_post --bots=7 --duration=5 --seed=42)
```

On the preset menu just press **Enter**: Mini Post · 5 bots · 7 minutes is pre-selected.
Change the bots with `3` / `5` / `7`, the mode with `M`, the duration with `+` / `−` (or the
mouse), and open the gear icon for controls, audio and display settings.

## Controls (defaults, remappable in Settings → Controls)

| Action | Primary | Secondary |
|---|---|---|
| Move left / right | `A` / `D` | `←` / `→` |
| Jump (tap) / Jetpack (hold) | `W` | `Space` |
| Crouch · drop through catwalks · dive in wind shafts | `S` | `↓` |
| Aim | mouse | – |
| Fire | left mouse button | – |
| Frag grenade (hold = aim arc, release = throw) | right mouse button | `G` |
| Reload | `R` | – |
| Switch weapon / select slot | `Q`, mouse wheel / `1`, `2` | – |
| Pick up or swap a weapon | `E` | – |
| Drop weapon | `X` | – |
| Scoreboard (hold) | `Tab` | – |
| Pause | `Esc` | `P` |
| Restart match (confirm with F5 / Enter) | `F5` | – |
| Fullscreen | `F11` | – |
| Debug overlay (while open in a debug build: F6 god mode, F7 next weapon, F8 boost now, F9 kill bots) | `F3` | – |

Key bindings, volumes and display options are saved automatically to
`~/.config/skyra/settings.json` (`$XDG_CONFIG_HOME/skyra/` when set; override the folder
with `SKYRA_CONFIG_DIR`). Writes are atomic and a corrupt file is backed up and reset.

## Game modes

- **Mini Post** — spawn with the Magnum (infinite reserve) + 2 Frags. Hornet (MP5), Kalash
  (AK-47), Pump, Black Arrow (M93BA), Blaze (flamethrower), Phaser, Bazooka and Buzzsaw
  appear on 16 weapon sockets, plus Frag Packs.
- **Sniper Post** — spawn with the Black Arrow + 3 Frags; only Black Arrows and Frag Packs spawn.

Both modes: unlimited respawns (2 s for Skyra, then 2 s of cloak — bots cannot see or hurt
you), score = bots killed, carry at most two guns, the camera zooms out per weapon (1x
Magnum … 5x Black Arrow), and a **Rocket Boost** (infinite jetpack, more speed for 10 s)
drops 45 s into the match and again 35–50 s after each one is taken or expires, at the
Beacon Crown or the Reactor Heart — never two at once. A Pacing Director lets at most two bots attack you at the same time.

## Map features

- **Launch pads** on both wings of the Spire fling you up past the catwalk to the
  floating islands (hold jet to go even higher).
- **Med stations** in both hangars and both lower tunnels heal +45 HP and recharge in
  25 s — bots use them too when badly hurt.
- **Two looks**: Mini Post plays at golden sunset, Sniper Post under a moonlit night sky.

## Tests and tools

```bash
./tools/bin/godot --headless --path . -- --selftest                 # 117 tests, ~20 s, writes docs/TEST_REPORT.md
./tools/bin/godot --headless --path . -- --selftest --only=test_ai  # one test file
./tools/bin/godot --headless --path . -- --soak=180 --seed=1234 --bots=7 --mode=mini_post
./tools/bin/godot --headless --path . -- --soak=120 --seed=99 --bots=5 --mode=sniper_post
./tools/bin/godot --headless --path . -- --gen-sfx                  # re-synthesize assets/audio/generated/*.wav
./tools/bin/godot --path . -- --bench                               # 30 s rendering benchmark (7 bots, VSync off)
```

`--bench` sweeps the camera over the whole map at 5x, then follows a bot fight around an
invulnerable autopiloted Skyra, and writes the average / p99 frame time and FPS to
`~/.local/share/skyra/bench.json` (exit code 0 when avg ≤ 16.6 ms and p99 ≤ 25 ms).

Building a standalone Linux binary needs the Godot export templates (≈1 GB download):

```bash
tools/install_export_templates.sh   # one-time download
tools/build_linux.sh                # -> build/linux/Skyra.x86_64 (single file)
tools/install_local.sh              # optional: install + menu entry for the current user
tools/make_appimage.sh              # optional: AppImage when appimagetool is installed
tools/fetch_fonts.sh                # optional: Russo One / Rajdhani fonts (OFL)
```

## Architecture

- **Simulation** (`src/sim`, `src/physics`, `src/weapons`, `src/pickups`, `src/ai`): a
  deterministic fixed 60 Hz `MatchSim` with custom AABB tile physics (step-up 34 wu, coyote
  time 0.08 s, jump buffer 0.10 s), DDA grid raycasts, pooled projectiles, explosions with
  exposure, and the bot AI (FSM, Pacing Director tokens, perception, aim model, time-sliced
  A* on a nav grid, tactical queries).
- **Views** (`src/view`): interpolated rendering — chunked map renderer, parallax sky,
  landmarks, paper-doll character rig, SVG-rasterized weapon art, particles and screen FX.
- **UI** (`src/ui`): code-built preset menu, HUD, pause / settings / summary screens.
- **Audio** (`src/audio`): 5 buses (Master + limiter, SFX, SFX_Interior + reverb,
  Ambient + low-pass, UI), voice pools, and an event router mapping game events to cues.

The full specification is `docs/Skyra_Technical_Architecture.md`; intentional deviations
are logged in `docs/DEVIATIONS.md`.
