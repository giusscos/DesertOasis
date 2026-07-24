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
        var sum = 0
        var count = 0
        let r = site.padRadius / VoxelMetrics.blockSize
        let steps = max(8, Int(r))
        let cx = site.worldX / VoxelMetrics.blockSize
        let cz = site.worldZ / VoxelMetrics.blockSize
        for i in 0..<steps {
            let angle = Float(i) / Float(steps) * Float.pi * 2
            let bx = Int((cx + cos(angle) * r).rounded())
            let bz = Int((cz + sin(angle) * r).rounded())
            sum += columnHeight(bx: bx, bz: bz, totalSize: totalSize)
            count += 1
        }
        sum += columnHeight(bx: Int(cx.rounded()), bz: Int(cz.rounded()), totalSize: totalSize)
        count += 1
        return max(2, min(VoxelChunk.sizeY - 2, sum / count))
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
            let h = columnHeight(bx: bx, bz: bz, totalSize: world.totalSize)
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

            let radius = 2.0 + rng.nextFloat() * 1.8
            var oasis = OasisInfo(
                position: SCNVector3((Float(bx) + 0.5) * bs, Float(h) * bs, (Float(bz) + 0.5) * bs),
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

    private func carveOasis(world: VoxelWorld, oasis: inout OasisInfo) {
        let bs = world.blockSize
        let cx = Int(floor(oasis.position.x / bs))
        let cz = Int(floor(oasis.position.z / bs))
        let r = Int(ceil(oasis.radius / bs))
        let waterLevel = max(2, Int(floor(oasis.position.y / bs)) - 1)
        let bowlDepthBlocks = max(2, Int((3.0 / bs).rounded()))

        for dz in -r...r {
            for dx in -r...r {
                let dist = sqrt(Float(dx * dx + dz * dz)) * bs
                guard dist <= oasis.radius else { continue }
                let bx = cx + dx
                let bz = cz + dz
                let bowl = Int((1 - dist / oasis.radius) * Float(bowlDepthBlocks)) + 1
                let top = columnHeight(bx: bx, bz: bz, totalSize: world.totalSize)

                for by in max(0, waterLevel - bowl)...min(VoxelChunk.sizeY - 1, top + 2) {
                    if by > waterLevel {
                        world.setBlock(at: bx, by: by, bz: bz, type: .air)
                    } else if by == waterLevel {
                        world.setBlock(at: bx, by: by, bz: bz, type: .water)
                    } else if by == waterLevel - 1 {
                        world.setBlock(at: bx, by: by, bz: bz, type: .sand)
                    }
                }
            }
        }

        oasis = OasisInfo(
            position: SCNVector3(oasis.position.x, Float(waterLevel + 1) * bs, oasis.position.z),
            radius: oasis.radius
        )
    }
}
