import SceneKit

/// Metadata about a placed oasis (position and pool radius in world-space metres).
struct OasisInfo {
    var position: SCNVector3
    var radius: Float
}

/// Seeded location where a camp can exist in the infinite desert.
struct CampSite: Identifiable {
    let id: String
    let worldX: Float
    let worldZ: Float
    let isHome: Bool
    /// Flat pad radius in metres.
    let padRadius: Float

    var worldPosition: SIMD2<Float> { SIMD2(worldX, worldZ) }
}

/// Persisted per-camp water + oasis growth.
struct CampProgress: Codable, Identifiable, Equatable {
    var id: String
    var waterLevel: Float
    var oasisStage: Int
    var oasisProgress: Float

    init(id: String,
         waterLevel: Float = 0,
         oasisStage: Int = 0,
         oasisProgress: Float = 0) {
        self.id = id
        self.waterLevel = waterLevel
        self.oasisStage = oasisStage
        self.oasisProgress = oasisProgress
    }

    static func home(from slotLevel: Float) -> CampProgress {
        CampProgress(id: "home", waterLevel: slotLevel)
    }
}

/// Deterministic pseudo-random number generator (xorshift64) for world generation.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x853C_49E6_748F_EA9B : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Returns a uniform Float in [0, 1).
    mutating func nextFloat() -> Float {
        Float(nextUInt64() & 0x00FF_FFFF) / Float(0x01_0000_00)
    }
}

enum CampSiteGenerator {
    /// Home + rings of remote camps. Rings extend far so the desert feels endless.
    static func sites(seed: UInt64, rings: Int = 6) -> [CampSite] {
        var result: [CampSite] = [
            CampSite(id: "home", worldX: 0, worldZ: 0, isHome: true, padRadius: 22)
        ]
        var rng = SeededRandom(seed: seed &+ 9_001)
        for ring in 1...rings {
            let count = ring == 1 ? 4 : (ring <= 3 ? 5 : 6)
            let baseDist = Float(ring) * 92
            let angleOffset = rng.nextFloat() * Float.pi * 2
            for i in 0..<count {
                let jitter = (rng.nextFloat() - 0.5) * 18
                let dist = baseDist + jitter
                let angle = angleOffset + Float(i) / Float(count) * Float.pi * 2
                    + (rng.nextFloat() - 0.5) * 0.25
                let x = cos(angle) * dist
                let z = sin(angle) * dist
                let id = String(format: "camp_r%d_%d", ring, i)
                result.append(CampSite(
                    id: id,
                    worldX: x,
                    worldZ: z,
                    isHome: false,
                    padRadius: 18
                ))
            }
        }
        return result
    }
}
