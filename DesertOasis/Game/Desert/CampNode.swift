import SceneKit
import UIKit

/// Circular keep-out around a tent (world XZ).
struct TentFootprint {
    let x: Float
    let z: Float
    let radius: Float

    func contains(x wx: Float, z wz: Float) -> Bool {
        let dx = wx - x
        let dz = wz - z
        return dx * dx + dz * dz < radius * radius
    }

    /// Approximate clear radius from prop footprint × scale (+ margin).
    static func radius(forScale scale: Float) -> Float {
        // Base tent ~2.25 × 3.1 m; use half-diagonal + padding.
        1.6 * scale + 0.6
    }
}

/// Home camp: voxel tents, neighbour tents, and the shared water barrel.
final class CampNode: SCNNode {

    private(set) var barrelNode: SCNNode!
    private var waterSurface: SCNNode!
    private(set) var fillLevel: Float = 0
    /// World-space tent keep-outs (filled after tents are placed).
    private(set) var tentFootprints: [TentFootprint] = []

    let interactionRadius: Float = 3.5
    static let deliveryAmount: Float = 0.12

    init(groundHeight: Float, world: VoxelWorld) {
        super.init()
        name = "camp"
        position = SCNVector3(0, groundHeight, 0)
        buildTents(world: world)
        buildBarrel()
        buildCampfire()
    }

    required init?(coder: NSCoder) { nil }

    func setFillLevel(_ level: Float) {
        fillLevel = max(0, min(1, level))
        waterSurface.scale.y = max(0.02, fillLevel)
        waterSurface.position.y = 0.08 + fillLevel * 0.95
        waterSurface.isHidden = fillLevel < 0.01
    }

    func canDeliver(at worldPosition: SCNVector3) -> Bool {
        let local = convertPosition(worldPosition, from: nil)
        let dx = local.x - barrelNode.position.x
        let dz = local.z - barrelNode.position.z
        return sqrt(dx * dx + dz * dz) < interactionRadius
    }

    @discardableResult
    func deliverWater() -> Float {
        setFillLevel(fillLevel + Self.deliveryAmount)
        return fillLevel
    }

    func isInsideTent(worldX: Float, worldZ: Float) -> Bool {
        tentFootprints.contains { $0.contains(x: worldX, z: worldZ) }
    }

    private func registerTentFootprint(localX: Float, localZ: Float, scale: Float) {
        tentFootprints.append(TentFootprint(
            x: position.x + localX,
            z: position.z + localZ,
            radius: TentFootprint.radius(forScale: scale)
        ))
    }

    private func buildTents(world: VoxelWorld) {
        let playerScale: Float = 1.45
        let playerTent = VoxelPropBuilder.tent(scale: playerScale)
        playerTent.position = SCNVector3(0, 0, 3.2)
        playerTent.eulerAngles.y = Float.pi
        addChildNode(playerTent)
        registerTentFootprint(localX: 0, localZ: 3.2, scale: playerScale)

        // Keep neighbour tents well inside the flat camp pad (~12 m radius).
        let neighbourOffsets: [(Float, Float, Float)] = [
            (-6.5, -3.5, 0.6),
            ( 6.8, -2.8, -0.9),
            (-3.5, -7.0, 2.2),
        ]
        let neighbourScale: Float = 1.15
        for (i, offset) in neighbourOffsets.enumerated() {
            let tent = VoxelPropBuilder.tent(scale: neighbourScale)
            let wx = offset.0
            let wz = offset.1
            // Sit on camp floor (pad is flat); avoid sampling cliff edges.
            let worldH = world.surfaceY(atWorldX: wx, worldZ: wz)
            let localY = max(0, worldH - position.y)
            tent.position = SCNVector3(wx, localY, wz)
            tent.eulerAngles.y = offset.2
            tent.name = "neighbour_tent_\(i)"
            addChildNode(tent)
            registerTentFootprint(localX: wx, localZ: wz, scale: neighbourScale)
        }
    }

    private func buildBarrel() {
        barrelNode = VoxelPropBuilder.waterBarrel()
        barrelNode.position = SCNVector3(3.2, 0, -1.5)
        waterSurface = barrelNode.childNode(withName: "water_surface", recursively: true)!
        addChildNode(barrelNode)
    }

    private func buildCampfire() {
        let fire = VoxelPropBuilder.campfire()
        fire.position = SCNVector3(-1.5, 0, -2.0)
        addChildNode(fire)
    }
}
