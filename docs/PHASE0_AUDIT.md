# Phase 0: Project Audit

Audit date: 2026-10-23. Code baseline: git tag `phase0-baseline` (commit `d9e9a3c`).

## How this audit was done

- I read every script in the repo (29 Luau files, about 4,200 lines). Rojo syncs them into Studio,
  so the repo is the source of truth for code.
- I inspected the live Studio place read-only through the playtest server DataModel: scripts
  outside the Rojo trees, ServerStorage, MaterialService, Lighting, Workspace contents, place
  settings and publish status.
- Speeds come from earlier playtests in this project (sampled AssemblyLinearVelocity), not
  estimates, except where marked.

## A. What exists

| System | Where | State |
|---|---|---|
| Rojo workflow | `default.project.json`, `src/` | Working. Code lives in git and syncs live into Studio. |
| Movement controller | `client/Controllers/MovementController` (691 lines) | Working: gravity along the slope, carving, tuck, brake, jump, landing quality, crash and recover, reset. Uses LinearVelocity and AlignOrientation on the root with the Humanoid in the Physics state. |
| Input layer | `client/Controllers/InputController`, `Config/InputConfig` | Action-based (ContextActionService). Keyboard, gamepad and touch buttons. |
| Camera | `client/Controllers/CameraController` + `Cameras/*` | Third person (default) and first person, V to toggle, speed-based FOV, collision avoidance. |
| Sport selection | `client/UI/SportSelectUI`, `server/Services/PlayerService` | Working, server-validated. Placeholder skis and board in `EquipmentService`. |
| HUD | `client/UI/HudUI` | Rectangular speedometer, status, callouts, Change Sport button. |
| Course | `server/Course/*`, `Config/Courses/Frostpeak` | One generated course, about 2,310 studs long, with terrain baked into the place. Kickers, visual-only gates, netting, forest, dressing in the first 650 studs. |
| Environment | `Config/EnvironmentConfig`, `server/Course/Environment` | Future lighting, atmosphere, skybox, clouds, post effects, AI-generated terrain materials. |
| Remotes | `ReplicatedStorage.Remotes` | `SelectSport`, `RequestReset`, `ResetState` |

Place-file-only content (not in git): baked terrain (7.3M cells, version `Frostpeak:10`), 16
MaterialVariants (3 in use), `ServerStorage/Assets/Trees` (2 spruce models), the template
Baseplate and SpawnLocation (the latter two and the unused variants were removed after the
audit; see E).

## B. Problems found

Ranked by the spec's priorities (gameplay feel first).

### Gameplay feel

1. **Speeds are roughly 3× the spec targets.** Measured: 126 studs/s (about 127 km/h) on the
   steep section. The config allows about 160 km/h tucked and caps at 220 studs/s (about
   222 km/h). The spec wants a 25 km/h cruise, 38–40 racing, about 48 tucked and a 55 km/h cap.
   That's about 55 studs/s at 1 stud = 0.28 m. The physics constants need retuning, not just the
   HUD.
2. **Course length versus the 90 s target.** At spec speeds (about 40 studs/s on average), the
   current 2,310-stud line takes about 60 s (estimate). The beginner course needs to be about
   3,500 studs, or slower. That's Phase 3 work. The current build doesn't finish in 5 s; the
   "5 seconds" problem from the spec doesn't apply to this version.
3. **Controls conflict with the spec.** Currently W = tuck, S = brake, Space = instant jump. The
   spec wants Shift = tuck, Ctrl = brake, hold-to-charge Space, and W/S/A/D for flips and spins in
   the air. A/D steering on the ground is unchanged.
4. **Crashes use a violent tumble.** The constraints switch off and the body spins at random.
   The spec asks for a stumble with a speed loss and brief reduced control for ordinary mistakes.
   Only severe impacts should fully crash.
5. **No charged jump** and no stumble or recovery states.
6. **No animations.** Riders keep the default pose. The snowboard stance isn't sideways, and
   there's no regular/goofy option.

### Correctness and multiplayer

7. **No racer collisions at all.** The `Riders` group doesn't collide with itself. The spec
   requires grounded bumps, airborne ghosting and grace periods. The current collision-group
   setup is a good base for that.
8. **No race system.** Gates are visual only. There are no checkpoints, timing, countdown or
   placements.
9. **The client owns movement with no server plausibility checks.** That's fine for Phase 1
   responsiveness, but the race phase needs server-side checkpoint, speed and time validation.

### Platform

10. **The place is unpublished** (PlaceId 0). DataStoreService, MemoryStoreService,
    MessagingService and TeleportService/reserved servers all need a published experience, plus
    "Enable Studio Access to API Services" for Studio testing. This blocks Phases 6–7. Publishing
    privately is not a public launch: new experiences are private until you make them public.
11. **Single-place architecture.** The resort and race Places don't exist yet. The shared-code
    plan must cover multiple Places (see Decisions).

### Maintainability

12. **MovementController is a single 691-line module.** It's cohesive, but Phase 1 changes
    (charge, stumble, collisions hook) should split it into ground probe, integrator and
    landing/stumble modules.
13. **Place-file content isn't backed up.** Terrain, materials and tree templates exist only in
    the open Studio session. Git covers the code that regenerates the terrain, not the AI
    materials or imported trees.
14. **Leftovers:** template Baseplate and SpawnLocation, 13 unused MaterialVariants (cleaned up), the
    `MovementConfig.Debug` flag, and a recurring Output warning
    (`rbxassetid://203785492 … Asset type does not match`). I haven't traced the source of that
    warning; it doesn't come from our scripts.
15. **Sport stats** are identical placeholders. The spec now says equipment stats apply in both
    modes with balanced tradeoffs. The `SportConfig.GetStats` hook is ready for that (Phase 8).

## C. What to keep

- Rojo + git workflow, and the config-module pattern (`MovementConfig`, `CameraConfig`, course
  configs).
- The constraint-based movement core and its signals (`Landed`, `Crashed`, `ModeChanged`). It
  gets retuned and restructured, not rewritten.
- The InputController action layer. It gets remapped to spec controls; its structure fits the
  "unified action layer" requirement.
- The camera module design (mode modules + controller).
- Server-validated sport selection and reset flow.
- The course pipeline: Heightfield, baked terrain and builders, reused for new mountains.
- Environment and asset pipeline: MaterialVariants, the tree-template hook, EnvironmentConfig.

## D. Backup and checkpoint plan

| What | How | Status |
|---|---|---|
| Code | git, pushed to the private GitHub repo; tag `phase0-baseline` | Done |
| Place file | **You:** File → Save to File As → `~/Projects/roblox-game/backups/ProjectDownhill-phase0.rbxl` (I'll add `backups/` to `.gitignore`) | Pending |
| Ongoing | A tag per approved phase (`phase1-approved`, …) plus a place backup after each phase that changes place-only content | Proposed |
| Later | Publishing privately gives Roblox's built-in place version history as a second backup | Pending your decision |

## E. Decisions (answered 2026-10-23)

1. **Publishing:** wait. Publish privately when cross-server matchmaking and teleports are tested
   (Phase 6).
2. **Shared code across Places:** one Rojo codebase with separate resort and race Places (one
   project file per Place, sharing `src/shared`).
3. **Cleanup:** done carefully, without touching the slope or gameplay.
   - Template Baseplate (2048-stud slab at the origin, no overlap with the course): removed.
   - Template SpawnLocation: replaced by an invisible, non-colliding `CourseSpawn` on the start
     pad (created by `PropBuilder`), then removed. Verified in a playtest: the character spawns
     on the start pad at full health, sport selection, equipment and HUD work, and riding works.
   - 13 unused MaterialVariants removed (the earlier count of 12 was wrong). Kept and verified as
     terrain overrides: `AlpineSnowWhite1` (Snow), `AlpineGraniteCliff` (Rock),
     `AlpineDarkSlate` (Slate). No parts referenced any variant.
   - These are place-file changes: save the place to keep them.

## F. Proposed Phase 1 scope (after approval)

Core movement only, tested on the existing slope:

- Retune physics to the spec's speed targets and calibrate km/h.
- Remap controls: Shift tuck, Ctrl brake, hold-to-charge Space; reserve W/S/A/D in the air for
  Phase 4 tricks.
- Charged jumps (tap = hop, hold = bigger jump, capped).
- Stumble and recovery for poor landings and minor impacts. Full crashes only for severe ones,
  with no violent tumbling.
- Split MovementController into focused modules, with the same external interface.
- Repeatable test: a scripted speed and timing log on a fixed slope, compared against the
  targets.
