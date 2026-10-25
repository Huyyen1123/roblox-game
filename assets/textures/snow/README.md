# Snow surface textures (Step 1)

Source photo sets are CC0 (no attribution required) from ambientCG:
- Snow005: fine grain, used under the groomed corduroy
- Snow004: soft wind-blown undulations, used for powder
- Snow007A: small clumps, mixed lightly into the powder relief

The corduroy grooves, colour grading and normal maps were generated from those in code
(1024 px, seamlessly tiling, OpenGL normals).

| Material (MaterialService) | Base | Studs/tile | Color | Normal | Roughness |
|---|---|---|---|---|---|
| GroomedCorduroy | Salt | 8 | rbxassetid://86121615919949 | rbxassetid://114741866047851 | rbxassetid://121505661909314 |
| PowderSoft | Snow | 20 | rbxassetid://73187914255542 | rbxassetid://80097658085105 | rbxassetid://96314852685986 |

The MaterialVariants live in the place file (MaterialService); EnvironmentConfig sets them as the
base-material overrides at runtime. To change a texture: edit the PNG, upload it (Studio:
Asset Manager → Import, or via the asset upload tool) and paste the new ID into the variant.
