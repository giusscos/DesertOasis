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

    static func radius(forScale scale: Float) -> Float {
        1.6 * scale + 0.6
    }

    /// Lobby shell footprint (~8.75 × 13.75 m).
    static func lobbyTentRadius() -> Float { 8.5 }
}

/// Camp: tents, barrel, fire, and a growing oasis irrigated from the barrel.
final class CampNode: SCNNode {

    let site: CampSite
    private(set) var barrelNode: SCNNode!
    private var campfireNode: SCNNode!
    private var waterSurface: SCNNode!
    private(set) var fillLevel: Float = 0
    private(set) var tentFootprints: [TentFootprint] = []
    private var tentNodes: [SCNNode] = []
    private(set) var bedNode: SCNNode?
    private(set) var settingsTableNode: SCNNode?
    private(set) var oasisGrowth: CampOasisGrowthNode!
    private(set) var playerTentNode: SCNNode?
    private var statsSign: CampStatsSignNode!

    /// Collision cylinders (meters) matching VoxelPropBuilder footprints.
    private let barrelCollisionRadius: Float = 0.52
    private let barrelCollisionHeight: Float = 1.2
    private let campfireCollisionRadius: Float = 0.75
    private let campfireCollisionHeight: Float = 1.1
    private let signCollisionRadius: Float = 0.55
    private let signCollisionHeight: Float = 3.4

    let interactionRadius: Float = 3.5
    static let deliveryAmount: Float = 0.12

    /// NPCs irrigate on this interval when there is water in the barrel.
    private var irrigateAccumulator: Float = 0
    private let irrigateInterval: Float = 7.5
    private let minWaterToIrrigate: Float = 0.04

    var onIrrigated: ((Float, OasisGrowthStage, Float, Bool) -> Void)?

    private var pendingNeighbourOffsets: [(Float, Float, Float)] = []
    private var pendingUseLobbyShell = true
    private weak var pendingWorld: VoxelWorld?

    init(site: CampSite, groundHeight: Float, world: VoxelWorld) {
        self.site = site
        super.init()
        name = "camp_\(site.id)"
        position = SCNVector3(site.worldX, groundHeight, site.worldZ)
        if site.isHome {
            buildHomeCamp(world: world)
        } else {
            buildRemoteCamp(world: world)
        }
        buildBarrel()
        buildCampfire()
        buildOasisGrowth()
        buildStatsSign()
    }

    required init?(coder: NSCoder) { nil }

    /// Builds at most one pending neighbour tent. Returns true while more remain.
    @discardableResult
    func buildNextPendingNeighbour() -> Bool {
        guard let world = pendingWorld, !pendingNeighbourOffsets.isEmpty else {
            pendingWorld = nil
            return false
        }
        let next = pendingNeighbourOffsets.removeFirst()
        placeNeighbourTents(offsets: [next], world: world, useLobbyShell: pendingUseLobbyShell)
        if pendingNeighbourOffsets.isEmpty {
            pendingWorld = nil
        }
        return !pendingNeighbourOffsets.isEmpty
    }

    var hasPendingNeighbours: Bool { !pendingNeighbourOffsets.isEmpty }

    // MARK: - Water

    func setFillLevel(_ level: Float) {
        fillLevel = max(0, min(1, level))
        // Solid water column grows upward from the barrel floor.
        waterSurface.scale.y = max(0.02, fillLevel)
        waterSurface.position.y = 0.12
        waterSurface.isHidden = fillLevel < 0.01
        refreshStatsSign()
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

    @discardableResult
    func drainWater(amount: Float = 0.008) -> Float {
        setFillLevel(max(0, fillLevel - amount))
        return fillLevel
    }

    func restoreOasis(stage: OasisGrowthStage, progress: Float) {
        oasisGrowth.restore(stage: stage, progress: progress)
        refreshStatsSign()
    }

    var oasisStage: OasisGrowthStage { oasisGrowth.stage }
    var oasisProgress: Float { oasisGrowth.progress }

    // MARK: - Irrigation (NPCs spend barrel water to grow the oasis)

    /// Call each frame. When the barrel has water, NPCs slowly convert it into oasis growth.
    func updateIrrigation(deltaTime: Float, hasCampNPCs: Bool) {
        guard hasCampNPCs, fillLevel >= minWaterToIrrigate, oasisGrowth.stage != .lush else { return }
        irrigateAccumulator += deltaTime
        guard irrigateAccumulator >= irrigateInterval else { return }
        irrigateAccumulator = 0

        let spent = min(CampOasisGrowthNode.waterPerTick, fillLevel)
        setFillLevel(fillLevel - spent)
        let advanced = oasisGrowth.addProgress(CampOasisGrowthNode.progressPerTick)
        refreshStatsSign()
        onIrrigated?(fillLevel, oasisGrowth.stage, oasisGrowth.progress, advanced)
    }

    /// Fast-forward irrigation during sleep (amount ≈ seconds of work).
    func simulateIrrigation(seconds: Float, hasCampNPCs: Bool) {
        guard hasCampNPCs else { return }
        var remaining = seconds
        while remaining > 0, fillLevel >= minWaterToIrrigate, oasisGrowth.stage != .lush {
            let step = min(irrigateInterval, remaining)
            remaining -= step
            irrigateAccumulator += step
            if irrigateAccumulator >= irrigateInterval {
                irrigateAccumulator = 0
                let spent = min(CampOasisGrowthNode.waterPerTick, fillLevel)
                setFillLevel(fillLevel - spent)
                oasisGrowth.addProgress(CampOasisGrowthNode.progressPerTick)
            }
        }
        refreshStatsSign()
    }

    // MARK: - Collision / footprints

    func isInsideTent(worldX: Float, worldZ: Float) -> Bool {
        tentFootprints.contains { $0.contains(x: worldX, z: worldZ) }
    }

    func isNearBed(worldPosition: SCNVector3, radius: Float = 2.2) -> Bool {
        guard let bed = bedNode else { return false }
        let bedWorld = bed.convertPosition(SCNVector3Zero, to: nil)
        let dx = worldPosition.x - bedWorld.x
        let dz = worldPosition.z - bedWorld.z
        return dx * dx + dz * dz < radius * radius
    }

    func isNearSettingsTable(worldPosition: SCNVector3, radius: Float = 2.0) -> Bool {
        guard let table = settingsTableNode else { return false }
        let tw = table.convertPosition(SCNVector3Zero, to: nil)
        let dx = worldPosition.x - tw.x
        let dz = worldPosition.z - tw.z
        return dx * dx + dz * dz < radius * radius
    }

    func resolvePlayerXZ(from prev: SIMD2<Float>,
                         to next: SIMD2<Float>,
                         worldY: Float,
                         radius: Float) -> SIMD2<Float> {
        if !collidesSolid(x: next.x, y: worldY, z: next.y, radius: radius) {
            return next
        }
        let slideX = SIMD2<Float>(next.x, prev.y)
        if !collidesSolid(x: slideX.x, y: worldY, z: slideX.y, radius: radius) {
            return slideX
        }
        let slideZ = SIMD2<Float>(prev.x, next.y)
        if !collidesSolid(x: slideZ.x, y: worldY, z: slideZ.y, radius: radius) {
            return slideZ
        }
        return prev
    }

    func collidesSolid(x: Float, y: Float, z: Float, radius: Float) -> Bool {
        collidesTentWalls(x: x, y: y, z: z, radius: radius)
            || collidesProps(x: x, y: y, z: z, radius: radius)
    }

    func collidesTentWalls(x: Float, y: Float, z: Float, radius: Float) -> Bool {
        tentNodes.contains { tentWallHit(tent: $0, world: SCNVector3(x, y, z), radius: radius) }
    }

    private func collidesProps(x: Float, y: Float, z: Float, radius: Float) -> Bool {
        if let barrel = barrelNode,
           collidesCylinder(node: barrel, cylRadius: barrelCollisionRadius, height: barrelCollisionHeight,
                            x: x, y: y, z: z, playerRadius: radius) {
            return true
        }
        if let fire = campfireNode,
           collidesCylinder(node: fire, cylRadius: campfireCollisionRadius, height: campfireCollisionHeight,
                            x: x, y: y, z: z, playerRadius: radius) {
            return true
        }
        if let sign = statsSign,
           collidesCylinder(node: sign, cylRadius: signCollisionRadius, height: signCollisionHeight,
                            x: x, y: y, z: z, playerRadius: radius) {
            return true
        }
        return false
    }

    private func collidesCylinder(node: SCNNode,
                                  cylRadius: Float,
                                  height: Float,
                                  x: Float, y: Float, z: Float,
                                  playerRadius: Float) -> Bool {
        let center = node.convertPosition(SCNVector3Zero, to: nil)
        if y < center.y - 0.05 || y > center.y + height + playerRadius {
            return false
        }
        let dx = x - center.x
        let dz = z - center.z
        let r = cylRadius + playerRadius
        return dx * dx + dz * dz < r * r
    }

    private func tentWallHit(tent: SCNNode, world: SCNVector3, radius: Float) -> Bool {
        let local = tent.convertPosition(world, from: nil)
        let isLobby = tent.name == "lobby_tent" || tent.name?.hasPrefix("lobby_tent") == true

        let halfW: Float
        let halfD: Float
        let wallT: Float
        let maxY: Float
        let doorHalf: Float
        let scale: Float

        if isLobby {
            // Matches VoxelPropBuilder.lobbyTentShell (lu = unit * 2.5).
            let lu = VoxelMetrics.unit * 2.5
            halfW = 24 * lu
            halfD = 42 * lu
            wallT = 3.5 * lu
            maxY = 40 * lu
            doorHalf = 10 * lu
            scale = 1
        } else {
            let uf = VoxelMetrics.unit
            halfW = 16 * uf
            halfD = 25 * uf
            wallT = 3.2 * uf
            maxY = 38 * uf
            doorHalf = 7.5 * uf
            scale = max(tent.scale.x, 0.001)
        }

        let r = radius / scale
        if local.y < -0.05 || local.y > maxY + r { return false }

        let lx = local.x
        let lz = local.z

        let inOuter = abs(lx) <= halfW + r
            && lz >= -halfD - r
            && lz <= halfD + r
        guard inOuter else { return false }

        if lz > halfD - wallT * 2 - r && abs(lx) < doorHalf {
            return false
        }

        let innerW = halfW - wallT
        let innerBack = -halfD + wallT
        let inInterior = abs(lx) < innerW - r
            && lz > innerBack + r
            && lz < halfD + r
        if inInterior { return false }
        return true
    }

    private func registerTentFootprint(localX: Float, localZ: Float, radius: Float) {
        tentFootprints.append(TentFootprint(
            x: position.x + localX,
            z: position.z + localZ,
            radius: radius
        ))
    }

    // MARK: - Build

    private func buildHomeCamp(world: VoxelWorld) {
        // Same shell as the title screen lobby tent.
        let tent = VoxelPropBuilder.lobbyTentShell()
        // Entrance faces camp center (−Z after yaw π). Sit slightly north of the fire ring.
        tent.position = SCNVector3(0, 0, 5.5)
        tent.eulerAngles.y = Float.pi
        addChildNode(tent)
        tentNodes.append(tent)
        playerTentNode = tent
        registerTentFootprint(localX: 0, localZ: 5.5, radius: TentFootprint.lobbyTentRadius())

        // Bed + settings table — same props/placements as the lobby, in tent-local space.
        let bed = VoxelPropBuilder.lobbyBed()
        bed.name = "sleep_bed"
        bed.position = SCNVector3(2.45, 0, 5.5 + 0.7)
        bed.eulerAngles.y = Float.pi
        for i in 0..<3 {
            bed.childNode(withName: "diary_\(i)", recursively: true)?.isHidden = true
        }
        addChildNode(bed)
        bedNode = bed

        let table = VoxelPropBuilder.lobbyTable()
        table.name = "camp_settings_table"
        table.position = SCNVector3(-2.2, 0, 5.5 + 1.0)
        table.eulerAngles.y = Float.pi / 2
        addChildNode(table)
        settingsTableNode = table

        // Neighbours use the same large tent shell, spaced for the bigger footprint.
        let neighbourOffsets: [(Float, Float, Float)] = [
            (-16.0, -5.0, 0.55),
            ( 16.0, -4.5, -0.75),
            (-6.0, -16.5, 2.1),
        ]
        placeNeighbourTents(offsets: neighbourOffsets, world: world, useLobbyShell: true)
    }

    private func buildRemoteCamp(world: VoxelWorld) {
        let tent = VoxelPropBuilder.lobbyTentShell(includeSign: false)
        tent.position = SCNVector3(0, 0, 5.0)
        tent.eulerAngles.y = Float.pi
        tent.name = "lobby_tent_remote"
        addChildNode(tent)
        tentNodes.append(tent)
        playerTentNode = tent
        registerTentFootprint(localX: 0, localZ: 5.0, radius: TentFootprint.lobbyTentRadius())

        let bed = VoxelPropBuilder.lobbyBed()
        bed.name = "sleep_bed"
        bed.position = SCNVector3(2.45, 0, 5.0 + 0.7)
        bed.eulerAngles.y = Float.pi
        for i in 0..<3 {
            bed.childNode(withName: "diary_\(i)", recursively: true)?.isHidden = true
        }
        addChildNode(bed)
        bedNode = bed

        let neighbourOffsets: [(Float, Float, Float)] = [
            (-15.0, -4.0, 0.5),
            ( 15.0, -3.5, -0.7),
        ]
        pendingUseLobbyShell = true
        pendingWorld = world
        pendingNeighbourOffsets = neighbourOffsets
    }

    private func placeNeighbourTents(offsets: [(Float, Float, Float)],
                                     world: VoxelWorld,
                                     useLobbyShell: Bool) {
        for (i, offset) in offsets.enumerated() {
            let tent: SCNNode
            let footprintRadius: Float
            if useLobbyShell {
                tent = VoxelPropBuilder.lobbyTentShell(includeSign: false)
                tent.name = "lobby_tent_neighbour_\(i)"
                footprintRadius = TentFootprint.lobbyTentRadius()
            } else {
                let scale: Float = 1.15
                tent = VoxelPropBuilder.tent(scale: scale)
                tent.name = "neighbour_tent_\(i)"
                footprintRadius = TentFootprint.radius(forScale: scale)
            }
            let wx = offset.0
            let wz = offset.1
            let worldH = world.surfaceY(atWorldX: position.x + wx, worldZ: position.z + wz)
            let localY = max(0, worldH - position.y)
            tent.position = SCNVector3(wx, localY, wz)
            tent.eulerAngles.y = offset.2
            VoxelPropBuilder.furnishNeighbourTent(tent, index: i)
            addChildNode(tent)
            tentNodes.append(tent)
            registerTentFootprint(localX: wx, localZ: wz, radius: footprintRadius)
        }
    }

    private func buildBarrel() {
        barrelNode = VoxelPropBuilder.waterBarrel()
        barrelNode.position = SCNVector3(3.6, 0, -2.2)
        waterSurface = barrelNode.childNode(withName: "water_surface", recursively: true)!
        addChildNode(barrelNode)
    }

    private func buildCampfire() {
        campfireNode = VoxelPropBuilder.campfire()
        campfireNode.position = SCNVector3(-1.8, 0, -2.4)
        addChildNode(campfireNode)
    }

    private func buildOasisGrowth() {
        oasisGrowth = CampOasisGrowthNode()
        // Grow the oasis on the open side of camp, opposite the main tent.
        oasisGrowth.position = SCNVector3(0.5, 0, -5.5)
        addChildNode(oasisGrowth)
    }

    private func buildStatsSign() {
        statsSign = CampStatsSignNode(title: site.displayName)
        // South-east of the plaza by the barrel, face south so third-person
        // cameras looking into camp read the board head-on.
        statsSign.position = SCNVector3(4.6, 0, -3.8)
        statsSign.eulerAngles.y = .pi
        addChildNode(statsSign)
        refreshStatsSign()
    }

    private func refreshStatsSign() {
        statsSign?.refresh(water: fillLevel, stage: oasisStage, progress: oasisProgress)
    }
}
