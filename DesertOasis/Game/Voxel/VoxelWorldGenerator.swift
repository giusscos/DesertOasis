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
    /// Dune amplitude in blocks (meters / blockSize).
    let heightScale: Int
    /// Flat-ish desert floor height in blocks.
    let baseHeight: Int
    /// Camp pad radius in blocks.
    let campRadius: Int

    /// Physical heights kept from the 1 m block era; converted using the world's block size.
    init(seed: UInt64,
         heightScaleMeters: Float = 8,
         baseHeightMeters: Float = 6,
         campRadiusMeters: Float = 12,
         blockSize: Float = VoxelMetrics.blockSize) {
        self.seed = seed
        self.heightScale = max(2, Int((heightScaleMeters / blockSize).rounded()))
        self.baseHeight = max(2, Int((baseHeightMeters / blockSize).rounded()))
        self.campRadius = max(4, Int((campRadiusMeters / blockSize).rounded()))
    }

    /// Approximate world-meter height of the flat camp pad top face.
    var campSurfaceMeters: Float {
        Float(campPadHeight(totalSize: VoxelMetrics.worldSizeMeters)) * VoxelMetrics.blockSize
    }

    func columnHeight(bx: Int, bz: Int, totalSize: Float) -> Int {
        let nx = Float(bx) / totalSize * 4.0 * VoxelMetrics.blockSize
        let nz = Float(bz) / totalSize * 4.0 * VoxelMetrics.blockSize
        let h = VoxelNoise.fbm(nx, nz, seed: seed) * Float(heightScale) + Float(baseHeight)
        return max(2, min(VoxelChunk.sizeY - 2, Int(h.rounded())))
    }

    /// Pad height from nearby natural rim/center samples so camp sits with the desert,
    /// not carved down to a fixed floor with dune walls around it.
    func campPadHeight(totalSize: Float) -> Int {
        var sum = 0
        var count = 0
        let r = Float(campRadius)
        let steps = max(8, campRadius)
        for i in 0..<steps {
            let angle = Float(i) / Float(steps) * Float.pi * 2
            let bx = Int((cos(angle) * r).rounded())
            let bz = Int((sin(angle) * r).rounded())
            sum += columnHeight(bx: bx, bz: bz, totalSize: totalSize)
            count += 1
        }
        sum += columnHeight(bx: 0, bz: 0, totalSize: totalSize)
        count += 1
        return max(2, min(VoxelChunk.sizeY - 2, sum / count))
    }

    /// Fills a single chunk column (terrain only — no oasis carving).
    func generateChunk(into world: VoxelWorld, cx: Int, cz: Int) {
        let half = world.halfExtent
        let totalSize = world.totalSize
        let bs = world.blockSize
        guard let chunk = world.chunk(cx: cx, cz: cz, create: true) else { return }
        let baseBX = cx * VoxelChunk.sizeX - half
        let baseBZ = cz * VoxelChunk.sizeZ - half
        let sandDepth = max(1, Int((2.0 / bs).rounded()))
        let sandstoneDepth = max(1, Int((3.0 / bs).rounded()))
        let padH = campPadHeight(totalSize: totalSize)
        let campR = Float(campRadius)
        // Soft ramp (~6 m) so dunes ease into the pad instead of forming cliffs.
        let blend = Float(max(4, Int((6.0 / bs).rounded())))

        for lz in 0..<VoxelChunk.sizeZ {
            for lx in 0..<VoxelChunk.sizeX {
                let bx = baseBX + lx
                let bz = baseBZ + lz
                let distCamp = sqrt(Float(bx * bx + bz * bz))
                var h = columnHeight(bx: bx, bz: bz, totalSize: totalSize)
                if distCamp <= campR {
                    h = padH
                } else if distCamp < campR + blend {
                    let t = (distCamp - campR) / blend
                    let s = t * t * (3 - 2 * t)
                    h = max(2, min(VoxelChunk.sizeY - 2,
                                   Int((Float(padH) * (1 - s) + Float(h) * s).rounded())))
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

    /// Places and carves oases into an already-filled world. Marks carved chunks dirty.
    @discardableResult
    func placeAndCarveOases(into world: VoxelWorld, oasisCount: Int = 6) -> [OasisInfo] {
        var oases = placeOases(world: world, count: oasisCount)
        for i in oases.indices {
            carveOasis(world: world, oasis: &oases[i])
        }
        return oases
    }

    /// Fills the world, flattens camp, carves oases (synchronous, full world).
    @discardableResult
    func generate(into world: VoxelWorld, oasisCount: Int = 6) -> [OasisInfo] {
        for cz in 0..<world.chunksZ {
            for cx in 0..<world.chunksX {
                generateChunk(into: world, cx: cx, cz: cz)
            }
        }
        return placeAndCarveOases(into: world, oasisCount: oasisCount)
    }

    private func placeOases(world: VoxelWorld, count: Int) -> [OasisInfo] {
        var oases: [OasisInfo] = []
        var rng = SeededRandom(seed: seed &+ 42)
        let bs = world.blockSize
        let minCampDistBlocks = 55 / bs
        let minOasisSepBlocks = 60 / bs

        for _ in 0..<count {
            var attempts = 0
            while attempts < 50 {
                let bx = Int(rng.nextFloat() * Float(world.halfExtent * 2)) - world.halfExtent
                let bz = Int(rng.nextFloat() * Float(world.halfExtent * 2)) - world.halfExtent
                let distFromCamp = sqrt(Float(bx * bx + bz * bz))
                let h = columnHeight(bx: bx, bz: bz, totalSize: world.totalSize)
                if h < baseHeight + max(2, heightScale / 2), distFromCamp > minCampDistBlocks {
                    let tooClose = oases.contains {
                        let ox = Int(floor($0.position.x / bs))
                        let oz = Int(floor($0.position.z / bs))
                        let dx = Float(ox - bx)
                        let dz = Float(oz - bz)
                        return sqrt(dx * dx + dz * dz) < minOasisSepBlocks
                    }
                    if !tooClose {
                        let radius = 6 + rng.nextFloat() * 8 // meters
                        oases.append(OasisInfo(
                            position: SCNVector3(
                                (Float(bx) + 0.5) * bs,
                                Float(h) * bs,
                                (Float(bz) + 0.5) * bs
                            ),
                            radius: radius
                        ))
                        break
                    }
                }
                attempts += 1
            }
        }
        return oases
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
