# Phase 1: Core Movement

Status: implemented and tested in Studio, awaiting approval. Baseline: tag `phase0-approved`.

## What changed

### Speed calibration

The prototype ran at about 127 km/h and could reach about 222 km/h. Movement is now tuned to the
spec's targets. On-snow gravity, drag and friction were retuned; the speedometer was already
correct (1 stud = 0.28 m, so studs/s × 1.008 = km/h). Air gravity stays at 110 so jumps don't
float.

| Target | Measured (Studio test lanes) |
|---|---|
| Cruising ~25 km/h (10° slope, untucked) | **24.7 km/h** |
| Racing 38–40 km/h (24° slope, untucked) | **40.3 km/h** |
| Tucking ~48 km/h (24° slope) | **48.6 km/h** |
| Cap ~55 km/h | `MaxSpeed = 54.5` studs/s (54.9 km/h) |

### Controls (PC)

| Input | Action |
|---|---|
| A / D (or ← / →) | Steer, with smoothed response |
| **Shift** (hold) | Tuck: eases in over 0.35 s, cuts drag, halves turning |
| **Ctrl** (hold) | Brake: steady deceleration with a slight sideways skid |
| **Space** | Tap = small hop. Hold = charge (up to 0.55 s), release to jump. |
| W | Skating push at low speed only (≤ 12 studs/s), e.g. off the start pad |
| V / R | Camera toggle / reset to start |

Gamepad: left stick steer, RT tuck, LT brake, A jump (hold to charge), Y camera, Back reset,
stick forward to push. Touch: thumbstick or ◀ ▶ buttons, plus Tuck / Brake / Jump / Cam / Reset
buttons. Shift-lock is disabled (`StarterPlayer.EnableMouseLockOption = false`) because Shift is
tuck. W/S, A/D and Q/E while airborne are reserved for Phase 4 tricks.

### Turning

Carving now costs speed instead of gaining it. Two bugs dating back to the prototype made
zig-zagging faster than riding straight:

- Sideways gravity was converted into forward speed. The edges now hold it; a little slips
  through only while braking or wiping out.
- The carve redirect added lost sideways *speed* to forward speed. It now moves kinetic energy,
  so a turn can never add speed.

Measured on the 24° lane: S-turns average 32 km/h (peak 37) against 40 km/h straight. There's
also a small per-turn drag (`TurnDrag`).

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

1. **F7** → 10° lane. Push with W, then let go. The speedometer settles at about 25.
2. **F7 F7** → 24° lane. Coast: it settles at about 40. Hold Shift: it eases up to about 48.
3. On the 24° lane at speed, hold **Ctrl**: a smooth stop in about 4 s.
4. Do S-turns with A/D: speed drops below the straight-line speed and recovers when you
   straighten.
5. Tap Space: small hop. Hold Space about half a second, then release: bigger jump, clean
   landing.
6. Jump, then hold A in the air for about ¼ s: STUMBLE. Hold it for about ½ s: WIPEOUT, then a
   recovery.
7. **F7** → 18° lane and ride into the red post: WIPEOUT, no fling.
8. **F6** at any point to log speeds and compare with the table above.
9. **F8** → ride the course: about 25–48 km/h depending on slope and tuck. Rough estimate
   70–82 s to the finish.

## Known limitations / next phases

- **No animations yet:** riders keep the default pose, and the snowboard stance isn't sideways
  (Phase 2).
- **Course not yet re-timed:** by integrating the new physics along the course profile
  (estimate, not a playtest), the current course takes about 69 s tucked and 82 s untucked. That
  is close to the 90 s beginner target; Phase 3 reshapes it and times real runs.
- **Kicker sizes were designed for the old speeds:** airtime off them is now small (Phase 3).
- **Not tested on device:** gamepad and touch bindings exist but haven't been tested on hardware.
- **Rider collisions still off:** racers pass through each other until the hybrid collision
  system (Phase 4).
- **Charged-jump height (~3 studs at full charge) is a first value:** tune
  `MovementConfig.Jump.FullPower` if jumps should clear more.
