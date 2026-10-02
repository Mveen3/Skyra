# Skyra

**Skyra** is a fast 2D side-view jetpack arena shooter for Linux, inspired by *Mini Militia*:
you are **Skyra**, alone against 3, 5 or 7 bots (Alpha, Beta, Gamma, Delta, Theta, Phi, Chi)
on one hand-made map, **Outpost Skyra**. Built with Godot 4.4 and GDScript, it needs no
external assets: the characters, weapons and map are procedural vector art and every sound
is synthesized.

---

## 1. System Requirements & Dependencies (Ubuntu / Debian)

Before cloning and running or building the game from source on Ubuntu, install the required build and system tools:

```bash
sudo apt update
sudo apt install -y git curl unzip make build-essential libgl1 libvulkan1 libasound2
```

- **`git`**: To clone the repository.
- **`curl` & `unzip`**: Used by automated setup scripts to fetch the Godot 4.4 engine runner and Linux export templates.
- **`make`**: To run the project Makefile targets (`make run`, `make build`, `make dist`).
- **`libgl1`, `libvulkan1`, `libasound2`**: Standard desktop OpenGL / Vulkan and ALSA audio libraries (preinstalled on standard Ubuntu desktops).

---

## 2. Quick Start: Clone & Play

You can clone the repository and launch the game in just 3 commands:

```bash
# 1. Clone the repository
git clone https://github.com/mveen3/Skyra.git
cd Skyra

# 2. Run the game (fullscreen)
make run
```

> **Note**: On the very first run, `make run` automatically downloads and configures the Godot 4.4.1 binary to `tools/bin/godot` (inside `.gitignore`).

### Other Run Options

```bash
make run-windowed     # Play in a 1600 x 900 window
```

Or without using `make`:

```bash
# Setup Godot engine runner
./tools/setup_godot.sh

# Run directly
./tools/bin/godot --path .                      # Play fullscreen
./tools/bin/godot --path . -- --windowed        # Play in 1600x900 window
./tools/bin/godot --path . -- --autostart       # Skip menu (--mode=sniper_post --bots=7 --duration=5 --seed=42)
```

On the preset menu just press **Enter**: Mini Post · 5 bots · 7 minutes is pre-selected.
Change the bots with `3` / `5` / `7`, the mode with `M`, the duration with `+` / `−` (or the
mouse), and open the gear icon for controls, audio and display settings.

---

## 3. Creating a Standalone Game for Friends (Zero Dependencies)

You can build a single, standalone binary file that contains the entire game (engine runtime, procedural vector art, maps, sounds, and match simulation) embedded inside.

When you send this file to a friend on Ubuntu / Linux, **they do not need to install Godot, clone the repo, or install any dependencies**.

### Build the Standalone Binary

Run:

```bash
make build
```

This automatically:
1. Downloads the Godot Linux export template (`linux_release.x86_64`, ~25 MB) if not already present.
2. Compiles and embeds the game package (PCK) directly into a single binary.
3. Produces the self-contained executable at:
   ```
   build/linux/Skyra.x86_64
   ```

### Package for Easy Sharing (Recommended)

To share the game over Discord, Google Drive, USB, or email without chat clients stripping file execute permissions:

```bash
make dist
```

This creates compressed distribution packages in `build/dist/`:
- `build/dist/Skyra-linux-x86_64.tar.gz`
- `build/dist/Skyra-linux-x86_64.zip`

Both archives contain the standalone `Skyra.x86_64` executable, the game icon, and a `HOW_TO_PLAY.txt` guide.

### Instructions for Your Friend (How They Run It on Ubuntu)

Send your friend the `Skyra.x86_64` binary (or the `.zip` / `.tar.gz` archive). All they have to do is:

1. If you sent the archive, extract it.
2. Open a terminal in the folder containing `Skyra.x86_64`.
3. Mark it executable and run:
   ```bash
   chmod +x Skyra.x86_64
   ./Skyra.x86_64
   ```

That's it! The game will launch immediately.

---

## 4. Makefile Command Reference

| Command | Description |
|---|---|
| `make run` | Automatically prepares engine (if needed) and runs game in fullscreen |
| `make run-windowed` | Runs the game in a 1600 x 900 window |
| `make build` | Builds the standalone Linux binary (`build/linux/Skyra.x86_64`) |
| `make dist` | Packages the standalone binary into `.tar.gz` and `.zip` archives |
| `make run-bin` | Executes the built standalone binary directly |
| `make setup` | Downloads engine binary and Linux export templates |
| `make test` | Runs the headless test suite (117 unit and integration tests) |
| `make appimage` | Builds a standalone AppImage (requires `appimagetool`) |
| `make clean` | Removes the `build/` directory |
| `make distclean` | Removes `build/`, downloaded engine binary `tools/bin/`, and local caches |

---

## 5. Controls (Defaults, Remappable in Settings → Controls)

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

---

## 6. Game Modes

- **Mini Post** — spawn with the Magnum (infinite reserve) + 2 Frags. Hornet (MP5), Kalash
  (AK-47), Pump, Black Arrow (M93BA), Blaze (flamethrower), Phaser, Bazooka and Buzzsaw
  appear on 16 weapon sockets, plus Frag Packs.
- **Sniper Post** — spawn with the Black Arrow + 3 Frags; only Black Arrows and Frag Packs spawn.

Both modes: unlimited respawns (2 s for Skyra, then 2 s of cloak — bots cannot see or hurt
you), score = bots killed, carry at most two guns, the camera zooms out per weapon (1x
Magnum … 5x Black Arrow), and a **Rocket Boost** (infinite jetpack, more speed for 10 s)
drops 45 s into the match and again 35–50 s after each one is taken or expires, at the
Beacon Crown or the Reactor Heart — never two at once. A Pacing Director lets at most two bots attack you at the same time.

---

## 7. Map Features

- **Launch pads** on both wings of the Spire fling you up past the catwalk to the
  floating islands (hold jet to go even higher).
- **Med stations** in both hangars and both lower tunnels heal +45 HP and recharge in
  25 s — bots use them too when badly hurt.
- **Two looks**: Mini Post plays at golden sunset, Sniper Post under a moonlit night sky.

---

## 8. Tests and Development Tools

```bash
make test                                                           # run full test suite via Makefile
./tools/bin/godot --headless --path . -- --selftest                 # 117 tests, ~20 s, writes docs/TEST_REPORT.md
./tools/bin/godot --headless --path . -- --selftest --only=test_ai  # run one test file
./tools/bin/godot --headless --path . -- --soak=180 --seed=1234 --bots=7 --mode=mini_post
./tools/bin/godot --headless --path . -- --soak=120 --seed=99 --bots=5 --mode=sniper_post
./tools/bin/godot --headless --path . -- --gen-sfx                  # re-synthesize assets/audio/generated/*.wav
./tools/bin/godot --path . -- --bench                               # 30 s rendering benchmark (7 bots, VSync off)
```

`--bench` sweeps the camera over the whole map at 5x, then follows a bot fight around an
invulnerable autopiloted Skyra, and writes the average / p99 frame time and FPS to
`~/.local/share/skyra/bench.json` (exit code 0 when avg ≤ 16.6 ms and p99 ≤ 25 ms).

Additional helper scripts in `tools/`:
- `tools/fetch_fonts.sh` — optional: downloads Russo One and Rajdhani fonts (OFL).
- `tools/install_local.sh` — optional: installs desktop menu entry and icon for the current user.
- `tools/make_appimage.sh` — optional: packages `Skyra.x86_64` as an AppImage when `appimagetool` is installed.

---

## 9. Architecture

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
