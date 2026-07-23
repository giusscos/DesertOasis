import UIKit
import SceneKit

/// Shared voxel sizing. Terrain uses `blockSize`; props/characters use finer `unit`.
enum VoxelMetrics {
    /// Terrain block edge length in meters.
    static let blockSize: Float = 0.5
    /// Keep the same ~240 m playable footprint.
    static let worldSizeMeters: Float = 240
    static var worldSizeBlocks: Int { Int((worldSizeMeters / blockSize).rounded()) }

    /// MagicaVoxel-style prop cube (1/16 m) — small enough for stair-step curves.
    static let unit: Float = 0.0625
    static var u: CGFloat { CGFloat(unit) }

    /// Convert a meter length to the nearest whole prop-units (≥ 1).
    static func units(_ meters: Float) -> Int {
        max(1, Int((meters / unit).rounded()))
    }
}

/// Block IDs stored in the voxel grid.
enum VoxelType: UInt8 {
    case air = 0
    case sand
    case sandstone
    case rock
    case water
    case cactus
    case wood
    case leaf
    case canvas
    case cloth
    case darkWood
    case iron
    case brass
    case skin
    case hair

    var isEmpty: Bool { self == .air }

    /// Transparent blocks don't occlude neighbors for solid faces; water culls against water.
    var isTransparent: Bool {
        switch self {
        case .air, .water, .leaf: return true
        default: return false
        }
    }

    var isSolid: Bool {
        switch self {
        case .air, .water: return false
        default: return true
        }
    }

    /// Surface the player stands on (includes water top).
    var isSurface: Bool { self != .air }

    var color: UIColor {
        switch self {
        case .air:       return .clear
        case .sand:      return UIColor(red: 0.87, green: 0.78, blue: 0.57, alpha: 1)
        case .sandstone: return UIColor(red: 0.78, green: 0.66, blue: 0.48, alpha: 1)
        case .rock:      return UIColor(red: 0.55, green: 0.48, blue: 0.42, alpha: 1)
        case .water:     return UIColor(red: 0.22, green: 0.55, blue: 0.78, alpha: 0.72)
        case .cactus:    return UIColor(red: 0.28, green: 0.55, blue: 0.28, alpha: 1)
        case .wood:      return UIColor(red: 0.50, green: 0.36, blue: 0.20, alpha: 1)
        case .leaf:      return UIColor(red: 0.25, green: 0.48, blue: 0.22, alpha: 1)
        case .canvas:    return UIColor(red: 0.72, green: 0.62, blue: 0.42, alpha: 1)
        case .cloth:     return UIColor(red: 0.55, green: 0.35, blue: 0.25, alpha: 1)
        case .darkWood:  return UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1)
        case .iron:      return UIColor(white: 0.32, alpha: 1)
        case .brass:     return UIColor(red: 0.72, green: 0.55, blue: 0.22, alpha: 1)
        case .skin:      return UIColor(red: 0.90, green: 0.74, blue: 0.58, alpha: 1)
        case .hair:      return UIColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1)
        }
    }

    var scnColor: SCNVector3 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SCNVector3(Float(r), Float(g), Float(b))
    }
}
