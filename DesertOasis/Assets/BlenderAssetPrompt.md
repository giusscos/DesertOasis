# Desert Oasis – Blender Asset Prompt

Use these prompts in Claude Code (or another AI assistant with Blender/Python access)
to generate the 3D assets for the game. Each section is self-contained and can be
given as an independent prompt.

---

## 1. Player Characters

**Prompt:**

Create two low-poly Zelda-style humanoid characters in Blender using Python (bpy):

**Man character** (`player_man.blend` → export as `player_man.usdz`):
- Cel-shaded Zelda Wind Waker aesthetic. Total height ≈ 1.4 m.
- Desert explorer style: khaki/sand-coloured shirt, dark olive trousers, tan cowboy/desert hat.
- Simple face with large expressive eyes (no mouth detail).
- Rigged with a basic armature: root, hips, spine, chest, neck, head, shoulder_L/R, upperarm_L/R, forearm_L/R, hand_L/R, thigh_L/R, shin_L/R, foot_L/R.
- Include NLA actions: **idle** (standing, gentle breathing cycle, 60 frames), **walk** (standard walk cycle, 30 frames looping), **talk** (idle with occasional head nods, 90 frames), **wave** (one arm waving, 45 frames).
- Export as USDZ with embedded armature and animation clips.

**Woman character** (`player_woman.blend` → export as `player_woman.usdz`):
- Same rig and style as the man.
- Rose/terracotta tunic, violet trousers, straw sun hat with a ribbon.
- Slightly shorter and leaner proportions.
- Same NLA animation actions as the man.

**SceneKit integration:**
Load with `SCNScene(named: "player_man.usdz")` and find the root node.
To play an animation: `node.animationPlayer(forKey: "walk")?.play()`.

---

## 2. NPC Characters

**Prompt:**

Create 5 distinct low-poly NPC characters in the same Zelda Wind Waker style.
Each ≈ 1.2–1.5 m tall. Rig each with the same armature as the player.
Include actions: **idle** (30 frames), **talk** (60 frames), **gesture** (45 frames).

| File name | Description |
|---|---|
| `npc_wanderer.usdz` | Weathered desert wanderer, torn beige cloak, wild hair, exhausted posture |
| `npc_merchant.usdz` | Cheerful merchant, red vest over white shirt, fez hat, holds a small satchel |
| `npc_child.usdz` | Small frightened child (0.9 m), blue tunic, messy hair, teary eyes |
| `npc_elder.usdz` | Old sage, long white robe, tall walking staff, white beard, kind wrinkled face |
| `npc_lost.usdz` | Confused traveller, modern-ish khaki jacket (anachronistic for comedy), compass in hand |

Export each as USDZ with animations embedded.

---

## 3. Lobby Scene Props

**Prompt:**

Create the following props for a desert camping-tent interior lobby scene in Blender.
Style: slightly stylised/low-poly, warm and cosy. Export each as `.usdz`.

### 3a. Desert Tent (`lobby_tent.usdz`)
- A-frame canvas tent interior (no floor needed, just the shell).
- Canvas fabric material in khaki/sand with subtle wrinkle normals.
- Open front entrance (facing +Z).
- Tent poles in dark weathered wood.
- Inner dimensions: 8 m wide × 10 m deep × 4 m peak height.
- Include a hanging lantern at the apex, emitting warm orange glow (use an emissive material).
- A wooden sign plank above the entrance area, reading **"Desert Oasis"** in carved wooden letters (the text geometry should be a child node named `sign_text`).

### 3b. Desert Bed with Diaries (`lobby_bed.usdz`)
- Old-fashioned camp cot: wooden frame, off-white canvas mattress, small pillow.
- 3 leather-bound diaries resting on the mattress, closed.
  - Diary 1: Red leather cover, gold trim, name placeholder label.
  - Diary 2: Green leather cover, silver trim.
  - Diary 3: Blue leather cover, bronze trim.
  - Name each diary node: `diary_0`, `diary_1`, `diary_2` (used for tap detection).
- When a diary is opened (animation): pages fan out, spine bends slightly, 30-frame action named `open`.

### 3c. Camp Table with Instruments (`lobby_table.usdz`)
- Folding wooden camp table (1.6 m × 1.1 m surface, 0.9 m tall).
- Items on the table (each as a named child node):
  - Brass compass (`node_compass`): circular, ornate, needle pointing north.
  - Rolled parchment map (`node_map`): with faint hand-drawn desert routes.
  - Small oil lantern (`node_lantern`): emissive warm glow.
  - Inkwell and quill (`node_quill`).
  - Small hourglass (`node_hourglass`): sand flowing (looped particle or UV animation).

---

## 4. Desert Environment Props

**Prompt:**

Create the following tileable/scatter props for a procedural desert scene.
Style: low-poly, suitable for SceneKit. Export each as `.usdz`.

| File | Description |
|---|---|
| `prop_cactus_saguaro.usdz` | Classic tall saguaro cactus ≈ 2.5 m, two arms, ridged surface with spine normals |
| `prop_cactus_barrel.usdz` | Short barrel cactus ≈ 0.6 m, round, dense spines |
| `prop_rock_small.usdz` | Desert sandstone rock ≈ 0.3–0.6 m, slightly flattened |
| `prop_rock_cluster.usdz` | Group of 3–5 rocks, varying sizes, natural arrangement |
| `prop_palm_tree.usdz` | Desert palm ≈ 5 m, curved trunk, 8 drooping fronds, rigged trunk (gentle sway action) |
| `prop_dead_tree.usdz` | Bare bleached dead tree, no leaves, dramatic silhouette |
| `prop_oasis_water.usdz` | Flat animated water surface, 10 m diameter disc, blue ripple shader |
| `prop_tumbleweed.usdz` | Round tumbleweed with roll animation action (30 frames) |
| `prop_sand_dune.usdz` | Smooth dune mound ≈ 8 m wide × 2.5 m tall, sandy colour |

---

## 5. Integration Notes

After exporting from Blender:

1. Add each `.usdz` to the Xcode project under `DesertOasis/DesertOasis/Assets.xcassets` or directly in the project navigator.

2. **Load a static prop:**
```swift
let propScene = SCNScene(named: "prop_cactus_saguaro.usdz")!
let cactusNode = propScene.rootNode.childNodes.first!
cactusNode.position = SCNVector3(x, y, z)
parentNode.addChildNode(cactusNode)
```

3. **Load a character with animations:**
```swift
let charScene = SCNScene(named: "player_man.usdz")!
let character = charScene.rootNode.childNodes.first!
// Play walk animation
character.animationPlayer(forKey: "walk")?.play()
// Stop and switch to idle
character.animationPlayer(forKey: "walk")?.stop()
character.animationPlayer(forKey: "idle")?.play()
```

4. **Replace the code-generated `PlayerNode` and `NPCNode`:** Once assets are ready, update
   `PlayerNode.swift` to load from the USDZ instead of building geometry procedurally.
   The rest of the game code (physics, movement, dialogue) is asset-agnostic.

5. **Lobby scene swap:** Replace the `LobbyScene.buildScene()` procedural geometry calls with
   USDZ asset loads. Camera positions and animation targets stay the same — just remove the
   primitive-building helper methods.
