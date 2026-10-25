# Snow surface textures (Step 1)

Source photo sets are CC0 (no attribution required) from ambientCG:
- Snow005: fine grain, used under the groomed corduroy
- Snow004: soft wind-blown undulations, used for powder
- Snow007A: small clumps, mixed into the powder relief
- Snow010A: crusty detail, mixed into the packed band and powder

The corduroy grooves, colour grading and normal maps were generated from those in code
(1024 px, seamlessly tiling, OpenGL normals).

| Material (MaterialService) | Base | Studs/tile | Pattern | Color | Normal | Roughness |
|---|---|---|---|---|---|---|
| GroomedCorduroy (racing line) | Salt | 20 | Regular | rbxassetid://102811540842140 | rbxassetid://77996430019235 | rbxassetid://78684319406153 |
| PackedSnow (transition band) | Limestone | 18 | Organic | rbxassetid://138927776019857 | rbxassetid://101236015199762 | rbxassetid://125802414819321 |
| PowderSoft (edges, mountain) | Snow | 22 | Organic | rbxassetid://114670635638100 | rbxassetid://103938659778066 | rbxassetid://111653654054971 |

Revision 2 (Steep-inspired): smooth packed racing line with faint corduroy (about 15% strength),
a wind-packed band, thick irregular powder, deeper blue-grey hollows. Snow010A (crust) is also mixed in.

The MaterialVariants live in the place file (MaterialService); EnvironmentConfig sets them as the
base-material overrides at runtime. To change a texture: edit the PNG, upload it (Studio:
Asset Manager → Import, or via the asset upload tool) and paste the new ID into the variant.
