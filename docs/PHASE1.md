# Phase 1: Core Movement and Camera Prototype

Project Downhill Phase 1 delivers a playable prototype: a generated Frostpeak test course, a
ski/snowboard picker, a custom downhill controller with jumps and crashes, third- and first-person
cameras, a speedometer HUD, and server-validated resets.

## Architecture

All code lives in this repo and is synced into Studio by Rojo (`rojo serve` + the Studio plugin).
The course is generated from config at server start, so the place file is disposable.

| Layer | Where | Role |
|---|---|---|
| Shared config and utilities | `ReplicatedStorage.Shared` | Balance values, course definitions, names shared by client and server |
| Remotes | `ReplicatedStorage.Remotes` | Declared in `default.project.json` |
| Server | `ServerScriptService.Server` | Course generation, spawning, sport validation, resets |
| Client | `StarterPlayerScripts.Client` | Input, movement physics, cameras, UI |

**Trust model.** The client simulates its own character, because it has network ownership, which
gives responsive movement. The server decides the sport, the spawn and reset positions, and the
reset rate limit. Phase 1 has no rewards, so nothing a client sends can grant anything. Phase 4
adds server-side checkpoint and speed validation on top of this.

### Remotes

| Remote | Direction | Payload | Server validation |
|---|---|---|---|
| `SelectSport` | client → server | sport id | Must be a known id; not allowed while `InRace`; 0.5 s cooldown |
| `RequestReset` | client → server | none | 1 s cooldown; the server picks the position |
| `ResetState` | server → client | spawn CFrame | Tells the controller to zero its state after a teleport |

## Explorer structure

```
ReplicatedStorage
├── Remotes (Folder): SelectSport, RequestReset, ResetState (RemoteEvent)
└── Shared (Folder)
    ├── Constants
    ├── Config
    │   ├── MovementConfig, CameraConfig, InputConfig, SportConfig
    │   └── Courses (registry) └── Frostpeak
    └── Util: Signal, Create, CharacterUtil, Units
ServerScriptService
└── Server (Script, bootstrap)
    ├── Services: CourseService, PlayerService, EquipmentService
    └── Course: Heightfield, TerrainBuilder, PropBuilder, Environment
StarterPlayer.StarterPlayerScripts
└── Client (LocalScript, bootstrap)
    ├── Controllers: InputController, MovementController, CameraController
    ├── Cameras: ThirdPersonCamera, FirstPersonCamera, CameraMath
    └── UI: SportSelectUI, HudUI
Workspace.Course (generated at runtime): Props, Gates, Trees + Terrain
```

## Scripts

| Script | Responsibility |
|---|---|
| `Server` (init) | Starts PlayerService, builds the course, then starts the out-of-bounds watch |
| `CourseService` | Builds the default course; exposes `GetSpawnCFrame`, `GetKillY`, `WaitUntilReady`; sets `KillY` and `CourseReady` attributes on `Workspace.Course` |
| `Heightfield` | Course config → `height(x, z)`: blended slope profile, meandering centre line, banks, noise, rollers |
| `TerrainBuilder` | Writes the heightfield into smooth Terrain with `WriteVoxels` in Z chunks (Snow, with Rock on steep banks) |
| `PropBuilder` | Start pad and arch, finish arch and line, kickers, slalom gates, rocks, placeholder trees |
| `Environment` | Lighting, atmosphere, colour correction |
| `PlayerService` | Rider collision group, loading characters after the course is ready, sport selection, resets, server-side fall check |
| `EquipmentService` | Welds placeholder skis or a board under the feet |
| `Client` (init) | Starts the controllers and UI; routes the Roblox menu's Reset to the server reset |
| `InputController` | Keyboard, gamepad and touch → steer/tuck/brake axes, jump/camera/reset/zoom actions, look input |
| `MovementController` | The downhill physics (below) |
| `CameraController` | Owns the camera while riding, switches modes (V), speed-based FOV |
| `ThirdPersonCamera` / `FirstPersonCamera` | Individual camera modes; add new ones in `CameraController.Modes` and `CameraConfig.ModeOrder` |
| `SportSelectUI` | Discipline picker; requests the sport and closes when the server confirms it |
| `HudUI` | Speedometer, status, camera label, control hints, Change Sport button, landing and crash callouts |

## Movement physics

The Humanoid is switched to the `Physics` state so it stops driving the body. Every
`RunService.PreSimulation` step the controller integrates its own velocity and passes it to two
constraints on the HumanoidRootPart:

- **LinearVelocity** applies the commanded velocity, plus a spring term along the ground normal that
  holds the root at ride height (feet + board thickness) above the snow.
- **AlignOrientation** keeps the rider perpendicular to the smoothed slope normal, facing the
  heading, and leaning into turns.

Each step:

1. **Probe the ground** with 5 downward rays and average the normals so the result is stable on
   voxel terrain.
2. **Grounded:**
   - Remove velocity into the surface.
   - Add gravity projected onto the slope plane (`Gravity * sin(slope)`).
   - Turn the heading at a speed-dependent rate.
   - Subtract drag (`k·v²`, with less drag while tucking), snow friction and braking.
   - **Carving:** split velocity into forward and sideways parts along the heading. Grip decays the
     sideways part and 85% of it is redirected forward, so turns keep most of your speed.
   - **Pushing:** below 22 studs/s, tucking skates you forward on flat ground.
3. **Airborne:** apply gravity and light air drag; steering yaws the body (the base for spins later).
4. **Landing:**
   - Compare facing with travel direction, and measure impact speed into the slope.
   - Clean: under 25° and soft impact. Sketchy: up to 60°, costs 25% of speed. Hard: extra speed
     loss proportional to impact.
   - Over 60° or over the crash impact speed counts as a crash.
5. **Collisions:** the engine still resolves contacts. If the actual velocity is far below what was
   commanded (a tree or a rock), it's a crash above 45 studs/s and a bump below that.
   - **Crash:** the constraints switch off and the body tumbles.
   - **Recovery:** after 2.2 s you're stood up on the snow, facing your direction of travel.
6. **Jump:** applied along the slope normal, biased upward. It includes a 0.12 s coyote window, and
   impact checks are paused for 0.12 s so the velocity change isn't read as a collision.

Sport stats (`Speed`, `Acceleration`, `Handling`, `Stability`, `Airtime`) are multipliers that are
identical for both sports. Equipment (Phase 6) and ranked normalisation (Phase 7) will plug in
through `SportConfig.GetStats`.

Approximate numbers with the default config (1 stud ≈ 0.28 m): about 125 km/h on the steepest
section without tucking, about 160 km/h tucked, and a hard cap of 220 studs/s.

## Studio configuration

Everything is set by the project file or by code:

- `Players.CharacterAutoLoads = false` (in `default.project.json`). The server spawns players after
  the course is built.
- The `Riders` collision group is registered by PlayerService. Riders pass through each other
  (`MovementConfig.RidersCollide`).
- The course sits at `Origin = (0, 0, 1500)`, so it stays clear of the template Baseplate and
  SpawnLocation. You can delete those two from the place if you like.
- R15 and R6 avatars both work: ride height is computed from the rig.

## Testing checklist

Run `rojo serve`, connect the Rojo plugin in Studio, then press Play.

| # | Test | Expected |
|---|---|---|
| 1 | Join | Output shows `[CourseService] Built Frostpeak in ~2s`. Picker appears. |
| 2 | Pick Skiing or Snowboarding | Picker closes. Skis or a board appear. HUD shows `READY`, 0 km/h. |
| 3 | Hold W | You skate off the pad, then accelerate on the slope. `TUCK` shown. |
| 4 | A / D | Smooth carving turns with a lean. Little speed lost. |
| 5 | S | `BRAKING`. You slow down and can come to a stop. |
| 6 | Space | About 6.5-stud hop, about 0.7 s of air. `AIRBORNE`, then landing. |
| 7 | Hit a kicker at speed | Launch, then a `CLEAN` / `SKETCHY` / `HARD LANDING` callout with airtime |
| 8 | Ride into a tree or rock fast | `WIPEOUT!`. You tumble, then get stood back up after about 2 s. |
| 9 | V | Toggles third and first person. FOV widens with speed. In first person the body is hidden and the skis stay visible. |
| 10 | Right-drag, mouse wheel, I/O | Orbit or look around (eases back), zoom in third person |
| 11 | R, or Esc → Reset Character | `RESET TO START`, back on the start pad with zero speed |
| 12 | Fall off the world | Automatic reset (client, with a server backstop) |
| 13 | Change Sport (top right) | Picker reopens. Equipment swaps without a respawn. |

Debugging: set `MovementConfig.Debug = true` to write `Debug*` attributes (mode, speed, slope,
ride-height error, bumps, jumps) onto your HumanoidRootPart during play.

## Common errors and fixes

| Symptom | Cause / fix |
|---|---|
| Nothing happens and no picker appears | The Rojo plugin isn't connected, so the scripts aren't in the place. Run `rojo serve` and click Connect. |
| You never spawn | `CourseService` errored before `CourseReady`. Check Output for the error. |
| Character stands still on a slope and the HUD stays at 0 | Check Output for client errors. The movement step must never yield. |
| You stick to trees at low speed | Expected: steer away or press R. Collisions under 45 studs/s are bumps, not crashes. |
| `Infinite yield … PlayerModule` | This place has no default PlayerModule. Input reads devices directly and must not wait on it. |
| Camera clips through terrain | Raise `CameraConfig.ThirdPerson.CollisionRadius` |
| Speeds feel too high or low | Tune `Gravity`, `DragCoefficient` and `TuckDragMultiplier` in `MovementConfig` |

## Known limitations (deferred by design)

- No animations: the rider holds the default pose (Phase 2).
- The snowboard stance isn't sideways yet (Phase 2 animation).
- Mobile has touch buttons and look-swipe, but layout hasn't been tuned on devices.
- Gates are visual only; checkpoints and timing arrive in Phase 4.
- No race anti-cheat yet, because Phase 1 has no races or rewards.
