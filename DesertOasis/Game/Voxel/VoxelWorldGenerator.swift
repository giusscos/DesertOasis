import SceneKit
import Foundation

// MARK: - Noise

enum VoxelNoise {
    static func hash(_ x: Int, _ y: Int, seed: UInt64) -> Float {
        var n = UInt64(bitPattern: Int64(x &* 1619 &+ y &* 31337)) &+ seed &* 1000003
        n = n ^ (n >> 16)
        n = n &* 0x45d9f3b
        n = n ^ (n >> 16)
        return Float(n & 0xFFFFFF) / Float(0xFFFFFF)
    }

    static func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    static func valueNoise(_ x: Float, _ y: Float, seed: UInt64) -> Float {
        let xi = Int(floor(x)); let xf = x - floor(x)
        let yi = Int(floor(y)); let yf = y - floor(y)
        let v00 = hash(xi,     yi,     seed: seed)
        let v10 = hash(xi + 1, yi,     seed: seed)
        let v01 = hash(xi,     yi + 1, seed: seed)
        let v11 = hash(xi + 1, yi + 1, seed: seed)
        let ux = smoothstep(xf); let uy = smoothstep(yf)
        return (v00 * (1 - ux) + v10 * ux) * (1 - uy) + (v01 * (1 - ux) + v11 * ux) * uy
    }

    static func fbm(_ x: Float, _ y: Float, seed: UInt64, octaves: Int = 5) -> Float {
        var value: Float = 0; var amplitude: Float = 0.5; var frequency: Float = 1.0
        for o in 0..<octaves {
            value += valueNoise(x * frequency, y * frequency, seed: seed &+ UInt64(o * 7919)) * amplitude
            amplitude *= 0.5; frequency *= 2.0
        }
        return value
    }
}

// MARK: - Generator

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
        let nx = Float(bx) / totalSize * 4.0 * VoxelMetrics.blockSize
        let nz = Float(bz) / totalSize * 4.0 * VoxelMetrics.blockSize
        let h = VoxelNoise.fbm(nx, nz, seed: seed) * Float(heightScale) + Float(baseHeight)
        return max(2, min(VoxelChunk.sizeY - 2, Int(h.rounded())))
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
        let totalSize = world.totalSize
        let bs = world.blockSize
        guard let chunk = world.chunk(cx: cx, cz: cz, create: true) else { return }
        let (baseBX, baseBZ) = world.chunkOriginBlock(cx: cx, cz: cz)
        let sandDepth = max(1, Int((2.0 / bs).rounded()))
        let sandstoneDepth = max(1, Int((3.0 / bs).rounded()))
        let blend = Float(max(4, Int((6.0 / bs).rounded())))

        // Precompute pad heights per site touching this chunk.
        let sitePads: [(CampSite, Int)] = campSites.map { ($0, padHeight(for: $0, totalSize: totalSize)) }

        for lz in 0..<VoxelChunk.sizeZ {
            for lx in 0..<VoxelChunk.sizeX {
                let bx = baseBX + lx
                let bz = baseBZ + lz
                var h = columnHeight(bx: bx, bz: bz, totalSize: totalSize)

                for (site, padH) in sitePads {
                    let siteBX = site.worldX / bs
                    let siteBZ = site.worldZ / bs
                    let dist = sqrt(
                        (Float(bx) - siteBX) * (Float(bx) - siteBX) +
                        (Float(bz) - siteBZ) * (Float(bz) - siteBZ)
                    )
                    let campR = site.padRadius / bs
                    if dist <= campR {
                        h = padH
                        break
                    } else if dist < campR + blend {
                        let t = (dist - campR) / blend
                        let s = t * t * (3 - 2 * t)
                        h = max(2, min(VoxelChunk.sizeY - 2,
                                       Int((Float(padH) * (1 - s) + Float(h) * s).rounded())))
                    }
                }

                for by in 0..<h {
                    let type: VoxelType
                    if by >= h - sandDepth {
                        type = .sand
                    } else if by >= h - sandDepth - sandstoneDepth {
                        type = .sandstone
                    } else {
                        type = .rock
                    }
                    chunk.setBlock(lx: lx, ly: by, lz: lz, type: type)
                }
            }
        }
    }

    /// Places oases near camps and in the wilderness around a loaded region.
    @discardableResult
    func placeAndCarveOases(into world: VoxelWorld,
                            nearSites: [CampSite],
                            oasisCount: Int = 6) -> [OasisInfo] {
        var oases = placeOases(world: world, nearSites: nearSites, count: oasisCount)
        for i in oases.indices {
            carveOasis(world: world, oasis: &oases[i])
        }
        return oases
    }

    @discardableResult
    func placeAndCarveOases(into world: VoxelWorld, oasisCount: Int = 6) -> [OasisInfo] {
        placeAndCarveOases(into: world, nearSites: Array(campSites.prefix(5)), oasisCount: oasisCount)
    }

    @discardableResult
    func generate(into world: VoxelWorld, oasisCount: Int = 6) -> [OasisInfo] {
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
        let minOasisSep = 45 / bs

        // One oasis near each remote-ish site, plus wild fills.
        for site in nearSites where !site.isHome {
            if oases.count >= count { break }
            if let oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: site.worldX, aroundZ: site.worldZ,
                minDistFromPoint: 18, maxDistFromPoint: 42,
                existing: oases, minSepBlocks: minOasisSep
            ) {
                oases.append(oasis)
            }
        }

        // Wild oases around home
        let home = nearSites.first(where: \.isHome) ?? nearSites.first
        let hx = home?.worldX ?? 0
        let hz = home?.worldZ ?? 0
        var attempts = 0
        while oases.count < count && attempts < 80 {
            attempts += 1
            if let oasis = tryPlaceOasis(
                world: world, rng: &rng,
                aroundX: hx, aroundZ: hz,
                minDistFromPoint: 55, maxDistFromPoint: 110,
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
            return OasisInfo(
                position: SCNVector3((Float(bx) + 0.5) * bs, Float(h) * bs, (Float(bz) + 0.5) * bs),
                radius: radius
            )
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
