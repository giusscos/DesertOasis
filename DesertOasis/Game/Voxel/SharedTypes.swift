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

    var displayName: String {
        if isHome { return "Home Camp" }
        // camp_r3_1 → "Way Camp 2"
        if let n = id.split(separator: "_").last, let idx = Int(n) {
            return "Way Camp \(idx + 1)"
        }
        return "Way Camp"
    }
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
    /// Home + sparse remote camps. Finding another camp should feel rare.
    static func sites(seed: UInt64, rings: Int = 8) -> [CampSite] {
        var result: [CampSite] = [
            CampSite(id: "home", worldX: 0, worldZ: 0, isHome: true, padRadius: 22)
        ]
        var rng = SeededRandom(seed: seed &+ 9_001)
        var campIndex = 0
        for ring in 1...rings {
            // ~1 in 2 rings place a camp; outer rings a bit likelier so the far desert isn't empty.
            let placeChance: Float = ring <= 2 ? 0.35 : 0.55
            guard rng.nextFloat() < placeChance else { continue }

            // Wide spacing: first possible camp ~210 m out, then ~190 m per ring.
            let baseDist = 210 + Float(ring - 1) * 190
            let jitter = (rng.nextFloat() - 0.5) * 40
            let dist = baseDist + jitter
            let angle = rng.nextFloat() * Float.pi * 2
            let x = cos(angle) * dist
            let z = sin(angle) * dist
            let id = String(format: "camp_r%d_%d", ring, campIndex)
            campIndex += 1
            result.append(CampSite(
                id: id,
                worldX: x,
                worldZ: z,
                isHome: false,
                padRadius: 18
            ))
        }
        return result
    }
}
