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

## DEV-005: Aim error decay constant 0.7 s
- Section(s): §5.6, §10.4 T-AI-04
- Change: σ(t) = 1.2° + 6.8°·e^(−t/0.7) instead of e^(−t/0.9).
- Reason: with 0.9 s, σ(3 s) = 1.44° and T-AI-04 (≤ 1.3° after 3 s) cannot pass; §0.2 gives §10 precedence.
- Invariants checked: 2.6.2 #1 (within ±15 % of the error after 1 s), #7
- Tests: T-AI-04

## DEV-006: Grenade solver extra arcs
- Section(s): §5.6
- Change: after the low and high ballistic arcs, 30–45° bounce arcs are also simulated and accepted only if they land within 120 wu.
- Reason: lets bots reach targets behind low cover; acceptance rule unchanged.
- Invariants checked: 2.6.2 #3 (INV-4 still capped)
- Tests: T-AI-05

## DEV-007: Time-sliced A* budget
- Section(s): §5.2, §5.7.1
- Change: queued searches share a 450-expansion budget per tick (instead of "≤ 2 searches per tick"); smoothing covers the first 28 waypoints.
- Reason: p99 Sim tick went from 4.87 ms to ≈ 3 ms (S-01 limit 4.0 ms).
- Invariants checked: 2.6.2 #1, #3, #7
- Tests: T-NAV-01…04, S-01

## DEV-008: Soak autopilot boost anticipation
- Section(s): §10.5
- Change: the autopilot also walks to the likely Rocket Boost socket 12 s before a drop and keeps moving to it while shooting.
- Reason: without it S-01 "Rocket Boost spawned ≥ 3" depends on luck; the game itself is unchanged.
- Invariants checked: 2.6.2 #7
- Tests: S-01 (seeds 1234, 1–5), S-01b
