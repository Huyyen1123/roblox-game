# Phase 1: Core Movement

Status: implemented and tested in Studio, awaiting approval. Baseline: tag `phase0-approved`.

## What changed

### Speed calibration (retuned after your first playtest)

The first Phase 1 tuning (25 / 40 / 48 / 55 km/h) felt too slow. It's now retuned to the faster
targets you gave, calibrated against the course's real slopes (9°–24°). On-snow gravity went
from 60 to 68, drag from 0.0142 to 0.0097, and the cap to 70 km/h. The speedometer conversion
was already correct (1 stud = 0.28 m, so studs/s × 1.008 = km/h).

| Target | Measured (Studio test lanes) | Notes |
|---|---|---|
| Cruising 35–40 km/h | 32.0 km/h on 10° (the mellowest course slope) | 37–39 km/h on the course's typical 13–14° (calculated) |
| Racing 45–55 km/h | **51.8 km/h** on 24°, untucked | about 45 on 18° (calculated) |
| Tucking 60–65 km/h | **62.1 km/h** on 24° | builds over about 4 s, no jump in speed |
| Max ~70 km/h | `MaxSpeed = 69.4` studs/s | reachable off jumps and steep drops |
| Braking | 44 → 0 in **1.9 s** on 24°; 36 → 0 in **1.6 s** on 10° | consistent on every slope (see below) |

Acceleration: 12 to 48 km/h in about 3 s on 24°.

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

1. **F7** → 10° lane. Push with W, then let go. The speedometer settles at about 32.
2. **F7 F7** → 24° lane. Coast: it settles at about 52. Hold Shift: it eases up to about 62.
3. On any lane at speed, hold **Ctrl**: a smooth stop in about 2 s.
4. Do S-turns with A/D: speed drops below the straight-line speed and recovers when you
   straighten.
5. Tap Space: small hop. Hold Space about half a second, then release: bigger jump, clean
   landing.
6. Jump, then hold A in the air for about ¼ s: STUMBLE. Hold it for about ½ s: WIPEOUT, then a
   recovery.
7. **F7** → 18° lane and ride into the red post: WIPEOUT, no fling.
8. **F6** at any point to log speeds and compare with the table above.
9. **F8** → ride the course: about 32–62 km/h depending on slope and tuck. Rough estimate
   55–65 s to the finish.

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
