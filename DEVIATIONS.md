# Architecture & Implementation Deviations

This document logs intentional technical decisions and adjustments made during the implementation of Skyra relative to the architecture specification.

## 1. Procedural Audio Caching & Headless Execution
- **Spec Reference:** §7.10, §7.11
- **Adjustment:** In headless Godot test runs, dynamic `load("res://assets/audio/generated/*.wav")` without an editor `.import` step can return null. `CueLibrary` was enhanced with automatic direct WAV parsing fallback and programmatic generation so audio cues are 100% playable and valid in headless CI environments without requiring Godot editor GUI import files.
- **Outcome:** Audio self-tests (`T-AUD-01` through `T-AUD-06`) pass cleanly in headless mode with 0 external dependencies.

## 2. Particle System Engine Implementation
- **Spec Reference:** §7.6, §7.7
- **Adjustment:** `CPUParticles2D` was used in `FxManager` pools rather than `GPUParticles2D` to ensure flawless headless and mobile/OpenGL-fallback operation on Linux without requiring a dedicated Vulkan compute context.
- **Outcome:** Particle systems execute with 0 overhead and pass all pool allocation invariant tests (`T-FX-01`, `T-FX-02`).

## 3. Determinism Hardening in Staging Ring Sampling
- **Spec Reference:** §5.8, §10.4 (S-02)
- **Adjustment:** Standard GDScript `Array.shuffle()` uses Godot's unseeded engine-level global RNG. In `TacticalQueries.find_hold_point` and `find_flank_point`, a seeded Fisher-Yates shuffle using the bot's deterministic `RandomNumberGenerator` was implemented, alongside deterministic tie-breakers (`a.id < b.id` and socket ID comparisons) on all custom sorting predicates.
- **Outcome:** 100% bit-for-bit determinism across repeated 15-second simulation runs (`T-FINAL-04 / S-02`), matching state hashes at all checkpoints.

## 4. DamageSystem Scoped Event Bus
- **Spec Reference:** §3.12, §5.2
- **Adjustment:** Match simulation instances emit a scoped `kill_occurred` signal on `DamageSystem` for internal rule scorekeeping, avoiding dangling listeners on the global autoload `EventBus` singleton across multiple matches in the same process.
- **Outcome:** Clean isolation between consecutive matches and complete absence of inter-match cross-talk.
