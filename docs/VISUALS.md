# Visual Overhaul: Environment

Benchmark section: **Frostpeak start → first steep (course Z 0–650)**. Its level of quality is the
target for the rest of the mountain, the resort and the UI.

## What made the old environment look low quality

| Problem | Source | Fix |
|---|---|---|
| Triangular mountains | `BackdropBuilder` (CornerWedge pyramids) | Removed. Terrain mountain ranges plus a mountain-panorama skybox seen through the haze. |
| Pyramid trees | `ForestBuilder` procedural pines | Snow-laden spruce MeshParts from the Creator Store, placed by the same forest logic |
| Flat, plastic-looking snow and rock | Stock terrain textures | AI-generated PBR MaterialVariants set as terrain material overrides |
| Dark wall along the piste edge | A `softRamp` bug in `Heightfield` that made an 11–13 stud step at the edge | Ramp is now exactly 0 until its knee |
| Bare, empty course edges | Netting only | Snowbanks against the netting, red banners, trail markers, run sign (benchmark section) |

## Where everything lives

| Element | How it's made | Where |
|---|---|---|
| Landscape, cliffs, valley, lake, ranges | Luau → smooth Terrain (baked into the place) | `src/server/Course/Heightfield.luau`, `TerrainBuilder.luau`, config in `Frostpeak.luau` → `World` |
| Snowbanks | Terrain (heightfield ridge) | `Heightfield:Snowbank`, `Frostpeak.Dressing` |
| Snow and rock textures | AI-generated MaterialVariants | **Place file**: `MaterialService` (`AlpineSnowWhite1`, `AlpineGraniteCliff`, `AlpineDarkSlate`). Selected in `EnvironmentConfig.MaterialOverrides`. |
| Pine trees | Creator Store MeshParts | **Place file**: `ServerStorage/Assets/Trees` (`SpruceTall` = asset 11590212184, `SpruceSlim` = asset 76188132698241) |
| Distant panorama | Creator Store skybox (asset 402232085) | Texture IDs in `EnvironmentConfig.Sky` |
| Lighting, haze, clouds, post effects | Luau | `EnvironmentConfig.luau` → `Environment.luau` |
| Netting, gates, arches | Luau Parts | `PropBuilder.luau` |
| Banners, markers, run sign | Luau Parts | `DressingBuilder.luau` (Z range in `Frostpeak.Dressing`) |

Every imported asset was audited when inserted: no scripts, only meshes, textures and a Sky.
Models with scripts, or tens of unions, were rejected.

## Studio steps

1. **Save the place** (Ctrl/Cmd+S). Baked terrain, MaterialVariants and tree templates live in the
   place file, not in git.
2. To try a different tree: insert it into `ServerStorage/Assets/Trees` as a Model. Placement
   measures its size and base automatically. Delete any scripts it contains first.
3. To rebake terrain after changing a terrain-affecting value in `Frostpeak.luau`: bump
   `World.TerrainVersion`, playtest once (it regenerates in about 5 s), or run
   `require(game.ServerScriptService.Server.Services.CourseService).Init()` in the command bar
   (restart Studio first if that module was already required this session). Then save.
4. To swap a terrain texture: change `Variant` in `EnvironmentConfig.MaterialOverrides` to any
   MaterialVariant in MaterialService.

## How to compare

- Playtest, then press Esc → Settings → Graphics Quality → set it **manually to high**. On
  Automatic, a laptop on battery drops to low quality and draws almost nothing in the distance.
- Ride the first 650 studs: groomed snow, netting on snowbanks, banners, spruce stands, cliff
  bands, peaks rising out of the valley mist. Then ride past z 650, where the course has only
  netting and no dressing, for a before/after comparison.

## Performance notes

- About 3,400 parts in the course: the spruces are 1–3 MeshParts each, and identical meshes are
  instanced.
- Tree meshes never collide. Trees near the piste get one invisible trunk collider. Far trees
  cast no shadows.
- Streaming is disabled so distant terrain is always present. Terrain is baked, so server start
  takes 0.15 s.

## Next (pending sign-off of the benchmark)

1. Roll the dressing out over the whole course (widen `Frostpeak.Dressing`).
2. Racing gates: replace the plain panels with proper GS gates and banners.
3. Resort at the base: lodge, shops, gondola station, cabins. These need imported architecture
   meshes (Creator Store packs or Blender) plus Luau layout.
4. Snow VFX: carving spray, brake spray, landing puffs, ambient snowfall.
5. HUD redesign.
