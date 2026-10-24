# Phase 1: Core Movement

Status: implemented and tested in Studio, awaiting approval. Baseline: tag `phase0-approved`.

## What changed

### Speed calibration (restored to the prototype speeds)

Speeds went through three retunes (25→55, 38→70, 46→85 km/h) and are now **back to the original
prototype's speeds** at your request (2026-10-24). On-snow and air gravity are 110, drag 0.0024,
tuck drag ×0.6, friction 0.04, cap 220 studs/s. Turning, braking (70 studs/s², plain force),
push and landing/impact thresholds are also back to the prototype's values. Everything else
built since then stays: energy-conserving carving, charged jumps, stumble/wipeout, stance.

| Slope | Untucked | Tucked |
|---|---|---|
| 10°–14° | ~80 km/h (calculated) | ~100 |
| 24° | **122 km/h measured** (prototype: ~127) | **148 and still climbing** when the lane ended (calculated ~160) |
| Cap | — | 220 studs/s |

The Studio test lanes are now 1,600 studs long so these speeds can be measured. Estimated
course time is about 25–30 s. This is far from the 90 s target in the spec, and the spec's own
guidance called this speed "excessively fast". Expect to revisit it in Phase 3.

**About the 20 km/h you saw:** that was the real riding speed, not braking. No brake input was
held. You were on the course's mellow 10° section (z ≈ 630–850), where the old tuning topped out
at about 25 km/h untucked, and steering drag took it to about 20.

**Frame rate:** Studio was running at **16 FPS** during your test, on battery with Future lighting
and about 1,000 tree meshes. Low FPS makes any speed feel choppy and slower. Test plugged in, at
a manual graphics setting. A frame-rate budget for the course is part of Phase 3 and later
optimisation.

### Controls (PC)

| Input | Action |
|---|---|
| A / D (or ← / →) | Steer, with smoothed response |
| **Shift** (hold) | Tuck: eases in over 0.35 s, cuts drag, halves turning |
| **Ctrl** (hold) | Brake: stops in about 2 s from racing speed on any slope, with a slight sideways skid |
| **Space** | Tap = small hop. Hold = charge (up to 0.55 s), release to jump. |
| W | Skating push at low speed only (≤ 12 studs/s), e.g. off the start pad |
| V / R | Camera toggle / reset to start |

Gamepad: left stick steer, RT tuck, LT brake, A jump (hold to charge), Y camera, Back reset,
stick forward to push. Touch: thumbstick or ◀ ▶ buttons, plus Tuck / Brake / Jump / Cam / Reset
buttons. Shift-lock is disabled (`StarterPlayer.EnableMouseLockOption = false`) because Shift is
tuck. W/S, A/D and Q/E while airborne are reserved for Phase 4 tricks.

### Turning

Carving costs speed instead of gaining it. Two bugs dating back to the prototype made
zig-zagging faster than riding straight:

- Sideways gravity was converted into forward speed. The edges now hold it; a little slips
  through only while braking or wiping out.
- The carve redirect added lost sideways *speed* to forward speed. It now moves kinetic energy,
  so a turn can never add speed.

For the faster tuning, high-speed turning is a little more responsive (`TurnRateHighSpeed` 1.15
→ 1.3 rad/s, reached at 65 instead of 50 studs/s), and turns cost a bit less speed (`TurnDrag`
0.3 → 0.22).

### Braking

Braking used to be a fixed deceleration, so with the higher slope gravity it nearly stalled on
steep slopes and felt grabby on mellow ones. It's now a fixed force (16 studs/s²) **plus a hold
that cancels the slope's downhill pull** (`Brake.SlopeHold = 1`). Ctrl therefore stops you in
about the same 1.5–2 s anywhere.

### Input robustness

If the Studio or Roblox window lost focus while a key was held (Cmd+Shift+4, alt-tab), the
release never arrived, so Shift stayed "held" and the tuck stayed on. Held actions now re-check
the live key state every frame and clear when the window loses focus.

### Landings, bumps and wipeouts (no ragdolls)

| Situation | Result |
|---|---|
| Normal or full-charge jump | Clean |
| Big drop (impact > 36 studs/s) | Hard: small speed loss |
| Very big drop (> 48) or landing 25–70° off-line | **Stumble**: 20% speed loss, weak steering and no tuck/jump for 0.7 s, wobble |
| Huge drop (> 75), landing > 70° off-line, or hitting an obstacle hard | **Wipeout**: slide to a stop over 1.6 s, leaning on one side, then a 0.5 s recovery stumble |
| Light bump into something | Stumble |

The body stays upright throughout. The constraints keep driving the character, so there's no
physics tumble or fling. In the post-collision test, sideways displacement was 0 studs.

### Riding stance (added at your request, ahead of Phase 2)

The rider no longer stands upright. `client/Animation/RiderPose.luau` bends the R15 joints every
frame, and `client/Controllers/PoseController.luau` drives it for every rider:

- **Skis:** knees bent, torso leaning forward, arms forward like holding poles, head up. The tuck
  goes deep (52° hip flex, 42° torso lean, arms tucked). Brake, air, jump-charge and landing
  compression change the crouch, and stumbles wobble the arms.
- **Snowboard:** body turned sideways on the board (regular stance: left foot forward), head
  looking down the slope, feet over the bindings, arms out for balance.
- **Feet stay planted:** the hips drop exactly as much as the bent legs lose. Measured: foot
  bottoms 0.06 studs above the ski and board tops.
- **Works with both R15 joint types** (Motor6D and the newer AnimationConstraint; Roblox can give
  the same avatar either). The default idle animation is paused while riding, because it would
  otherwise override the torso and arms.
- **Multiplayer:** each rider sends a tiny state update (tuck, brake, air, charge, stumble; only
  on change, at most 10/s). The server validates it and republishes it as character attributes,
  so every client poses every rider.
- **Tuning** is in `shared/Config/PoseConfig.luau`. Skis are now spaced to match hip width.
- **Not included yet** (Phase 2): equipment models, poles, regular/goofy choice in the UI, and
  authored animation clips.

### Code structure

`client/Controllers/MovementController.luau` coordinates; the work is split into:

| Module | Responsibility |
|---|---|
| `client/Movement/Rig.luau` | Constraints and Humanoid state |
| `client/Movement/GroundProbe.luau` | Ground normal and distance (5 rays) |
| `client/Movement/Physics.luau` | Grounded and airborne integration, jump velocity |
| `client/Movement/Landing.luau` | Touchdown judgement |

The public interface the camera and HUD use is unchanged, plus new `Stumbled` and `Jumped`
signals and `state.Tuck` / `state.JumpCharge` / `state.SlopeAngle`. All tuning lives in
`shared/Config/MovementConfig.luau`; bindings live in `shared/Config/InputConfig.luau`.

The camera's speed-based FOV and distance were rescaled to the new speed range, and are more
subtle now (max FOV 84°). The HUD shows STUMBLE / WIPEOUT / CHARGING JUMP, plus a thin amber
charge bar under the speed bar.

### Studio-only dev tools

These are never built or bound on live servers.

| Key | Tool |
|---|---|
| F6 | Start or stop a speed log. A summary and a per-second table print to Output. |
| F7 | Teleport to the next test lane: 10° / 18° (with an obstacle post) / 24° |
| F8 | Back to the course start |

Code: `server/Dev/TestSlopes.luau`, `server/Dev/DevService.luau`, `client/Dev/DevTools.luau`,
`shared/Config/DevConfig.luau`. The `DevTeleport` remote is ignored outside Studio.

## How to test

Run `rojo serve` and connect the plugin, press Play, pick a sport.

1. **F7** → 10° lane. Push with W, then let go. The speedometer climbs toward about 80.
2. **F7 F7** → 24° lane. Coast: about 125. Hold Shift: up toward about 160.
3. At speed, hold **Ctrl**: a strong stop (70 studs/s², as in the prototype).
4. Do S-turns with A/D: speed drops below the straight-line speed and recovers when you
   straighten.
5. Tap Space: small hop. Hold Space about half a second, then release: bigger jump, clean
   landing.
6. Jump, then hold A in the air for about ¼ s: STUMBLE. Hold it for about ½ s: WIPEOUT, then a
   recovery.
7. **F7** → 18° lane and ride into the red post: WIPEOUT, no fling.
8. **F6** at any point to log speeds and compare with the table above.
9. **F8** → ride the course at prototype speed. Rough estimate 25–30 s to the finish.

## Known limitations / next phases

- **No animations yet:** riders keep the default pose, and the snowboard stance isn't sideways
  (Phase 2).
- **Course is now shorter than the 90 s target:** at the faster tuning the current course takes
  about 55 s tucked and 65 s untucked (estimate from integrating the physics along the course
  profile, not a timed run). Phase 3 lengthens and reshapes it and times real runs.
- **Kickers are first-pass:** at the new speeds they give modest air; Phase 3 redesigns them.
- **Not tested on device:** gamepad and touch bindings exist but haven't been tested on hardware.
- **Rider collisions still off:** racers pass through each other until the hybrid collision
  system (Phase 4).
- **Charged-jump height (~3 studs at full charge) is a first value:** tune
  `MovementConfig.Jump.FullPower` if jumps should clear more.
