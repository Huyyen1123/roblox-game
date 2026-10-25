# Snow Visual System — Step 0 Findings and Plan

Status: **plan only, awaiting approval.** Checkpoint tag: `snow-phase-start`.

## What exists today

| Area | Current state | Problem |
|---|---|---|
| Terrain material | Every snow voxel, piste and edges alike, is `Snow` with one MaterialVariant override (`AlpineSnowWhite1`, 16 studs/tile, colour + normal + roughness maps) | One look everywhere, so it reads as a flat white ramp. No groomed vs powder distinction. |
| Material choice | `TerrainBuilder.chooseMaterial` uses `Heightfield:DistanceFromPiste()` (piste half-width 70) | The piste boundary is already known in code, so splitting materials is easy |
| Terrain bake | Baked into the place, keyed by `TerrainVersion = 10` | A material change needs a rebake (version 11). Geometry would be identical. |
| Tracks | One Roblox `Trail` per ski (or board), attached to the gear base. Lifetime 2.5 s, flat blue-white ribbon. | Tilts with the edge angle, can float over dips and crests, too short-lived, no texture, looks like a flat strip |
| Spray | Two emitters on the HumanoidRootPart (left/right of the tails): outside-edge carve, braking, light cruise dust. Built-in smoke texture. | Not tied to the actual ski/board edge; no takeoff burst; one look for every surface; the texture reads as haze, not snow |
| Landing puff | One emitter at the centre, scaled by impact | Fine; will be re-tuned per surface |
| Ground state | `Grounded` (physics) and `TrickAir` (debounced air) on the movement state; other riders send `RiderAir` | Reusable. Effects currently use raw `Grounded` (can flicker on crests). |
| Physics | Movement never reads the terrain material (friction and grip come from `MovementConfig`) | **A material split cannot change speed, grip, steering or braking.** |

## Architecture

### 1. Surfaces (Step 1)
- **Groomed piste:** move the racing line to its own base material (`Salt`, which is currently unused). Give it a new
  MaterialVariant `GroomedCorduroy`: fine corduroy grooves, firm, slightly blue-grey, low shine.
- **Powder:** the edges and banks stay `Snow`, retuned: softer, less uniform, slightly brighter.
- **Transition:** a noisy 4–8 stud blend band at the piste edge, so there's no straight voxel line.
- **Rebake:** `TerrainVersion` 10 → 11, rebuilt from the same heightfield, so the shape and collision are unchanged.

Roblox terrain only allows one variant per base material, which is why the piste needs a second base material. Our
custom physics ignores the material, so this is purely visual.

**Assets needed (honest list):**
- **Groomed corduroy snow:** a tileable colour, normal and roughness set (about 1K). Either I generate it with the
  Studio material generator, or we import a CC0 photo set (e.g. from ambientCG or Poly Haven) and upload it to your
  account. I'll show you both before committing.
- Scripts can't produce good texture art. The simple masks below (track groove, snow sprite) I can make precisely in
  code as PNGs; the snow surface itself needs real texture art.

### 2. Equipment contact (Step 2)
- Moving the rider or the gear down would break the foot-to-binding IK and change the ride height (physics). Rejected.
- **Visual alternative:** thin, snow-coloured "displaced snow" lips welded along each ski's and the board's sides at the
  base, only visible while that gear is touching snow. They're barely there on groomed snow and taller and softer in
  powder. Combined with the track groove underneath, the gear reads as sitting *in* the snow. Cost: 2 small parts per
  ski or board, toggled, with no extra physics.
- The edge that's engaged (from the lean) shows a slightly larger lip: inside edge for skis, toe or heel edge for the
  board.

### 3. Tracks (Step 3) — improve the existing Trail system rather than duplicating it
- Each ski (or the board) gets a **track anchor**: an anchored, non-colliding, invisible client-side part. Each
  frame it's raycast down onto the terrain under the gear tail, sat 0.03 studs above the surface and aligned to the
  surface normal, *not* to the edge roll. The existing Trail rides on that anchor, so tracks follow the terrain
  without floating, tilting or z-fighting.
- The trail texture will be a soft-edged groove: a slightly darker, shaded centre with lighter compressed rims.
  Generated precisely in code and uploaded. Low contrast, no glow (LightEmission 0, LightInfluence 1).
- Two narrow tracks for skis (about 0.5 studs each), one wide track for the board (about 1.5 studs).
- Tracks only emit when the gear is actually within ~0.35 studs of a snow surface: none in the air, none on
  rock or ice, and nothing while stopped.
- Lifetime: 14 s (High), 8 s (Medium), 4 s (Low). Trails fade by themselves (a transparency curve) and need no
  per-segment objects, so memory stays bounded by design.
- Other riders get the same tracks from their replicated position (no extra network traffic), with shorter lifetimes
  and only within a set distance.

### 4. Spray (Step 4)
- Emitters move from the root onto the **gear edges**: each ski's inside and outside edge near the tail, and the
  board's toe and heel edges.
- Context table: cruise (barely), gentle carve, aggressive carve, brake (ski snowplow: both inner edges forward;
  board: heel-edge fan), **takeoff burst (new)**, landing (by impact).
- **Surface-aware:** a raycast reads the material under the gear. Powder (`Snow`) gives bigger, softer, slower
  particles; groomed (`Salt`) gives smaller, crisper ones; rock and ice give none.
- New snow-clump sprite texture (made in code), short lifetimes, rate caps per rider, and fewer particles for distant
  riders.

### 5. Quality tiers and performance (Step 5)
- `EffectsConfig.Quality = { High, Medium, Low }`, picked automatically from the player's Roblox graphics level.
  Each tier sets track lifetime, track draw distance, particle rate multiplier, max particles per rider and remote-rider
  detail.
- Everything is client-side cosmetic; no new RemoteEvents (other riders are rebuilt from replicated state).
- Cleanup on respawn and sport switch is already handled by the rig system. I'll add checks for leftover anchors and
  emitters.

## Safety
- Git tag `snow-phase-start` marks the code before this phase.
- Terrain lives in the place file. It can be regenerated from code (TerrainVersion), but **please save a copy of the
  place** (File → Save to File As → `backups/`) before Step 1.
- No changes to: movement or physics config, joints, IK, equipment geometry, camera, HUD or checkpoints.

## Files to change
- `server/Course/TerrainBuilder.luau`: material split and blend band (Step 1)
- `shared/Config/Courses/Frostpeak.luau`: TerrainVersion 11, surface settings (Step 1)
- `shared/Config/EnvironmentConfig.luau`: new MaterialVariant override (Step 1)
- `shared/Config/EffectsConfig.luau`: surfaces, quality tiers, track and spray settings (Steps 2–5)
- `client/Controllers/EffectsController.luau`: track anchors, edge emitters, contact lips, surface detection (Steps 2–4)
- New `client/Effects/SnowSurface.luau`: raycast and material classification shared by the effects (Step 2)
- `server/Services/EquipmentService.luau`: only if the contact lips are built with the gear (otherwise client-side)
