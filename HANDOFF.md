# Desert Oasis — C++ Performance Handoff

## Context

This is an iOS 26 SwiftUI + SceneKit voxel-desert survival game.  
A previous session added C++ for the hot paths: world generation and mesh building.  
This document describes exactly what was done, what is still incomplete, and what to do next.

---

## Architecture overview

| Layer | Language | Role |
|---|---|---|
| UI / game logic | Swift | SwiftUI views, SceneKit node management, game state |
| Simulation hot paths | Swift + Accelerate (vDSP) | Water wave simulation (`OasisWaterNode`) |
| World gen + meshing | C++ (`VoxelCore.cpp`) | Noise, chunk filling, face-culled mesh building |
| Swift ↔ C++ bridge | `DesertOasis-Bridging-Header.h` | Imports `VoxelCore.hpp` with `extern "C"` declarations |

The project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16), so any new `.cpp` file
placed inside `DesertOasis/` is compiled automatically — no manual "Add to target" step.

---

## What is DONE ✅

### 1. `OasisWaterNode.swift` — complete rewrite
- Grid is now **voxel-aligned**: `cellSize = VoxelMetrics.blockSize = 0.5 m`  
  Each sim cell corresponds to one voxel block column.
- Wave equation runs via **Accelerate vDSP** (zero heap allocation per frame).
  Key functions: `vDSP_vadd`, `vDSP_vsma`, `vDSP_vsmul`, `vDSP_vclip`, `vDSP_vmul`.
- `lapBuf: ContiguousArray<Float>` pre-allocated once in `init` and reused every frame.
- Mesh is now **flat per-cell quads** (blocky voxel-water look) instead of a smooth triangulated
  mesh. Each cell emits one top-face quad at its wave height.
- Public interface unchanged: `init(radius:)`, `contains(worldPosition:)`,
  `setDepleted(_:)`, `update(deltaTime:playerWorldPosition:playerSpeed:)`.
- `DesertScene.swift` call site updated: `OasisWaterNode(radius: oasis.radius)` (removed `resolution:` param).

### 2. `VoxelCore.hpp` — C interface header
Path: `DesertOasis/Game/Voxel/VoxelCore.hpp`

```c
// Three extern "C" functions exposed to Swift:
int32_t voxel_gen_column_height(bx, bz, seed, total_size, block_size, height_scale, base_height);
void    voxel_gen_chunk(out_blocks, cx, cz, seed, block_size, total_size,
                        height_scale, base_height,
                        camp_wx, camp_wz, camp_wr, camp_pad_h, camp_count);
int32_t voxel_mesh_build(padded_blocks, block_size,
                         out_vertices, out_normals, out_colors, out_indices,
                         out_vertex_count, out_index_count);
void    voxel_mesh_free(vertices, normals, colors, indices);
```

### 3. `VoxelCore.cpp` — C++ implementation
Path: `DesertOasis/Game/Voxel/VoxelCore.cpp`

Contains:
- **Noise**: `noise_hash`, `value_noise`, `fbm` — exact port of the old Swift `VoxelNoise` enum.
- **`voxel_gen_column_height`**: same formula as the old Swift `columnHeight(bx:bz:totalSize:)`.
- **`voxel_gen_chunk`**: fills a 16×48×16 `uint8_t` block array (index = `lx + 16*(lz+16*ly)`)
  with the same sand/sandstone/rock layering + camp-pad blending as the old Swift version.
- **`voxel_mesh_build`**: takes an 18×48×18 padded block array (1-block border from neighbours),
  does per-block face culling (water/leaf/solid rules matching `VoxelMesher.swift`),
  writes `float[vc*3]` vertex, normal, RGBA colour arrays + `int32_t[]` index array.
  Uses `std::vector` internally, copies to `new[]` heap arrays returned to Swift.
- **`voxel_mesh_free`**: `delete[]` all four returned arrays.
- Block colour table matches `VoxelType.swift`'s `.color` property for all 15 types.

### 4. `DesertOasis-Bridging-Header.h`
Path: `DesertOasis/DesertOasis-Bridging-Header.h`

```objc
#import "Game/Voxel/VoxelCore.hpp"
```

### 5. `VoxelWorldGenerator.swift` — partial update
- `VoxelNoise` enum **removed** (was lines 6–36; noise now lives in C++).
- `columnHeight(bx:bz:totalSize:)` now calls `voxel_gen_column_height(...)`.
- `padHeight(for:totalSize:)` and `campPadHeight(totalSize:)` unchanged (they call `columnHeight`).
- ⚠️ **`generateChunk(into:cx:cz:)` still uses old Swift loops** — see TODO below.

---

## What is NOT DONE ❌

### Step 1 — One manual Xcode step (REQUIRED before building)

The bridging header path must be registered in build settings.  
**Do this once in Xcode:**

1. Click the project in the navigator → select the **DesertOasis** target → **Build Settings**.
2. Search for **"Objective-C Bridging Header"**.
3. Set the value to: `DesertOasis/DesertOasis-Bridging-Header.h`  
   (for both Debug and Release).
4. Build once to confirm no errors.

After this step Swift can call `voxel_gen_column_height`, `voxel_gen_chunk`,
`voxel_mesh_build`, and `voxel_mesh_free` directly.

---

### Step 2 — Replace `generateChunk` in `VoxelWorldGenerator.swift`

Replace the entire body of `generateChunk(into:cx:cz:)` with a C++ call.
The new implementation must:
1. Precompute pad heights (Swift, reuse existing `padHeight()` calls).
2. Pack camp site data into flat `[Float]` and `[Int32]` arrays.
3. Call `voxel_gen_chunk(...)` to fill a `[UInt8](count: 16*48*16)`.
4. Write the result into the `VoxelChunk` via a new bulk-load method (see Step 3).

**Replacement code for `generateChunk`:**

```swift
func generateChunk(into world: VoxelWorld, cx: Int, cz: Int) {
    guard let chunk = world.chunk(cx: cx, cz: cz, create: true) else { return }
    let totalSize = world.totalSize
    let bs        = world.blockSize

    // Precompute pad heights in Swift (calls C++ columnHeight internally)
    let wx  = campSites.map { $0.worldX }
    let wz  = campSites.map { $0.worldZ }
    let wr  = campSites.map { $0.padRadius }
    let phs = campSites.map { Int32(padHeight(for: $0, totalSize: totalSize)) }

    var raw = [UInt8](repeating: 0, count: VoxelChunk.volume)

    wx.withUnsafeBufferPointer  { wxBuf in
    wz.withUnsafeBufferPointer  { wzBuf in
    wr.withUnsafeBufferPointer  { wrBuf in
    phs.withUnsafeBufferPointer { phBuf in
    raw.withUnsafeMutableBufferPointer { rBuf in
        voxel_gen_chunk(
            rBuf.baseAddress!,
            Int32(cx), Int32(cz),
            seed, bs, totalSize,
            Int32(heightScale), Int32(baseHeight),
            wxBuf.baseAddress!, wzBuf.baseAddress!,
            wrBuf.baseAddress!, phBuf.baseAddress!,
            Int32(campSites.count)
        )
    }}}}}

    chunk.loadBlocks(from: raw)
}
```

---

### Step 3 — Add `loadBlocks(from:)` to `VoxelChunk.swift`

Add this method to the `VoxelChunk` class (after the existing `fillColumn` method):

```swift
/// Bulk-replaces all block data from a raw array produced by C++ voxel_gen_chunk.
/// Layout must match VoxelChunk's internal index: lx + sizeX*(lz + sizeZ*ly).
func loadBlocks(from raw: [UInt8]) {
    precondition(raw.count == Self.volume)
    blocks = raw
    isDirty = true
}
```

---

### Step 4 — Replace `VoxelMesher.swift`

Replace the **entire file** with this thin Swift wrapper around `voxel_mesh_build`:

```swift
import SceneKit
import UIKit

enum VoxelMesher {

    static func mesh(chunk: VoxelChunk, world: VoxelWorld) -> SCNGeometry? {
        let bs = world.blockSize
        let (baseBX, baseBZ) = world.chunkOriginBlock(cx: chunk.cx, cz: chunk.cz)

        // Build 18×48×18 padded block array.
        // Layout: pi = (lx+1) + 18*((lz+1) + 18*ly)  for lx,lz ∈ [-1..16], ly ∈ [0..47]
        var padded = [UInt8](repeating: 0, count: 18 * 48 * 18)
        for ly in 0..<48 {
            for lz in -1...16 {
                for lx in -1...16 {
                    let pi = (lx+1) + 18 * ((lz+1) + 18*ly)
                    let t: VoxelType = chunk.inBounds(lx: lx, ly: ly, lz: lz)
                        ? chunk.block(lx: lx, ly: ly, lz: lz)
                        : world.block(at: baseBX+lx, by: ly, bz: baseBZ+lz)
                    padded[pi] = t.rawValue
                }
            }
        }

        var outV: UnsafeMutablePointer<Float>?   = nil
        var outN: UnsafeMutablePointer<Float>?   = nil
        var outC: UnsafeMutablePointer<Float>?   = nil
        var outI: UnsafeMutablePointer<Int32>?   = nil
        var vc: Int32 = 0, ic: Int32 = 0

        let count = voxel_mesh_build(padded, bs, &outV, &outN, &outC, &outI, &vc, &ic)
        guard count > 0,
              let vp = outV, let np = outN, let cp = outC, let ip = outI else { return nil }
        defer { voxel_mesh_free(outV, outN, outC, outI) }

        let vcI = Int(vc), icI = Int(ic)

        let vSrc = SCNGeometrySource(
            data: Data(bytes: vp, count: vcI * 12), semantic: .vertex,
            vectorCount: vcI, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)

        let nSrc = SCNGeometrySource(
            data: Data(bytes: np, count: vcI * 12), semantic: .normal,
            vectorCount: vcI, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)

        let cSrc = SCNGeometrySource(
            data: Data(bytes: cp, count: vcI * 16), semantic: .color,
            vectorCount: vcI, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)

        let elem = SCNGeometryElement(
            data: Data(bytes: ip, count: icI * 4),
            primitiveType: .triangles, primitiveCount: icI / 3, bytesPerIndex: 4)

        let geo = SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])
        let mat = SCNMaterial()
        mat.lightingModel    = .lambert
        mat.diffuse.contents = UIColor.white
        mat.isDoubleSided    = false
        mat.transparencyMode = .aOne
        mat.blendMode        = .alpha
        geo.firstMaterial    = mat
        return geo
    }
}
```

---

## Verification checklist

After completing all steps:

- [ ] Project builds with no errors (Swift sees C++ functions via bridging header).
- [ ] World generates correctly — same sand/sandstone/rock terrain as before.
- [ ] Camp pads are still flat (blending logic matches old Swift version).
- [ ] Chunk meshes render — same visual output as old mesher.
- [ ] Water oases render with blocky voxel-tile surface + ripple animation.
- [ ] Player can walk into water, trigger splash and footstep ripples.

---

## Key files summary

| File | Status | Notes |
|---|---|---|
| `Game/Desert/OasisWaterNode.swift` | ✅ Done | vDSP wave sim, voxel-aligned grid |
| `Game/Voxel/VoxelCore.hpp` | ✅ Done | C interface for Swift |
| `Game/Voxel/VoxelCore.cpp` | ✅ Done | C++ noise + generator + mesher |
| `DesertOasis-Bridging-Header.h` | ✅ Done | Imports VoxelCore.hpp |
| `Game/Voxel/VoxelWorldGenerator.swift` | ⚠️ Partial | `columnHeight` done; `generateChunk` still Swift |
| `Game/Voxel/VoxelChunk.swift` | ❌ Pending | Add `loadBlocks(from:)` |
| `Game/Voxel/VoxelMesher.swift` | ❌ Pending | Full rewrite (code above) |
| Xcode Build Settings | ❌ Pending | Set `SWIFT_OBJC_BRIDGING_HEADER` manually |

---

## What NOT to port (not bottlenecks)

- `VoxelCharacterBuilder.swift` — called once per character spawn, negligible cost
- `VoxelAnimalBuilder.swift` — same
- `VoxelPropBuilder.swift` — called once at world build, not per-frame
- `VoxelSculpture.swift` — helper for prop geometry, used at build time only
