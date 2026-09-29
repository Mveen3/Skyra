# Skyra

**Skyra** is a fast-paced 2D side-view jetpack arena shooter built with Godot 4.4+ and GDScript, inspired by the spirit of *Mini Militia*. It runs fully autonomously with zero external assets, featuring deterministic 60 Hz AABB physics, Amanatides-Woo DDA grid raycasting, a built-in procedural audio synthesizer, and dynamic vector graphics.

---

## Quick Start

### Running the Game

Launch with default settings (Preset Menu):
```bash
./tools/bin/godot --path .
```

Or run windowed:
```bash
./tools/bin/godot --path . -- --windowed
```

Or instantly start a match skipping the menu:
```bash
./tools/bin/godot --path . -- --autostart
```

### Running the Self-Test Suite

Run the full self-test suite (114 unit, soak, and determinism tests in ≤ 17 s):
```bash
./tools/bin/godot --headless --path . -- --selftest
```

### Running Soak Tests

Mini Post 180s Soak:
```bash
./tools/bin/godot --headless --path . -- --soak=180 --seed=1234 --bots=7 --mode=mini_post
```

Sniper Post 120s Soak:
```bash
./tools/bin/godot --headless --path . -- --soak=120 --seed=99 --bots=5 --mode=sniper_post
```

### Generating Audio Assets

Re-synthesize all 87 procedural sound cues to `assets/audio/generated/*.wav`:
```bash
./tools/bin/godot --headless --path . -- --gen-sfx
```

---

## Default Controls

| Action | Primary Key | Secondary Key |
|---|---|---|
| **Move Left** | `A` | `Left Arrow` |
| **Move Right** | `D` | `Right Arrow` |
| **Jump / Jetpack** | `W` | `Space` |
| **Crouch / Dive / Drop** | `S` | `Down Arrow` |
| **Aim** | Mouse Pointer | – |
| **Fire Weapon** | Left Mouse Button | – |
| **Throw Grenade** | Right Mouse Button | `G` |
| **Pick Up Weapon** | `E` | – |
| **Switch Weapon** | `Q` | Mouse Wheel Up/Down |
| **Drop Weapon** | `X` | – |
| **Pause Match** | `Escape` | `P` |
| **Quick Restart** | `F5` | – |

Keybindings can be customized in the in-game Settings menu or by modifying `~/.config/skyra/settings.json`.

---

## Configuration & Settings

Settings are stored at:
- **Linux:** `~/.config/skyra/settings.json` (or `$XDG_CONFIG_HOME/skyra/settings.json`)
- Can be overridden via the environment variable: `SKYRA_CONFIG_DIR=/path/to/dir`

Settings are written atomically (`.tmp` + rename) with automatic corruption recovery.

---

## Game Modes

1. **Mini Post**
   - Spawn weapon: Magnum + 2 Frag Grenades
   - 9 weapons distributed across map weapon sockets (W01–W16)
   - Dynamic zoom (1x to 5x depending on equipped weapon)
   - Rocket Boost power-up spawns every 45 s at Beacon Crown (B01) or Reactor Heart (B02)
   - Pacing Director limits active attacking bots to at most 2 simultaneously

2. **Sniper Post**
   - Spawn weapon: Black Arrow (M93BA) + 3 Frag Grenades
   - Only Black Arrow rifles and Frag Packs spawn in sockets
   - 5x fixed zoom with dynamic laser sight
   - One-shot headshots

---

## Architecture Overview

- **Fixed-Tick Simulation:** 60 Hz fixed timestep (`MatchSim`) decoupled from rendering.
- **Physics Engine:** Custom AABB grid collisions with step-up (12 px), coyote time (5 ticks), jump buffering (6 ticks), and zero Godot physics nodes used for simulation.
- **Raycasting:** Amanatides-Woo Digital Differential Analyzer (DDA) grid traversal with sub-tile boundary hit normals.
- **Pacing Director:** Orchestrates 5 pacing phases (`WARMUP`, `BUILD_UP`, `PEAK`, `RELAX`, `RESPAWN_GRACE`) with dynamic tokens to prevent bot swarming.
- **Sound Engine:** 22,050 Hz 16-bit mono procedural audio synthesizer with 5 mixer buses (`Master` with Limiter, `SFX`, `SFX_Interior` with Reverb, `Ambient` with LowPass, `UI`).
- **Visual FX:** 24 presets with pre-allocated `CPUParticles2D` emitter pools.
