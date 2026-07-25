import SceneKit

/// Metadata about a placed oasis (position and pool radius in world-space metres).
struct OasisInfo {
    var position: SCNVector3
    /// Flat pool radius in metres.
    var radius: Float
    var landmark: LandmarkKind? = nil

    var displayName: String {
        landmark?.displayName ?? "Oasis"
    }
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
    /// Home + remote camps. Sparse enough to explore, dense enough to find along a compass bearing.
    static func sites(seed: UInt64, rings: Int = 8) -> [CampSite] {
        var result: [CampSite] = [
            CampSite(id: "home", worldX: 0, worldZ: 0, isHome: true, padRadius: 22)
        ]
        var rng = SeededRandom(seed: seed &+ 9_001)
        var campIndex = 0

        // Always place one mid-near beacon camp so the post-flourish mission has a real target.
        let beaconDist = 200 + rng.nextFloat() * 90 // 200…290 m
        let beaconAngle = rng.nextFloat() * Float.pi * 2
        result.append(CampSite(
            id: String(format: "camp_beacon_%d", campIndex),
            worldX: cos(beaconAngle) * beaconDist,
            worldZ: sin(beaconAngle) * beaconDist,
            isHome: false,
            padRadius: 18
        ))
        campIndex += 1

        for ring in 1...rings {
            let placeChance: Float = ring <= 3 ? 0.62 : 0.48
            guard rng.nextFloat() < placeChance else { continue }

            // Closer ring spacing than before — first extras ~310 m, then ~145 m/ring.
            let baseDist = 310 + Float(ring - 1) * 145
            let jitter = (rng.nextFloat() - 0.5) * 36
            let dist = baseDist + jitter
            let angle = rng.nextFloat() * Float.pi * 2
            let x = cos(angle) * dist
            let z = sin(angle) * dist

            // Skip if overlapping the beacon (or another camp) too closely.
            let tooClose = result.contains {
                let dx = $0.worldX - x
                let dz = $0.worldZ - z
                return dx * dx + dz * dz < 110 * 110
            }
            if tooClose { continue }

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

    /// Nearest remote camp not yet in `discoveredIDs`, from home (0,0).
    static func nearestUndiscoveredRemote(
        seed: UInt64,
        discoveredIDs: Set<String>
    ) -> CampSite? {
        sites(seed: seed)
            .filter { !$0.isHome && !discoveredIDs.contains($0.id) }
            .min { a, b in
                let da = a.worldX * a.worldX + a.worldZ * a.worldZ
                let db = b.worldX * b.worldX + b.worldZ * b.worldZ
                return da < db
            }
    }

    /// Vague poetic bearing for compass navigation. World north = −Z.
    /// Uses 16 sectors (~22.5°) so the elder's hint is usable without being a waypoint.
    static func poeticCompassHint(toward site: CampSite, fromX: Float = 0, fromZ: Float = 0) -> String {
        let dx = site.worldX - fromX
        let dz = site.worldZ - fromZ
        var angle = atan2(dx, -dz)
        if angle < 0 { angle += Float.pi * 2 }
        let sector = Int((angle / (Float.pi / 8)).rounded()) % 16
        switch sector {
        case 0:  return "toward true north"
        case 1:  return "a little east of north"
        case 2:  return "between north and the rising sun"
        case 3:  return "mostly toward the rising sun"
        case 4:  return "toward the rising sun"
        case 5:  return "a little south of the rising sun"
        case 6:  return "where morning leans into the heat"
        case 7:  return "mostly into the midday heat"
        case 8:  return "into the long heat of midday"
        case 9:  return "a little west of midday"
        case 10: return "toward the softer evening dunes"
        case 11: return "mostly toward the setting sun"
        case 12: return "toward the setting sun"
        case 13: return "a little north of the setting sun"
        case 14: return "between north and the setting sun"
        default: return "mostly north, toward the evening edge"
        }
    }

    /// Smallest angle between two bearings in radians.
    static func bearingDelta(_ a: Float, _ b: Float) -> Float {
        var d = abs(a - b)
        if d > Float.pi { d = Float.pi * 2 - d }
        return d
    }

    static func bearingTo(x: Float, z: Float, fromX: Float = 0, fromZ: Float = 0) -> Float {
        atan2(x - fromX, -(z - fromZ))
    }
}
