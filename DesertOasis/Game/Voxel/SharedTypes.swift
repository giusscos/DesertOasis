import SceneKit

/// Metadata about a placed oasis (position and pool radius in world-space metres).
struct OasisInfo {
    var position: SCNVector3
    var radius: Float
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
