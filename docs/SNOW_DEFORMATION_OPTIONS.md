# Snow Deformation — Options Review (no implementation yet)

## The constraint that decides everything

**Anything drawn below the terrain surface is hidden by the terrain.** Roblox terrain is opaque and can't
be made locally see-through. So a groove whose floor sits *below* the surrounding snow can only come from:

1. **changing the terrain itself**, or
2. **raising a snow "skin" above the terrain** and shaping the groove into that skin, so the visible
   surface around the gear sits above the gear.

Shading and trails (what we have now) only *suggest* depth; they have no geometry. Every real-depth option
below is a version of (1) or (2).

## Roblox APIs checked (October 2026)

| API | Can it deform at runtime? | Collision | Limits / requirements |
|---|---|---|---|
| **Terrain (WriteVoxels / FillBlock etc.)** | Yes, true terrain change | Changes collision (for the client that edits it, locally) | 4-stud voxel grid: occupancy gives smooth *heights*, but nothing narrower than about 4 studs. A ski track is 0.85 wide. Writes cost several ms each; edits must be undone later. |
| **EditableMesh** (`AssetService:CreateEditableMesh`, `CreateMeshPartAsync`, `SetPosition` / `BatchSetValues`) | Yes, vertex positions can change every frame | Visual only; collision doesn't update unless the mesh part is re-created (we wouldn't) | 60k vertices / 20k triangles per mesh. Strict **client memory budget** (forum reports about 8 editable meshes per client before hitting it). **Not replicated**: each client builds its own (fine for cosmetics). **Published games: the owner must be 13+, age- and ID-verified, and enable "Allow Mesh & Image APIs"** in Experience Settings → Security. Fails by default otherwise. |
| **Skinned MeshPart + Bones** (`Bone.Transform`) | Yes, by moving bones of a pre-made mesh | Visual only | Needs a mesh authored with bones (Blender → FBX upload). Fixed shape topology; moving many bones per frame costs CPU. No verification needed. |
| **Parts / WedgeParts (pooled)** | Moved and resized, not deformed | Can be made non-colliding | Faceted look. That's what produced the "bubbles". |
| **Trails / Beams / Decals** | Texture only | — | No geometric depth (the current system) |

## Options

### A. Terrain stamping (true depth)
Each client carves shallow dents into its *own* copy of the terrain behind each rider, a few times a second,
and restores them after the track lifetime.
- **Looks:** real depth, native snow texture, perfect blending.
- **Limits:**
  - 4-stud resolution: a soft furrow about 4–6 studs wide, so two ski tracks merge into one.
  - Changes the local collision, so riders crossing a fresh track would dip slightly (realistic, but it
    touches the physics).
  - You asked to avoid continuous terrain edits.
- **Cost:** medium-high (voxel writes plus bookkeeping to restore), worst on mobile.
- **Verdict:** not recommended.

### B. EditableMesh "powder wake" (recommended, if you can enable the API)
A small, smooth, locally built snow mesh per piece of gear:
- **Bow / side banks:** a continuous, smoothly shaded mesh hugging the gear's sides, raised a little above
  the terrain at the gear and tucked *under* the terrain at its outer edges, so there's no seam.
  - It makes the snow look like it parts around the gear.
  - Its height comes from nose, middle and tail contact rays.
  - It grows on the carving edge and at braking, and drops away in the air.
- **Track ribbon:** a mesh ribbon behind the gear with **raised walls and a lower floor**.
  - Real geometry: the walls catch light and cast shadow on the floor.
  - Two narrow ribbons for skis, one wide one for the board.
  - Written as a ring buffer: each frame only the newest cross-section is written (about 7 vertices); old
    sections flatten and fade.
- **Texture:** UVs from world position, so the snow material lines up with the terrain.
- **Limits:**
  - The floor of the groove is at terrain level, with the walls above it. It reads as a groove pressed
    into a snow surface, not a hole below the terrain.
  - Raised material sitting on the terrain can never look *exactly* like the terrain (texture projection
    differs slightly).
  - **Publishing requires your ID verification and the API toggle.** It works in Studio regardless.
- **Cost:**
  - Local rider: 1–2 meshes, about 1–2k vertices, ~10–20 vertex writes per frame. Cheap.
  - Other riders: full effect only for the nearest 2–3; the rest keep the current texture groove.
  - Memory stays well under the client budget.

### C. Skinned-mesh ribbon (fallback if B isn't allowed)
Same idea as B, using a pre-made boned mesh (a ribbon with, e.g., 24 cross-section bones) driven by script.
- **Limits:**
  - Must be modelled and uploaded (Blender; I can generate the file, but you'd upload it).
  - Fixed length.
  - Slightly less flexible than B (cross-section shape is set by the bones).
- **Cost:** about 24 bone writes per frame per ribbon. OK for the local rider and a few others.

### D. Keep shading only (current)
Cheapest, but it doesn't give the physical feel you're asking for.

## Recommendation

**B (EditableMesh)**, keeping the current dig-in and groove texture as the base layer underneath it:
- The texture groove stays for distant riders and low-end devices.
- The mesh wake adds real geometry up close.

Contact detection uses nose, middle and tail raycasts per piece of gear, plus the existing
grounded/airborne state and steer, speed, brake and landing inputs.

**Decision needed from you:**
1. Can you (the experience owner) be 13+ ID-verified and turn on **Allow Mesh & Image APIs**?
   If **yes**, use B. If **no**, use C.
2. Quality tiers: full wake for the local rider plus the nearest 2–3 riders, texture groove for everyone
   else. Is that OK?

**First step if approved:** a Studio-only prototype of the board's side banks and track ribbon, with
screenshots and frame-time numbers, before any polish or the ski version.
