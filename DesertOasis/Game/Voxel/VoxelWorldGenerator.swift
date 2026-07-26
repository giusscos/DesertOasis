import SceneKit
import Foundation

// MARK: - Generator
// Noise and chunk generation are handled by VoxelCore.cpp (C++) via the bridging header.

struct VoxelWorldGenerator {
    let seed: UInt64
    let heightScale: Int
    let baseHeight: Int
    let campRadius: Int
    /// All known camp pads (home + remote). Flattened during chunk gen.
    var campSites: [CampSite]

    init(seed: UInt64,
         heightScaleMeters: Float = 8,
         baseHeightMeters: Float = 6,
         campRadiusMeters: Float = 12,
         blockSize: Float = VoxelMetrics.blockSize,
         campSites: [CampSite] = []) {
        self.seed = seed
        self.heightScale = max(2, Int((heightScaleMeters / blockSize).rounded()))
        self.baseHeight = max(2, Int((baseHeightMeters / blockSize).rounded()))
        self.campRadius = max(4, Int((campRadiusMeters / blockSize).rounded()))
        self.campSites = campSites.isEmpty
            ? CampSiteGenerator.sites(seed: seed)
            : campSites
    }

    var campSurfaceMeters: Float {
        Float(padHeight(for: campSites.first ?? CampSite(
            id: "home", worldX: 0, worldZ: 0, isHome: true, padRadius: 18
        ), totalSize: VoxelMetrics.worldSizeMeters)) * VoxelMetrics.blockSize
    }

    func columnHeight(bx: Int, bz: Int, totalSize: Float) -> Int {
        Int(voxel_gen_column_height(
            Int32(bx), Int32(bz),
            seed,
            totalSize, VoxelMetrics.blockSize,
            Int32(heightScale), Int32(baseHeight)
        ))
    }

    func padHeight(for site: CampSite, totalSize: Float) -> Int {
        // Use only the center column so the pad sits at the natural ground level rather
        // than an averaged perimeter height that can create an elevated plateau.
        let cx = site.worldX / VoxelMetrics.blockSize
        let cz = site.worldZ / VoxelMetrics.blockSize
        return max(2, min(VoxelChunk.sizeY - 2,
            columnHeight(bx: Int(cx.rounded()), bz: Int(cz.rounded()), totalSize: totalSize)
        ))
    }

    /// Legacy single-camp pad height (home).
    func campPadHeight(totalSize: Float) -> Int {
        if let home = campSites.first(where: { $0.isHome }) {
            return padHeight(for: home, totalSize: totalSize)
        }
        return padHeight(for: CampSite(id: "home", worldX: 0, worldZ: 0, isHome: true, padRadius: 18),
                         totalSize: totalSize)
    }

    /// Pure terrain fill — safe to call off the main thread (no SceneKit / world mutation).
    func makeChunkBlocks(cx: Int, cz: Int, totalSize: Float, blockSize: Float) -> [UInt8] {
        let wx  = campSites.map { $0.worldX }
        let wz  = campSites.map { $0.worldZ }
        let wr  = campSites.map { $0.padRadius }
        let phs = campSites.map { Int32(padHeight(for: $0, totalSize: totalSize)) }

        var raw = [UInt8](repeating: 0, count: VoxelChunk.volume)
        raw.withUnsafeMutableBufferPointer { rBuf in
            guard let outBlocks = rBuf.baseAddress else { return }
            if campSites.isEmpty {
                voxel_gen_chunk(
                    outBlocks,
                    Int32(cx), Int32(cz),
                    seed, blockSize, totalSize,
                    Int32(heightScale), Int32(baseHeight),
                    nil, nil, nil, nil,
                    0
                )
            } else {
                wx.withUnsafeBufferPointer  { wxBuf in
                wz.withUnsafeBufferPointer  { wzBuf in
                wr.withUnsafeBufferPointer  { wrBuf in
                phs.withUnsafeBufferPointer { phBuf in
                    guard let campWX = wxBuf.baseAddress,
                          let campWZ = wzBuf.baseAddress,
                          let campWR = wrBuf.baseAddress,
                          let campPH = phBuf.baseAddress else { return }
                    voxel_gen_chunk(
                        outBlocks,
                        Int32(cx), Int32(cz),
                        seed, blockSize, totalSize,
                        Int32(heightScale), Int32(baseHeight),
                        campWX, campWZ, campWR, campPH,
                        Int32(campSites.count)
                    )
                }}}}
            }
        }
        return raw
    }

    func generateChunk(into world: VoxelWorld, cx: Int, cz: Int) {
        guard let chunk = world.chunk(cx: cx, cz: cz, create: true) else { return }
        let raw = makeChunkBlocks(
            cx: cx, cz: cz,
            totalSize: world.totalSize,
            blockSize: world.blockSize
        )
        chunk.loadBlocks(from: raw)
    }

    /// Places oases near camps and in the wilderness around a loaded region.
    @discardableResult
    func placeAndCarveOases(into world: VoxelWorld,
                            nearSites: [CampSite],
                            oasisCount: Int = 8) -> [OasisInfo] {
        var oases = placeOases(world: world, nearSites: nearSites, count: oasisCount)
        for i in oases.indices {
            carveOasis(world: world, oasis: &oases[i])
        }
        return oases
    }

    @discardableResult
    func placeAndCarveOases(into world: VoxelWorld, oasisCount: Int = 8) -> [OasisInfo] {
        placeAndCarveOases(into: world, nearSites: Array(campSites.prefix(5)), oasisCount: oasisCount)
    }

    @discardableResult
    func generate(into world: VoxelWorld, oasisCount: Int = 8) -> [OasisInfo] {
        let coords = world.chunkCoordinatesFromCenter(radiusChunks: 10)
        for c in coords {
            generateChunk(into: world, cx: c.cx, cz: c.cz)
        }
        return placeAndCarveOases(into: world, oasisCount: oasisCount)
    }

    private func placeOases(world: VoxelWorld, nearSites: [CampSite], count: Int) -> [OasisInfo] {
        var oases: [OasisInfo] = []
        var rng = SeededRandom(seed: seed &+ 42 &+ UInt64(nearSites.count) &* 17)
        let bs = world.blockSize
        let minOasisSep = 40 / bs

        let home = nearSites.first(where: \.isHome)
        let remotes = nearSites.filter { !$0.isHome }

        // Remote-camp discovery: one harder-to-spot oasis — not hugging the pad.
        if home == nil, let remote = remotes.first, remotes.count == 1, count <= 2 {
            // ~55% chance — finding water near a new camp is a reward, not a guarantee.
            if rng.nextFloat() < 0.55,
               let oasis = tryPlaceOasis(
                   world: world, rng: &rng,
                   aroundX: remote.worldX, aroundZ: remote.worldZ,
                   minDistFromPoint: 72, maxDistFromPoint: 135,
                   existing: oases, minSepBlocks: minOasisSep
               ) {
                oases.append(oasis)
            }
            return oases
        }

        let hx = home?.worldX ?? 0
        let hz = home?.worldZ ?? 0

        // Starter oasis: findable on a short trek, not sitting on camp's doorstep.
        if count > 0, home != nil, let starter = tryPlaceOasis(
            world: world, rng: &rng,
            aroundX: hx, aroundZ: hz,
            minDistFromPoint: 48, maxDistFromPoint: 72,
            existing: oases, minSepBlocks: minOasisSep
        ) {
            oases.append(starter)
        }

        // Occasional oasis near remotes only when those chunks exist (usually deferred to discovery).
        for site in remotes {
            if oases.count >= count { break }
            // Less common / farther out — search challenge around way camps.
            guard rng.nextFloat() < 0.4 else { continue }
            if let oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: site.worldX, aroundZ: site.worldZ,
                minDistFromPoint: 72, maxDistFromPoint: 130,
                existing: oases, minSepBlocks: minOasisSep
            ) {
                oases.append(oasis)
            }
        }

        // Remaining wild oases around home — exploration rewards within the initial ring.
        var attempts = 0
        while oases.count < count && attempts < 90 {
            attempts += 1
            if let oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: hx, aroundZ: hz,
                minDistFromPoint: 78, maxDistFromPoint: 118,
                existing: oases, minSepBlocks: minOasisSep
            ) {
                oases.append(oasis)
            }
        }
        return oases
    }

    /// Place a single challenging oasis near a remote camp (used on discovery).
    /// Ensures terrain exists under the candidate before carving.
    func placeAndCarveRemoteCampOasis(into world: VoxelWorld, site: CampSite) -> OasisInfo? {
        var rng = SeededRandom(seed: seed &+ 42 &+ Self.stableHash(site.id))
        guard rng.nextFloat() < 0.55 else { return nil }

        let bs = world.blockSize
        let minOasisSep = 40 / bs
        // Prefer a few candidate distances; generate chunks around each try.
        for _ in 0..<16 {
            let angle = rng.nextFloat() * Float.pi * 2
            let dist = 72 + rng.nextFloat() * 63 // 72…135 m
            let wx = site.worldX + cos(angle) * dist
            let wz = site.worldZ + sin(angle) * dist
            let bx = Int(floor(wx / bs))
            let bz = Int(floor(wz / bs))
            // Pool carve needs neighbours — generate a local ring first.
            ensureGeneratedChunks(world: world, centerBX: bx, centerBZ: bz, radiusBlocks: 14)
            guard var oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: site.worldX, aroundZ: site.worldZ,
                minDistFromPoint: 72, maxDistFromPoint: 135,
                existing: [], minSepBlocks: minOasisSep,
                forcedAngle: angle, forcedDist: dist
            ) else { continue }
            carveOasis(world: world, oasis: &oasis)
            return oasis
        }
        return nil
    }

    /// Rare wild oasis while streaming far from home — keeps exploration rewarding.
    func placeAndCarveStreamOasis(
        into world: VoxelWorld,
        aroundX: Float,
        aroundZ: Float,
        existing: [OasisInfo]
    ) -> OasisInfo? {
        let distHome = sqrt(aroundX * aroundX + aroundZ * aroundZ)
        guard distHome > 130 else { return nil }

        var rng = SeededRandom(
            seed: seed &+ 88_021
                &+ UInt64(aroundX.bitPattern)
                &+ UInt64(aroundZ.bitPattern) &* 17
        )
        // Low chance per call — DesertScene gates by chunk hash too.
        guard rng.nextFloat() < 0.85 else { return nil }

        let bs = world.blockSize
        let minOasisSep = 55 / bs
        let tooCloseCamp = campSites.contains {
            let dx = aroundX - $0.worldX
            let dz = aroundZ - $0.worldZ
            return dx * dx + dz * dz < 90 * 90
        }
        if tooCloseCamp { return nil }

        let tooCloseOasis = existing.contains {
            let dx = aroundX - $0.position.x
            let dz = aroundZ - $0.position.z
            return dx * dx + dz * dz < 70 * 70
        }
        if tooCloseOasis { return nil }

        let bx = Int(floor(aroundX / bs))
        let bz = Int(floor(aroundZ / bs))
        ensureGeneratedChunks(world: world, centerBX: bx, centerBZ: bz, radiusBlocks: 12)
        guard var oasis = tryPlaceOasis(
            world: world, rng: &rng,
            aroundX: aroundX, aroundZ: aroundZ,
            minDistFromPoint: 0, maxDistFromPoint: 6,
            existing: existing, minSepBlocks: minOasisSep
        ) else { return nil }
        carveOasis(world: world, oasis: &oasis)
        return oasis
    }

    private static func stableHash(_ id: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in id.utf8 {
            h ^= UInt64(b)
            h = h &* 0x1000_0000_01b3
        }
        return h
    }

    private func tryPlaceOasis(world: VoxelWorld,
                               rng: inout SeededRandom,
                               aroundX: Float,
                               aroundZ: Float,
                               minDistFromPoint: Float,
                               maxDistFromPoint: Float,
                               existing: [OasisInfo],
                               minSepBlocks: Float,
                               forcedAngle: Float? = nil,
                               forcedDist: Float? = nil) -> OasisInfo? {
        let bs = world.blockSize
        let attempts = forcedAngle != nil ? 1 : 12
        for _ in 0..<attempts {
            let angle = forcedAngle ?? (rng.nextFloat() * Float.pi * 2)
            let dist = forcedDist ?? (minDistFromPoint + rng.nextFloat() * (maxDistFromPoint - minDistFromPoint))
            let wx = aroundX + cos(angle) * dist
            let wz = aroundZ + sin(angle) * dist
            let bx = Int(floor(wx / bs))
            let bz = Int(floor(wz / bs))
            let (ocx, ocz) = world.chunkCoord(blockX: bx, blockZ: bz)
            // Only place on generated terrain — noise fallback would carve into empty stubs.
            guard world.hasGeneratedChunk(cx: ocx, cz: ocz) else { continue }

            // Read the actual terrain height from loaded chunks (includes blend-zone edits).
            let actualSurfY = world.solidSurfaceY(atWorldX: wx, worldZ: wz)
            let h = Int(actualSurfY / bs)
            guard h < baseHeight + max(2, heightScale / 2) else { continue }

            // Keep clear of camp pads
            let onPad = campSites.contains {
                let dx = wx - $0.worldX
                let dz = wz - $0.worldZ
                return dx * dx + dz * dz < ($0.padRadius + 4) * ($0.padRadius + 4)
            }
            if onPad { continue }

            let tooClose = existing.contains {
                let ox = Int(floor($0.position.x / bs))
                let oz = Int(floor($0.position.z / bs))
                let dx = Float(ox - bx)
                let dz = Float(oz - bz)
                return sqrt(dx * dx + dz * dz) < minSepBlocks
            }
            if tooClose { continue }

            let radius = 2.4 + rng.nextFloat() * 2.0
            var oasis = OasisInfo(
                position: SCNVector3((Float(bx) + 0.5) * bs, actualSurfY, (Float(bz) + 0.5) * bs),
                radius: radius
            )
            // ~22% of oases become landmarks (slightly rarer — more of a find)
            if rng.nextFloat() < 0.22 {
                let kinds = LandmarkKind.allCases
                let idx = Int(rng.nextFloat() * Float(kinds.count)) % kinds.count
                oasis.landmark = kinds[idx]
            }
            return oasis
        }
        return nil
    }

    /// Make sure every chunk the carve AABB touches has real terrain (not an air stub).
    private func ensureGeneratedChunks(world: VoxelWorld, centerBX: Int, centerBZ: Int, radiusBlocks: Int) {
        let minBX = centerBX - radiusBlocks
        let maxBX = centerBX + radiusBlocks
        let minBZ = centerBZ - radiusBlocks
        let maxBZ = centerBZ + radiusBlocks
        let (minCX, minCZ) = world.chunkCoord(blockX: minBX, blockZ: minBZ)
        let (maxCX, maxCZ) = world.chunkCoord(blockX: maxBX, blockZ: maxBZ)
        for cz in minCZ...maxCZ {
            for cx in minCX...maxCX {
                if world.hasGeneratedChunk(cx: cx, cz: cz) { continue }
                generateChunk(into: world, cx: cx, cz: cz)
            }
        }
    }

    private func carveOasis(world: VoxelWorld, oasis: inout OasisInfo) {
        let bs = world.blockSize
        let cx = Int(floor(oasis.position.x / bs))
        let cz = Int(floor(oasis.position.z / bs))
        let poolR = max(oasis.radius, 2.0)
        let r = Int(ceil(poolR / bs)) + 2 // include sand rim
        let waterLevel = max(3, Int(floor(oasis.position.y / bs)) - 1)
        // Dig a sand bowl under a single flat water plane (no stepped shelves).
        let bowlDepthBlocks = max(2, Int((3.0 / bs).rounded()))
        let rimOuter = poolR + bs * 1.6

        // Carve can spill across chunk borders. Generate real terrain first so setBlock
        // never allocates empty air stubs (those show up as rectangular voids).
        ensureGeneratedChunks(world: world, centerBX: cx, centerBZ: cz, radiusBlocks: r)

        for dz in -r...r {
            for dx in -r...r {
                let dist = sqrt(Float(dx * dx + dz * dz)) * bs
                let bx = cx + dx
                let bz = cz + dz
                // Actual block height — respects blend-zone terrain edits.
                let top = Int(world.solidSurfaceY(
                    atWorldX: (Float(bx) + 0.5) * bs,
                    worldZ:   (Float(bz) + 0.5) * bs
                ) / bs)

                if dist <= poolR {
                    let bowl = Int((1 - dist / poolR) * Float(bowlDepthBlocks)) + 1
                    let clearTo = max(top + 2, waterLevel + 2)
                    for by in max(0, waterLevel - bowl)...min(VoxelChunk.sizeY - 1, clearTo) {
                        if by > waterLevel {
                            world.setBlock(at: bx, by: by, bz: bz, type: .air)
                        } else if by == waterLevel {
                            world.setBlock(at: bx, by: by, bz: bz, type: .water)
                        } else if by == waterLevel - 1 {
                            world.setBlock(at: bx, by: by, bz: bz, type: .sand)
                        } else if by >= waterLevel - bowl {
                            // Fill bowl sides so the pool never opens into void under the water plane.
                            if world.block(at: bx, by: by, bz: bz) == .air {
                                world.setBlock(at: bx, by: by, bz: bz, type: .sand)
                            }
                        }
                    }
                } else if dist <= rimOuter {
                    // Sand bank around the pool — keep solid sand, flatten a bit
                    let padY = max(waterLevel, min(top, waterLevel + 1))
                    for by in 0...min(VoxelChunk.sizeY - 1, max(top, padY) + 1) {
                        if by < padY {
                            if world.block(at: bx, by: by, bz: bz) == .air {
                                world.setBlock(at: bx, by: by, bz: bz, type: .sand)
                            }
                        } else if by == padY {
                            world.setBlock(at: bx, by: by, bz: bz, type: .sand)
                        } else if by <= top + 1 {
                            world.setBlock(at: bx, by: by, bz: bz, type: .air)
                        }
                    }
                }
            }
        }

        oasis = OasisInfo(
            position: SCNVector3(oasis.position.x, Float(waterLevel + 1) * bs, oasis.position.z),
            radius: poolR,
            landmark: oasis.landmark
        )
    }
}
