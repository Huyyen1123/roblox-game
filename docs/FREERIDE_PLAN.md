# Open-Mountain Freeride Test Map — Step 0 Audit and Plan

Status: **plan only, awaiting approval.** Supersedes the narrow-course direction for new maps.
Frostpeak stays as it is, as a separate test area.

## Audit: what exists

| System | Today | Reusable for freeride? |
|---|---|---|
| Course registry (`Config/Courses`) | One course, `Frostpeak`; `CourseService` builds only the `Default` one | Yes. Add a second course and build both. |
| Heightfield | Built around **one racing line**: a 1-D slope profile along Z, a meander, a 140-stud piste and scenery either side | **No.** Open mountains need a true 2-D generator. Same interface, new module. |
| TerrainBuilder | Chunked WriteVoxels, version-keyed bake into the place, per-column material choice | Yes. Pass it the new heightfield and a freeride material rule. |
| Terrain bake key | One attribute on `Workspace.Terrain` (`Frostpeak:12`) | Needs to become per-course. |
| Movement physics | Never reads the terrain material; ground probe plus hover handles any shape; slopes over 55° count as not ground (cliffs) | Yes, unchanged |
| Kickers | Bright `WedgePart`s with hard edges | Replace with **terrain-sculpted** snow kickers on the new map |
| **Race logic** | **None yet.** The gates are decoration; there are no checkpoints, timer, results or validation. (The roadmap scheduled this for Phase 4.) | To build in Step 3, server-authoritative |
| Spawn / reset | Server spawn slots at the course start; R or menu reset to start | Yes. Point it at the selected course's summit. |
| Control guide (HUD) | Key chips bottom-left, each fades after first use; grab/tweak rows show for both sports | Keep. Make it sport-aware, plus a key to show it again (H). |
| Minimap | None | New (Step 4) |
| Snow look | Three materials (groomed, packed, powder), a 1K texture each; about 710 drift parts on Frostpeak | Freeride uses **one** powder material; drifts become terrain shape, not parts |
| Streaming | Off | Fine for this size. Revisit before launch. |

## The new mountain (working name: "Summit Ridge")

- **Location:** its own area at world X ≈ +7000, well clear of Frostpeak (which ends at about X = +1600).
  Dev keys teleport between the two. The freeride map becomes the default spawn while testing.
- **Size:** about **2,400 studs wide × 5,600 studs long** (about 670 m × 1.6 km), playable from the summit to the finish.
  That's roughly 2.5× Frostpeak's run and about 15× its rideable area. A run is about 1.5–3 minutes depending on route.
- **Shape:** generated as a real 2-D mountain, seeded so it's the same every time:
  - **Summit plateau start:** a wide, gentle 3–5° shelf with room for 8+ racers.
  - **Main bowl:** wide powder fields (12–20°) that split into **three corridors** separated by rounded
    ridgelines:
    - **left:** gentle beginner valley (8–14°), long and safe;
    - **middle:** fast open face (18–26°);
    - **right:** advanced terrain (25–35°), with rollovers and a few rock bands (cliffs over 55° are rock,
      so riders can't ride them as ground).
  - The corridors **rejoin** in a lower valley, then a run-out to a wide, flat **finish basin**.
  - **Edge walls:** steep rocky ridges bound the map, so it reads as natural and keeps riders in.
- **Restart:** R (existing) returns you to the summit. At the finish basin, a "back to summit" prompt teleports you
  after a few seconds.

## Snow, kept deliberately lightweight (per your clarification)

- **One** powder MaterialVariant (the soft PowderSoft set, Organic tiling so there's no repetition) everywhere, plus
  the existing rock material on cliffs. **No corduroy** anywhere on this map, and no extra textures.
- **Depth comes from shape, not objects:**
  - gentle **wind-shaped ridges, rounded drifts and snowbanks are baked into the terrain itself**
    (low, smooth noise layers: 0.5–3 studs high, wide and rounded);
  - they cost nothing at runtime (no parts, no scripts) and are gentle enough for the existing hover and
    ground probe to ride smoothly.
- **Shading:** the late-afternoon light from the last step (cool blue-grey shadows, low warm sun) brings out
  that shape. The terrain colour is tinted slightly blue-grey in hollows and on shaded faces.
- **No** drift parts, real-time deformation, high-res textures, or new particles in this phase.
  Snow interaction (tracks and spray) stays a later, lightweight phase.

## Trick area

- A dedicated **park bowl** beside the beginner corridor, reached from the summit:
  - **small**, **medium** and **large** kickers, plus one **natural kicker** (a rounded lip on a rollover);
  - each with a **long, steep landing slope** (25–30°), and a wide flat run-out back to a lift teleport.
- Built **into the terrain** (smooth sculpted ramps), so there are no part seams or bright colours.
- Sized from the existing jump physics (air gravity 92 studs/s²). Airtime when landing on a 27° slope:

  | Kicker | Approach speed | Lip angle | Airtime | Fits |
  |---|---|---|---|---|
  | Small | about 35 studs/s | 18° | about 0.6 s | 180 / 360 |
  | Medium | about 55 studs/s | 22° | about 1.0 s | 360 / 540 |
  | Large | about 75 studs/s | 25° | about 1.4 s | 540 / 720 |
  | Natural | ride-dependent | 15° | 0.6–1.0 s | style air |

  An approach ramp of the right length sets each speed, so it's consistent. Final numbers get measured in Studio.
- No changes to jump physics or trick controls.

## Open-mountain racing (Step 3)

- **Checkpoints are wide "gates"** (60–150 studs) marked by subtle flags and banners, placed so every corridor can
  reach each one. Order matters; any line between them is allowed.
- **Server-authoritative:** the client reports a crossing, and the server checks order, position and plausible
  timing against replicated positions. Then come a timer, finish time and results.
- This is new race logic (none exists yet). It slots into the existing player and replication setup.

## Minimap (Step 4)

- **Pre-generated map image, not real-time terrain.** The freeride terrain uses a deterministic noise
  function that I implement **identically in Lua and in a small offline Python script**. The script renders
  a shaded-relief top-down map (snow white, blue-grey shading, rock grey, corridors visible) at 512 px, which
  is uploaded once.
- In-game, the image sits in a small rounded frame (top-left, clear of the speedometer and controls). It rotates
  with the camera heading, with a north marker. It shows player and racer dots (facing arrow for you), start,
  finish and checkpoints. The cost is a handful of UI frames updated each frame.

## Control display

The existing guide stays. It becomes sport-aware: grab and tweak rows show only for the snowboard (skis don't use
them yet). **H** shows the full guide again after it fades. Layout and keys are otherwise unchanged.

## Steps (approval after each)

1. **Mountain terrain plus powder snow:** new 2-D heightfield generator, freeride material rule,
   per-course bake key, dev teleport between maps, default spawn on the summit.
2. **Trick park:** sculpted kickers and landings, airtime measured in Studio.
3. **Checkpoints and racing:** wide gates, server validation, timer and results.
4. **Minimap:** offline relief render, minimap UI. Control guide made sport-aware with H to show it again.
5. **Test and optimise:** frame rate, memory, multiplayer, low-end settings.

## Performance budget

- Terrain is about 2× Frostpeak's voxel area, baked once into the place (about 15–25 s to rebuild in Studio;
  not at game start).
- No decorative parts on the new map. Trees and rocks stay out until the scenery phase.
- One extra texture set and one 512 px map image.
- Frostpeak's 710 drift parts only exist on Frostpeak. They can become terrain-shaped drifts later too.

## Risks and how they're handled

- **Steep or rough terrain vs the ride-height hover:** drifts stay smooth and low; cliffs are rock at over 55°
  (already treated as "not ground"). Step 1 includes a ride test on every corridor.
- **Larger place file:** stays well within Roblox limits. Save a local `.rbxl` backup before Step 1.
- **Checkpoint cutting on an open map:** gates are wide enough for every route, and the server checks order
  and timing.
