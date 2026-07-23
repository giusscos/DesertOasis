# Desert Oasis – Camp & Tool Asset Prompt

Use these prompts in Claude Code (or another AI assistant with Blender/Python access)
to generate the gameplay props for the camp / water-delivery loop. Each section is
self-contained and can be given as an independent prompt.

**Style (all assets):** low-poly, slightly stylised Zelda Wind Waker aesthetic — same
look as existing `lobby_*` and `prop_*` assets. Warm desert palette (khaki, sand,
weathered wood, brass, faded canvas). Export each as `.usdz` with UsdPreviewSurface
materials. Origin at ground contact centre; faces +Z in SceneKit terms. Scale in metres.

**Game context (for the generator):**
Players start at a desert camp of tents (the player’s plus neighbour tents). The main
goal is to find oasis water, carry it back, and fill the camp water store to help
neighbours. On journeys they meet NPCs who need help or who help them. Tools
(bucket, water compass, water detector) support exploration and water delivery.

**Reuse note:** `lobby_tent.usdz` can be placed for camp tents until a smaller travel
tent exists. Prefer new props below over duplicating lobby-only furniture.

---

## 1. Camp Water Store

**Prompt:**

Create a camp water-delivery prop for Desert Oasis in Blender using Python (bpy).
Style: low-poly Zelda Wind Waker, weathered desert camp. Export as `.usdz`.

### `prop_water_barrel.usdz`
- Large wooden water barrel / cistern the player pours collected water into.
- Size ≈ 1.0 m diameter × 1.2 m tall (fits next to a tent).
- Weathered oak staves, dark iron bands, slightly stained from water.
- Open top (or removable lid as a child node `lid`) so it reads as fillable.
- Named child nodes for SceneKit interaction:
  - `fill_point` — empty transform at the pour/dump target (top centre, ~1.15 m up).
  - `water_surface` — flat disc or cylinder top inside the barrel (blue-green water
    material). Scale Y (or morph) will be driven in code from empty → full; author
    the mesh at **full** water height so the game can shrink it.
  - `interact_zone` — invisible empty or simple box marker ≈ 2 m wide around the barrel
    (origin at ground) for proximity / tap detection.
- Optional: small wooden spout or ladle hanging on the side (static).
- No animation required (fill level is code-driven).
- Materials: wood (rough), metal bands (slightly metallic), water (slightly translucent
  blue-green; mild roughness).

---

## 2. Handheld Tools

**Prompt:**

Create three handheld adventure tools for Desert Oasis in Blender using Python (bpy).
Style: low-poly Zelda Wind Waker, readable silhouette from third-person camera.
Export each as `.usdz`. Origin at the **grip** (where a hand would hold it) so they
parent cleanly to a character hand bone later. Faces +Z when held “forward.”

### 2a. Bucket (`prop_bucket.usdz`)
- Classic desert water bucket for scooping oasis water and carrying it to camp.
- Size ≈ 0.35 m diameter × 0.40 m tall; wooden staves + iron bands + rope handle arch.
- Named children:
  - `water_fill` — disc of water inside, authored at full; game hides / scales when empty.
  - `handle` — the rope/wood handle (for optional swing animation later).
- Two visual states are fine as one mesh + `water_fill` visibility:
  - Empty: hide `water_fill`.
  - Full: show `water_fill` (blue-green, slight transparency).
- No required animation. Keep polygon count modest (~200–600 tris).

### 2b. Water Compass (`prop_water_compass.usdz`)
- Pocket / handheld compass that points toward the nearest oasis (needle driven in code).
- Size ≈ 0.12 m diameter × 0.04 m thick; brass/bronze body, glass-looking top
  (clear or slightly tinted), parchment dial with simple oasis / drop markings.
- Named children (critical for SceneKit):
  - `needle` — pivot at compass centre; rotates around local **Y** (up) in SceneKit.
    Author pointing +Z at rest (0° = “forward”).
  - `dial` — static face under the needle.
  - `lid` (optional) — hinged cover; if included, closed by default; simple open pose
    not required for v1.
- Materials: brass (metallic), dial (matte paper), needle (dark metal with a red tip
  for readability).
- No baked animation — the game rotates `needle` toward oasis direction.

### 2c. Water Detector (`prop_water_detector.usdz`)
- Hand tool that “pings” when near moisture / underground water (gameplay-driven).
- Size ≈ 0.45 m long (wand/scanner feel); mix of wood grip + brass/copper coils or
  dish + small gauge — readable fantasy tech, not sci-fi chrome.
- Named children:
  - `antenna` or `dish` — the sensing end (faces +Z).
  - `gauge_needle` — small dial needle on the body; game rotates it for signal strength
    (local Z or X rotation; document which axis in the blend). Prefer rotation around
    local **Z**, 0 = empty, ~90° = strong signal.
  - `lamp` — small emissive bulb/gem on the housing (warm amber). Game can pulse
    emission intensity; author a modest emissive material (intensity ~0.3–0.8).
- Optional idle: 30-frame subtle `idle` wobble on `antenna` only (loop-safe). Not required.
- Keep silhouette distinct from the compass so inventory icons stay clear.

---

## 3. Optional Camp Flavour (do after core props)

**Prompt:**

Create optional camp props for Desert Oasis. Same low-poly Wind Waker desert style.
Export each as `.usdz`.

| File | Description |
|---|---|
| `prop_camp_tent.usdz` | Smaller travel A-frame tent ≈ 3.5 m wide × 4 m deep × 2.2 m peak (lighter than `lobby_tent`). Open entrance +Z. Canvas khaki, wood poles. Good for neighbour tents around the home camp. |
| `prop_campfire.usdz` | Ring of stones + wood pile ≈ 1.2 m wide. Emissive orange coals (`embers` child). Optional 30-frame flicker on emissive intensity or flame planes. |
| `prop_water_jug.usdz` | Ceramic / leather canteen ≈ 0.25 m; alternate carry visual when the player has a small amount of water (not a full bucket). |
| `prop_trough.usdz` | Long wooden animal/people watering trough ≈ 1.8 m × 0.5 m; alternative or companion to the barrel for “shared camp water.” Include `water_surface` + `fill_point` like the barrel. |
| `prop_camp_sign.usdz` | Weathered wood post + plank ≈ 0.9 m tall plaque. Camp stats (barrel %, oasis stage) are drawn in code on the face — leave a flat `sign_face` child (~0.7 × 0.45 m) facing +Z for SceneKit text / decals. Optional carved border only; no baked numbers. |

Only generate these if the core barrel + three tools are already done.

---

## 4. Naming & Export Checklist

1. File names must match exactly: `prop_water_barrel`, `prop_bucket`,
   `prop_water_compass`, `prop_water_detector` (plus optional props above).
2. All interactive parts must be **named child nodes** as specified — SceneKit finds
   them by name.
3. Apply scale (1,1,1), apply transforms before export; real-world metre scale.
4. Prefer a single root empty/object named the same as the file (without extension).
5. Emissive parts (`lamp`, campfire `embers`): keep HDR modest so SceneKit bloom
   does not blow out (match lobby lantern restraint).
6. After export, place `.usdz` files under `DesertOasis/Assets/` and add them to the
   Xcode target like the existing props.

---

## 5. SceneKit Integration Notes

```swift
// Static prop
let barrel = AssetLoader.loadProp("prop_water_barrel")
if let fill = barrel.childNode(withName: "water_surface", recursively: true) {
    fill.scale.y = CGFloat(fillFraction) // 0...1
}

// Compass needle (degrees around Y, oasis direction in XZ)
if let needle = compass.childNode(withName: "needle", recursively: true) {
    needle.eulerAngles.y = oasisBearingRadians
}

// Detector gauge (0...1 signal)
if let gauge = detector.childNode(withName: "gauge_needle", recursively: true) {
    gauge.eulerAngles.z = signal * (.pi / 2)
}
```

**Suggested unlock order in game code (not part of the asset job):**
1. Bucket (always available at camp)
2. Water compass (reward for helping an NPC / first oasis return)
3. Water detector (later / farther oases)

**Minimum set to ship the new loop:** `prop_bucket` + `prop_water_barrel` + one of
`prop_water_compass` or `prop_water_detector`.
