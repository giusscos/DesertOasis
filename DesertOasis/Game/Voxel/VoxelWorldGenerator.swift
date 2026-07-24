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
        let minOasisSep = 36 / bs

        let home = nearSites.first(where: \.isHome) ?? nearSites.first
        let hx = home?.worldX ?? 0
        let hz = home?.worldZ ?? 0

        // One starter oasis: findable on a short trek, not sitting on camp's doorstep.
        if count > 0, let starter = tryPlaceOasis(
            world: world, rng: &rng,
            aroundX: hx, aroundZ: hz,
            minDistFromPoint: 38, maxDistFromPoint: 58,
            existing: oases, minSepBlocks: minOasisSep
        ) {
            oases.append(starter)
        }

        // One oasis near each remote camp (reward for reaching other sites).
        for site in nearSites where !site.isHome {
            if oases.count >= count { break }
            if let oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: site.worldX, aroundZ: site.worldZ,
                minDistFromPoint: 18, maxDistFromPoint: 40,
                existing: oases, minSepBlocks: minOasisSep
            ) {
                oases.append(oasis)
            }
        }

        // Remaining wild oases farther out — exploration rewards, not a carpet.
        var attempts = 0
        while oases.count < count && attempts < 90 {
            attempts += 1
            if let oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: hx, aroundZ: hz,
                minDistFromPoint: 60, maxDistFromPoint: 105,
                existing: oases, minSepBlocks: minOasisSep
            ) {
                oases.append(oasis)
            }
        }
        return oases
    }

    private func tryPlaceOasis(world: VoxelWorld,
                               rng: inout SeededRandom,
                               aroundX: Float,
                               aroundZ: Float,
                               minDistFromPoint: Float,
                               maxDistFromPoint: Float,
                               existing: [OasisInfo],
                               minSepBlocks: Float) -> OasisInfo? {
        let bs = world.blockSize
        for _ in 0..<12 {
            let angle = rng.nextFloat() * Float.pi * 2
            let dist = minDistFromPoint + rng.nextFloat() * (maxDistFromPoint - minDistFromPoint)
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
            // ~28% of oases become landmarks
            if rng.nextFloat() < 0.28 {
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
