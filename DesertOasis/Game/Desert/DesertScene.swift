import SceneKit
import UIKit

final class DesertScene: SCNScene, SCNPhysicsContactDelegate {

    private(set) var playerNode: PlayerNode!
    private(set) var toolRig: PlayerToolRig!
    private(set) var camp: CampNode!
    private(set) var npcs: [NPCNode] = []
    private(set) var oases: [OasisInfo] = []
    private(set) var waterBodies: [OasisWaterNode] = []
    private var voxelWorld: VoxelWorld!
    private var worldSeed: UInt64 = 0

    let cameraNode = SCNNode()
    let cameraArmNode = SCNNode()
    private let cameraPitchNode = SCNNode()
    private let cameraLookTarget = SCNNode()
    private var cameraPitch: Float = -0.32
    private let cameraDistance: Float = 8.2
    private let cameraMinDistance: Float = 1.15
    /// Solid camera sphere radius used for collision.
    private let cameraRadius: Float = 0.4
    /// How quickly the view direction orbits toward the desired boom angle.
    private let cameraOrbitSpeed: Float = 18
    /// How quickly boom length expands/contracts along the current view ray.
    private let cameraDistanceSpeed: Float = 14
    private var cameraWorldPosition: SCNVector3?
    private let cameraPitchMin: Float = -1.05
    private let cameraPitchMax: Float = 0.40
    private let playerCollisionRadius: Float = 0.32

    var onNPCProximity: ((NPCNode) -> Void)?
    var onOasisReached: ((OasisInfo) -> Void)?
    var onWaterCollected: (() -> Void)?
    var onWaterDelivered: ((Float, Bool, Bool) -> Void)?
    var onNearBarrel: ((Bool) -> Void)?
    var onCampDrained: ((Float) -> Void)?
    var onWaterGivenToNPC: ((NPCNode) -> Void)?
    var onNearWater: ((Bool) -> Void)?

    private var playerHorizontalSpeed: Float = 0
    private var isInWater = false
    private var toolTime: Float = 0
    private var wasNearBarrel = false
    private var deliveryCount = 0

    // Oasis depletion
    private var wasNearCollectableWater = false
    private var depletedWaterBodies: Set<ObjectIdentifier> = []
    private var oasisRefillTimers: [ObjectIdentifier: Float] = [:]
    private let oasisRefillTime: Float = 90.0

    // Camp drain
    private var campDrainAccumulator: Float = 0
    private let campDrainInterval: Float = 18.0
    private let campDrainAmount: Float = 0.007

    // Progressive world build
    private(set) var isBuildingWorld = false
    private var buildSlot: SaveSlot?
    private var buildGenerator: VoxelWorldGenerator?
    private var pendingChunkCoords: [(cx: Int, cz: Int)] = []
    private var buildChunkIndex = 0
    private let chunksPerFrame = 6

    var onBuildProgress: ((Float) -> Void)?
    var onBuildComplete: (() -> Void)?

    // MARK: - Build

    /// Streams terrain chunks outward from camp so the player can watch the desert form.
    func build(from slot: SaveSlot) {
        guard !isBuildingWorld else { return }
        isBuildingWorld = true
        buildSlot = slot
        worldSeed = slot.desertSeed
        background.contents = skyboxGradient()
        deliveryCount = slot.waterDeliveries

        setupLighting()
        setupSky()

        voxelWorld = VoxelWorld(seed: slot.desertSeed)
        rootNode.addChildNode(voxelWorld.rootNode)

        buildGenerator = VoxelWorldGenerator(seed: slot.desertSeed)
        pendingChunkCoords = voxelWorld.chunkCoordinatesFromCenter()
        buildChunkIndex = 0

        setupOverviewCamera()
        onBuildProgress?(0)
        scheduleNextBuildBatch()
    }

    private func scheduleNextBuildBatch() {
        DispatchQueue.main.async { [weak self] in
            self?.processBuildBatch()
        }
    }

    private func processBuildBatch() {
        guard isBuildingWorld, let generator = buildGenerator, voxelWorld != nil else { return }

        let total = pendingChunkCoords.count
        guard total > 0 else {
            finalizeBuild()
            return
        }

        let end = min(buildChunkIndex + chunksPerFrame, total)
        for i in buildChunkIndex..<end {
            let coord = pendingChunkCoords[i]
            generator.generateChunk(into: voxelWorld, cx: coord.cx, cz: coord.cz)
            voxelWorld.remeshChunk(cx: coord.cx, cz: coord.cz, animated: true)
        }
        buildChunkIndex = end

        // Terrain fill is ~0–0.92 of the progress bar; finalize fills the rest.
        let terrainProgress = Float(end) / Float(total)
        onBuildProgress?(terrainProgress * 0.92)

        if end < total {
            scheduleNextBuildBatch()
        } else {
            finalizeBuild()
        }
    }

    private func finalizeBuild() {
        guard let slot = buildSlot, let generator = buildGenerator else { return }

        oases = generator.placeAndCarveOases(into: voxelWorld, oasisCount: 6)
        voxelWorld.remeshDirtyChunks()
        onBuildProgress?(0.96)

        let campGround = voxelWorld.surfaceY(atWorldX: 0, worldZ: 0)
        camp = CampNode(groundHeight: campGround, world: voxelWorld)
        camp.setFillLevel(slot.campWaterLevel)
        rootNode.addChildNode(camp)

        waterBodies.removeAll()
        for oasis in oases {
            let container = SCNNode()
            container.position = SCNVector3(oasis.position.x, oasis.position.y, oasis.position.z)
            let water = OasisWaterNode(radius: oasis.radius, resolution: 18)
            container.addChildNode(water)
            rootNode.addChildNode(container)
            waterBodies.append(water)
        }

        let props = VoxelPropBuilder.scatterProps(world: voxelWorld, oases: oases, seed: slot.desertSeed)
        rootNode.addChildNode(props)

        spawnNPCs()
        setupPlayer(slot: slot)
        tearDownOverviewCamera()
        setupCamera()
        setupPhysics()

        buildSlot = nil
        buildGenerator = nil
        pendingChunkCoords = []
        isBuildingWorld = false
        onBuildProgress?(1)
        onBuildComplete?()
    }

    private func setupOverviewCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 62
        camera.zNear = 0.5
        camera.zFar = 600
        cameraNode.camera = camera
        cameraNode.constraints = nil
        cameraNode.eulerAngles = SCNVector3(-0.92, 0.15, 0)
        cameraNode.position = SCNVector3(18, 110, 95)
        if cameraNode.parent == nil {
            rootNode.addChildNode(cameraNode)
        }
    }

    private func tearDownOverviewCamera() {
        cameraNode.removeFromParentNode()
        cameraNode.constraints = nil
        cameraNode.eulerAngles = SCNVector3Zero
    }

    private func groundY(x: Float, z: Float) -> Float {
        voxelWorld.surfaceY(atWorldX: x, worldZ: z)
    }

    // MARK: - Lighting

    private func setupLighting() {
        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(red: 1.0, green: 0.93, blue: 0.75, alpha: 1)
        sun.intensity = 1200
        sun.castsShadow = true
        sun.shadowRadius = 4
        sun.shadowColor = UIColor(white: 0, alpha: 0.4)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi * 0.45, Float.pi * 0.25, 0)
        rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.62, green: 0.72, blue: 0.85, alpha: 1)
        ambient.intensity = 420
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)
    }

    // MARK: - Sky

    private func setupSky() {
        let sky = SCNNode(geometry: SCNSphere(radius: 400))
        sky.name = "sky"
        let mat = SCNMaterial()
        mat.diffuse.contents = skyboxGradient()
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        sky.geometry?.firstMaterial = mat
        sky.geometry?.firstMaterial?.cullMode = .front
        rootNode.addChildNode(sky)
    }

    private func skyboxGradient() -> UIColor {
        UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)
    }

    // MARK: - Player

    private func setupPlayer(slot: SaveSlot) {
        let gender = slot.characterGender ?? .man
        playerNode = PlayerNode(gender: gender)

        let spawnX = slot.playerPositionX
        let spawnZ = slot.playerPositionZ
        let nearOrigin = abs(spawnX) < 0.5 && abs(spawnZ) < 0.5
        let x = nearOrigin ? 1.5 : spawnX
        let z = nearOrigin ? 0.5 : spawnZ
        let groundH = groundY(x: x, z: z)
        playerNode.position = SCNVector3(x, groundH + 0.01, z)
        rootNode.addChildNode(playerNode)

        toolRig = PlayerToolRig()
        toolRig.setCarryingWater(slot.isCarryingWater)
        toolRig.setCompassUnlocked(slot.hasWaterCompass)
        toolRig.setDetectorUnlocked(slot.hasWaterDetector)
        playerNode.addChildNode(toolRig)
    }

    // MARK: - Camera

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 65
        camera.zNear = 0.2
        camera.zFar = 500
        cameraNode.camera = camera
        cameraNode.eulerAngles = SCNVector3Zero
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        cameraWorldPosition = nil
        cameraNode.constraints = nil

        // Look target rides on the yaw arm (player height), not the pitch boom
        cameraLookTarget.position = SCNVector3(0, 1.25, 0)
        if cameraLookTarget.parent == nil {
            cameraArmNode.addChildNode(cameraLookTarget)
        }

        if cameraPitchNode.parent == nil {
            cameraArmNode.addChildNode(cameraPitchNode)
        }
        if cameraNode.parent != cameraPitchNode {
            cameraPitchNode.addChildNode(cameraNode)
        }

        let lookAt = SCNLookAtConstraint(target: cameraLookTarget)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        cameraPitchNode.eulerAngles.x = cameraPitch
        if cameraArmNode.parent == nil {
            rootNode.addChildNode(cameraArmNode)
        }
        syncCameraFollow()
        resolveCameraCollision(deltaTime: 1)
    }

    private func syncCameraFollow() {
        guard let playerNode else { return }
        cameraArmNode.position = playerNode.position
    }

    /// Orbit the camera around obstacles: rotate the view ray fluidly and ride the
    /// contact silhouette instead of stopping with friction when blocked.
    private func resolveCameraCollision(deltaTime: Float) {
        let lookWorld = cameraLookTarget.convertPosition(SCNVector3Zero, to: nil)
        let desiredWorld = cameraPitchNode.convertPosition(SCNVector3(0, 0, cameraDistance), to: nil)

        let desiredVec = simd_float3(
            desiredWorld.x - lookWorld.x,
            desiredWorld.y - lookWorld.y,
            desiredWorld.z - lookWorld.z
        )
        let desiredLen = simd_length(desiredVec)
        guard desiredLen > 1e-4 else { return }
        let desiredDir = desiredVec / desiredLen

        let previous = cameraWorldPosition ?? desiredWorld
        var prevVec = simd_float3(
            previous.x - lookWorld.x,
            previous.y - lookWorld.y,
            previous.z - lookWorld.z
        )
        var prevLen = simd_length(prevVec)
        if prevLen < 1e-4 {
            prevVec = desiredVec
            prevLen = desiredLen
        }
        let prevDir = prevVec / prevLen

        let dt = max(0, deltaTime)
        let orbitBlend = 1 - exp(-cameraOrbitSpeed * dt)
        let dir = slerpCameraDir(prevDir, desiredDir, orbitBlend)

        // Clear length along this orbit ray — follows the object perimeter as you pan.
        let probeEnd = SCNVector3(
            lookWorld.x + dir.x * cameraDistance,
            lookWorld.y + dir.y * cameraDistance,
            lookWorld.z + dir.z * cameraDistance
        )
        let clearDist = clearCameraDistance(from: lookWorld, toward: probeEnd)

        let distBlend = 1 - exp(-cameraDistanceSpeed * dt)
        var dist = prevLen + (clearDist - prevLen) * distBlend
        dist = max(cameraMinDistance, min(cameraDistance, dist))

        var pos = SCNVector3(
            lookWorld.x + dir.x * dist,
            lookWorld.y + dir.y * dist,
            lookWorld.z + dir.z * dist
        )

        // If the sphere clips while sliding around a surface, glide along the tangent.
        pos = slideCameraAlongSurfaces(from: previous, to: pos)

        pos = depenetrateCamera(at: pos)
        pos = projectCameraOntoLookRay(pos, look: lookWorld, direction: dir, distance: dist)

        if let voxelWorld {
            let ground = voxelWorld.surfaceY(atWorldX: pos.x, worldZ: pos.z)
            if pos.y < ground + cameraRadius {
                pos.y = ground + cameraRadius
                // Keep framing: push back onto the orbit ray at a safe distance.
                let toCam = simd_float3(pos.x - lookWorld.x, pos.y - lookWorld.y, pos.z - lookWorld.z)
                let len = simd_length(toCam)
                if len > 1e-4 {
                    let nd = toCam / len
                    let d = max(cameraMinDistance, min(cameraDistance, len))
                    pos = SCNVector3(
                        lookWorld.x + nd.x * d,
                        lookWorld.y + nd.y * d,
                        lookWorld.z + nd.z * d
                    )
                }
            }
        }

        cameraWorldPosition = pos
        cameraNode.position = cameraPitchNode.convertPosition(pos, from: nil)
    }

    private func slerpCameraDir(_ from: simd_float3, _ to: simd_float3, _ t: Float) -> simd_float3 {
        let clampedT = max(0, min(1, t))
        let dot = max(-1, min(1, simd_dot(from, to)))
        if dot > 0.9995 {
            return simd_normalize(from * (1 - clampedT) + to * clampedT)
        }
        if dot < -0.9995 {
            // Opposite directions — pick a perpendicular axis and rotate.
            var axis = simd_cross(from, simd_float3(0, 1, 0))
            if simd_length(axis) < 1e-4 {
                axis = simd_cross(from, simd_float3(1, 0, 0))
            }
            axis = simd_normalize(axis)
            let half = simd_quatf(angle: .pi * clampedT, axis: axis)
            return simd_normalize(half.act(from))
        }
        let theta = acos(dot)
        let sinTheta = sin(theta)
        let w1 = sin((1 - clampedT) * theta) / sinTheta
        let w2 = sin(clampedT * theta) / sinTheta
        return simd_normalize(from * w1 + to * w2)
    }

    private func clearCameraDistance(from: SCNVector3, toward: SCNVector3) -> Float {
        let move = simd_float3(toward.x - from.x, toward.y - from.y, toward.z - from.z)
        let moveLen = simd_length(move)
        guard moveLen > cameraMinDistance else { return cameraMinDistance }

        var best = moveLen
        let hits = rootNode.hitTestWithSegment(from: from, to: toward, options: cameraHitOptions())
        for hit in hits {
            guard !shouldIgnoreCameraHit(hit.node) else { continue }
            let hx = Float(hit.worldCoordinates.x - from.x)
            let hy = Float(hit.worldCoordinates.y - from.y)
            let hz = Float(hit.worldCoordinates.z - from.z)
            let hitDist = sqrt(hx * hx + hy * hy + hz * hz)
            best = min(best, max(cameraMinDistance, hitDist - cameraRadius))
        }
        return min(cameraDistance, best)
    }

    /// Collide-and-slide so orbiting around an obstacle follows its perimeter.
    private func slideCameraAlongSurfaces(from: SCNVector3, to: SCNVector3) -> SCNVector3 {
        var pos = from
        var remaining = simd_float3(to.x - from.x, to.y - from.y, to.z - from.z)

        for _ in 0..<4 {
            let remLen = simd_length(remaining)
            if remLen < 1e-5 { break }

            let candidate = SCNVector3(pos.x + remaining.x, pos.y + remaining.y, pos.z + remaining.z)
            let hits = rootNode.hitTestWithSegment(from: pos, to: candidate, options: cameraHitOptions())
            var closestHit: SCNHitTestResult?
            var closestDist = remLen
            for hit in hits {
                guard !shouldIgnoreCameraHit(hit.node) else { continue }
                let hx = Float(hit.worldCoordinates.x - pos.x)
                let hy = Float(hit.worldCoordinates.y - pos.y)
                let hz = Float(hit.worldCoordinates.z - pos.z)
                let hitDist = sqrt(hx * hx + hy * hy + hz * hz)
                if hitDist < closestDist {
                    closestDist = hitDist
                    closestHit = hit
                }
            }

            guard let hit = closestHit else {
                pos = candidate
                break
            }

            let travel = max(0, closestDist - cameraRadius * 0.98)
            let step = remaining / remLen
            pos = SCNVector3(
                pos.x + step.x * travel,
                pos.y + step.y * travel,
                pos.z + step.z * travel
            )

            var normal = simd_float3(
                Float(hit.worldNormal.x),
                Float(hit.worldNormal.y),
                Float(hit.worldNormal.z)
            )
            let nLen = simd_length(normal)
            if nLen > 1e-4 {
                normal /= nLen
            } else {
                normal = -step
            }
            // Outward from the surface (against the approach).
            if simd_dot(normal, step) > 0 {
                normal = -normal
            }

            // Keep only the tangential part → glide around the perimeter.
            let into = simd_dot(remaining, normal)
            if into < 0 {
                remaining -= normal * into
            } else {
                remaining = simd_float3(0, 0, 0)
            }

            pos = SCNVector3(
                pos.x + normal.x * 0.02,
                pos.y + normal.y * 0.02,
                pos.z + normal.z * 0.02
            )
        }
        return pos
    }

    private func projectCameraOntoLookRay(_ position: SCNVector3,
                                          look: SCNVector3,
                                          direction: simd_float3,
                                          distance: Float) -> SCNVector3 {
        // Prefer staying on the intended orbit ray after sliding/depenetration.
        let onRay = SCNVector3(
            look.x + direction.x * distance,
            look.y + direction.y * distance,
            look.z + direction.z * distance
        )
        // If on-ray is clear of fresh penetration, use it; otherwise keep slid position
        // projected to the same distance from the look target.
        let clear = clearCameraDistance(from: look, toward: onRay)
        if clear >= distance - 0.05 {
            return onRay
        }
        let offset = simd_float3(position.x - look.x, position.y - look.y, position.z - look.z)
        let len = simd_length(offset)
        guard len > 1e-4 else { return onRay }
        let d = max(cameraMinDistance, min(distance, len))
        let nd = offset / len
        return SCNVector3(look.x + nd.x * d, look.y + nd.y * d, look.z + nd.z * d)
    }

    private func depenetrateCamera(at position: SCNVector3) -> SCNVector3 {
        var pos = position
        let axes: [simd_float3] = [
            simd_float3(1, 0, 0), simd_float3(-1, 0, 0),
            simd_float3(0, 1, 0), simd_float3(0, -1, 0),
            simd_float3(0, 0, 1), simd_float3(0, 0, -1),
            simd_normalize(simd_float3(1, 0, 1)),
            simd_normalize(simd_float3(-1, 0, 1)),
            simd_normalize(simd_float3(1, 0, -1)),
            simd_normalize(simd_float3(-1, 0, -1)),
        ]
        for dir in axes {
            let end = SCNVector3(
                pos.x + dir.x * cameraRadius,
                pos.y + dir.y * cameraRadius,
                pos.z + dir.z * cameraRadius
            )
            let hits = rootNode.hitTestWithSegment(from: pos, to: end, options: cameraHitOptions())
            for hit in hits {
                guard !shouldIgnoreCameraHit(hit.node) else { continue }
                let hx = Float(hit.worldCoordinates.x - pos.x)
                let hy = Float(hit.worldCoordinates.y - pos.y)
                let hz = Float(hit.worldCoordinates.z - pos.z)
                let hitDist = sqrt(hx * hx + hy * hy + hz * hz)
                let penetration = cameraRadius - hitDist
                if penetration > 0 {
                    let n = hit.worldNormal
                    var nx = Float(n.x), ny = Float(n.y), nz = Float(n.z)
                    let nLen = sqrt(nx * nx + ny * ny + nz * nz)
                    if nLen > 1e-4 {
                        nx /= nLen; ny /= nLen; nz /= nLen
                    } else {
                        nx = dir.x; ny = dir.y; nz = dir.z
                    }
                    pos.x += nx * penetration
                    pos.y += ny * penetration
                    pos.z += nz * penetration
                }
            }
        }
        return pos
    }

    private func cameraHitOptions() -> [String: Any] {
        [
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.ignoreHiddenNodes.rawValue: true,
        ]
    }

    private func shouldIgnoreCameraHit(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let n = current {
            if n === playerNode || n === cameraArmNode || n === cameraPitchNode
                || n === cameraNode || n === cameraLookTarget {
                return true
            }
            if let name = n.name, name == "sky" || name == "tool_rig" {
                return true
            }
            current = n.parent
        }
        return false
    }

    // MARK: - NPCs

    private func spawnNPCs() {
        var rng = SeededRandom(seed: worldSeed &+ 12345)
        let half = voxelWorld.totalSize * 0.5
        let footprints = camp.tentFootprints

        func blocked(_ wx: Float, _ wz: Float) -> Bool {
            footprints.contains { $0.contains(x: wx, z: wz) }
        }

        // Open camp spots — clear of tent footprints (tent XZ ≈ (0,3.2), (±6–7,−3), (−3.5,−7)).
        let campPersonalities: [NPCPersonality] = [.elder, .child, .merchant]
        for personality in campPersonalities {
            let spot = randomCampSpot(rng: &rng, isBlocked: blocked)
                ?? openCampFallback(for: personality, isBlocked: blocked)
            let h = groundY(x: spot.0, z: spot.1)
            let npc = NPCNode(personality: personality, position: SCNVector3(spot.0, h, spot.1))
            npc.configureWander(radius: 5.5, groundY: { [weak self] x, z in
                self?.groundY(x: x, z: z) ?? 0
            }, isBlocked: { [weak self] x, z in
                guard let self else { return true }
                // Stay near camp pad and out of tents.
                if sqrt(x * x + z * z) > 11 { return true }
                return self.camp.isInsideTent(worldX: x, worldZ: z)
            })
            rootNode.addChildNode(npc)
            npcs.append(npc)
        }

        for personality: NPCPersonality in [.wanderer, .lost] {
            var pos = SCNVector3(40, 0, 40)
            for _ in 0..<40 {
                let wx = rng.nextFloat() * voxelWorld.totalSize - half
                let wz = rng.nextFloat() * voxelWorld.totalSize - half
                if sqrt(wx * wx + wz * wz) < 35 { continue }
                if blocked(wx, wz) { continue }
                let h = groundY(x: wx, z: wz)
                if h < VoxelWorldGenerator(seed: worldSeed).campSurfaceMeters + 3 {
                    pos = SCNVector3(wx, h, wz)
                    break
                }
            }
            let npc = NPCNode(personality: personality, position: pos)
            npc.configureWander(radius: 9, groundY: { [weak self] x, z in
                self?.groundY(x: x, z: z) ?? 0
            }, isBlocked: { [weak self] x, z in
                self?.camp.isInsideTent(worldX: x, worldZ: z) ?? false
            })
            rootNode.addChildNode(npc)
            npcs.append(npc)
        }
    }

    private func randomCampSpot(rng: inout SeededRandom,
                                isBlocked: (Float, Float) -> Bool) -> (Float, Float)? {
        for _ in 0..<50 {
            let angle = rng.nextFloat() * Float.pi * 2
            let dist = 3.5 + rng.nextFloat() * 6.5
            let wx = cos(angle) * dist
            let wz = sin(angle) * dist
            if isBlocked(wx, wz) { continue }
            // Keep clear of other already-spawned NPCs
            let tooClose = npcs.contains {
                let dx = $0.position.x - wx
                let dz = $0.position.z - wz
                return dx * dx + dz * dz < 2.8 * 2.8
            }
            if tooClose { continue }
            return (wx, wz)
        }
        return nil
    }

    private func openCampFallback(for personality: NPCPersonality,
                                  isBlocked: (Float, Float) -> Bool) -> (Float, Float) {
        let candidates: [(Float, Float)] = [
            (-4.0, 2.5), (5.0, 1.5), (2.0, -5.0),
            (4.5, -4.0), (-5.0, 4.0), (1.0, 5.5),
        ]
        for c in candidates where !isBlocked(c.0, c.1) {
            return c
        }
        switch personality {
        case .elder:    return (-4.0, 2.5)
        case .child:    return (5.0, 1.5)
        case .merchant: return (2.0, -5.0)
        default:        return (4.0, 4.0)
        }
    }

    // MARK: - Physics

    private func setupPhysics() {
        physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        physicsWorld.contactDelegate = self
    }

    // MARK: - Player movement

    private var moveInput: SIMD2<Float> = .zero
    private var isRunning = false
    private var verticalVelocity: Float = 0
    private var isGrounded = true
    private let moveSpeed: Float = 5.5
    private let runMultiplier: Float = 1.7
    private let jumpSpeed: Float = 7.2
    private let gravity: Float = 22
    private let turnSpeed: Float = 10.0
    private let moveDeadzone: Float = 0.08
    /// Auto-hop onto ledges up to this height (≈1 block).
    private let maxAutoStepUp: Float = 1.15
    /// Ignore tiny height noise.
    private let heightEpsilon: Float = 0.12

    func setMoveInput(dx: Float, dy: Float) {
        var input = SIMD2<Float>(dx, dy)
        let mag = simd_length(input)
        if mag > 1 {
            input /= mag
        }
        moveInput = input
    }

    func setRunning(_ running: Bool) {
        isRunning = running
    }

    func jump() {
        guard isGrounded, !isInWater else { return }
        beginAirborne(velocity: jumpSpeed)
    }

    private func beginAirborne(velocity: Float) {
        verticalVelocity = velocity
        isGrounded = false
        playerNode?.playJumpAnimation()
    }

    func update(deltaTime: Float) {
        guard !isBuildingWorld, playerNode != nil else { return }
        let dt = max(0, min(deltaTime, 1.0 / 20.0))
        toolTime += dt
        campDrainAccumulator += dt
        if campDrainAccumulator >= campDrainInterval, let camp {
            campDrainAccumulator -= campDrainInterval
            let level = camp.drainWater(amount: campDrainAmount)
            onCampDrained?(level)
        }
        applyMovement(deltaTime: dt)
        updateNPCs(deltaTime: dt)
        updateWater(deltaTime: dt)
        updateTools()
        checkProximity()
        checkBarrelProximity()
        syncCameraFollow()
        resolveCameraCollision(deltaTime: dt)
    }

    private func updateNPCs(deltaTime: Float) {
        for npc in npcs {
            npc.updateWander(deltaTime: deltaTime)
        }
    }

    private func applyMovement(deltaTime: Float) {
        guard let playerNode else { return }

        let inputLen = simd_length(moveInput)
        var nextX = playerNode.position.x
        var nextZ = playerNode.position.z
        let prevX = nextX
        let prevZ = nextZ

        if inputLen > moveDeadzone {
            let yaw = cameraArmNode.eulerAngles.y
            let sinY = sin(yaw)
            let cosY = cos(yaw)
            let forward = SIMD2<Float>(-sinY, -cosY)
            let right   = SIMD2<Float>( cosY, -sinY)

            let desired = right * moveInput.x + forward * moveInput.y
            let desiredLen = simd_length(desired)
            if desiredLen > 0.0001 {
                let dir = desired / desiredLen

                let waterMul: Float = isInWater ? 0.52 : 1.0
                let carryMul: Float = toolRig?.isCarryingWater == true ? 0.85 : 1.0
                let runMul: Float = (isRunning && !isInWater) ? runMultiplier : 1.0
                let speed = moveSpeed * min(inputLen, 1) * waterMul * carryMul * runMul
                playerHorizontalSpeed = speed
                let step = dir * speed * deltaTime
                nextX += step.x
                nextZ += step.y

                let targetYaw = atan2(dir.x, dir.y)
                let delta = shortestAngle(from: playerNode.eulerAngles.y, to: targetYaw)
                let maxTurn = turnSpeed * deltaTime
                playerNode.eulerAngles.y += max(-maxTurn, min(maxTurn, delta))
                playerNode.setWalking(true)
            } else {
                playerHorizontalSpeed = 0
                playerNode.setWalking(false)
            }
        } else {
            playerHorizontalSpeed = 0
            playerNode.setWalking(false)
        }

        if let camp {
            let bodyY = playerNode.position.y + 0.7
            let resolved = camp.resolvePlayerXZ(
                from: SIMD2(prevX, prevZ),
                to: SIMD2(nextX, nextZ),
                worldY: bodyY,
                radius: playerCollisionRadius
            )
            nextX = resolved.x
            nextZ = resolved.y
        }

        let yOff: Float = isInWater ? -0.08 : 0.01
        let groundAtNext = groundY(x: nextX, z: nextZ) + yOff
        let groundAtPrev = groundY(x: prevX, z: prevZ) + yOff
        var nextY = playerNode.position.y

        if isInWater {
            verticalVelocity = 0
            if !isGrounded {
                isGrounded = true
                playerNode.landFromJump()
            }
            nextY = groundAtNext
            playerNode.position = SCNVector3(nextX, nextY, nextZ)
            return
        }

        // Auto step-up / walk-off while grounded
        if isGrounded {
            let rise = groundAtNext - nextY
            let drop = nextY - groundAtNext

            if rise > heightEpsilon {
                if rise <= maxAutoStepUp {
                    // Hop onto the higher block
                    let hop = sqrt(max(0, 2 * gravity * rise)) + 1.2
                    beginAirborne(velocity: hop)
                } else {
                    // Wall — cancel horizontal move
                    nextX = prevX
                    nextZ = prevZ
                    nextY = groundAtPrev
                    playerNode.position = SCNVector3(nextX, nextY, nextZ)
                    return
                }
            } else if drop > heightEpsilon {
                // Step / fall down — leave ground and play jump pose
                beginAirborne(velocity: 0)
            } else {
                nextY = groundAtNext
                playerNode.position = SCNVector3(nextX, nextY, nextZ)
                return
            }
        }

        // Airborne integration
        verticalVelocity -= gravity * deltaTime
        nextY += verticalVelocity * deltaTime

        let landY = groundY(x: nextX, z: nextZ) + yOff
        if nextY <= landY, verticalVelocity <= 0 {
            nextY = landY
            verticalVelocity = 0
            isGrounded = true
            playerNode.landFromJump()
        }

        playerNode.position = SCNVector3(nextX, nextY, nextZ)
    }

    private func updateWater(deltaTime: Float) {
        guard let playerNode else { return }
        var inside = false
        var canCollect = false
        for water in waterBodies {
            let id = ObjectIdentifier(water)
            if var timer = oasisRefillTimers[id] {
                timer -= deltaTime
                if timer <= 0 {
                    oasisRefillTimers.removeValue(forKey: id)
                    depletedWaterBodies.remove(id)
                    water.setDepleted(false)
                } else {
                    oasisRefillTimers[id] = timer
                }
            }
            let isDepleted = depletedWaterBodies.contains(id)
            water.update(
                deltaTime: deltaTime,
                playerWorldPosition: playerNode.position,
                playerSpeed: playerHorizontalSpeed
            )
            if water.contains(worldPosition: playerNode.position) {
                inside = true
                if !isDepleted && !(toolRig?.isCarryingWater == true) { canCollect = true }
            }
        }
        isInWater = inside
        if canCollect != wasNearCollectableWater {
            wasNearCollectableWater = canCollect
            onNearWater?(canCollect)
        }
    }

    private func updateTools() {
        guard let playerNode, let toolRig else { return }

        if toolRig.hasCompass, let nearest = nearestOasisDirection() {
            toolRig.updateCompass(playerYaw: playerNode.eulerAngles.y, directionXZ: nearest)
        }

        if toolRig.hasDetector {
            toolRig.updateDetector(signal: nearestWaterSignal(), time: toolTime)
        }
    }

    private func nearestOasisDirection() -> SIMD2<Float>? {
        guard let playerNode, !oases.isEmpty else { return nil }
        var best: OasisInfo?
        var bestDist = Float.greatestFiniteMagnitude
        for oasis in oases {
            let dx = oasis.position.x - playerNode.position.x
            let dz = oasis.position.z - playerNode.position.z
            let d = dx * dx + dz * dz
            if d < bestDist {
                bestDist = d
                best = oasis
            }
        }
        guard let best else { return nil }
        let dx = best.position.x - playerNode.position.x
        let dz = best.position.z - playerNode.position.z
        let len = sqrt(dx * dx + dz * dz)
        guard len > 0.001 else { return nil }
        return SIMD2<Float>(dx / len, dz / len)
    }

    private func nearestWaterSignal() -> Float {
        guard let playerNode else { return 0 }
        var best = Float.greatestFiniteMagnitude
        for oasis in oases {
            let dx = oasis.position.x - playerNode.position.x
            let dz = oasis.position.z - playerNode.position.z
            let dist = max(0, sqrt(dx * dx + dz * dz) - oasis.radius)
            best = min(best, dist)
        }
        if best >= 90 { return 0 }
        if best <= 5 { return 1 }
        return 1 - (best - 5) / 85
    }

    private func shortestAngle(from a: Float, to b: Float) -> Float {
        var diff = b - a
        while diff > .pi  { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return diff
    }

    func rotateCamera(yawDelta: Float, pitchDelta: Float = 0) {
        cameraArmNode.eulerAngles.y -= yawDelta
        cameraPitch = max(cameraPitchMin, min(cameraPitchMax, cameraPitch + pitchDelta))
        cameraPitchNode.eulerAngles.x = cameraPitch
        // Keep collision progressive while orbiting (approx one display frame).
        resolveCameraCollision(deltaTime: 1.0 / 60.0)
    }

    /// Backward-compatible yaw-only helper.
    func rotateCamera(by delta: Float) {
        rotateCamera(yawDelta: delta, pitchDelta: 0)
    }

    // MARK: - Water carry / deliver

    @discardableResult
    func tryCollectWater(enteredBody: OasisWaterNode? = nil) -> Bool {
        guard let toolRig, !toolRig.isCarryingWater, let playerNode else { return false }
        let body = enteredBody ?? waterBodies.first {
            $0.contains(worldPosition: playerNode.position) &&
            !depletedWaterBodies.contains(ObjectIdentifier($0))
        }
        guard let body, !depletedWaterBodies.contains(ObjectIdentifier(body)) else { return false }

        toolRig.setCarryingWater(true)
        let id = ObjectIdentifier(body)
        depletedWaterBodies.insert(id)
        oasisRefillTimers[id] = oasisRefillTime
        body.setDepleted(true)
        onWaterCollected?()
        return true
    }

    func giveWaterToNPC(_ npc: NPCNode) {
        guard let toolRig, toolRig.isCarryingWater else { return }
        toolRig.setCarryingWater(false)
        npcs.removeAll { $0.npcID == npc.npcID }
        npc.completeTask()
        onWaterGivenToNPC?(npc)
    }

    @discardableResult
    func tryDeliverWater() -> Bool {
        guard let toolRig, let camp, let playerNode else { return false }
        guard toolRig.isCarryingWater else { return false }
        guard camp.canDeliver(at: playerNode.position) else { return false }

        toolRig.setCarryingWater(false)
        let level = camp.deliverWater()
        deliveryCount += 1

        var unlockedCompass = false
        var unlockedDetector = false
        if !toolRig.hasCompass {
            toolRig.setCompassUnlocked(true)
            unlockedCompass = true
        }
        if !toolRig.hasDetector, deliveryCount >= 3 {
            toolRig.setDetectorUnlocked(true)
            unlockedDetector = true
        }

        onWaterDelivered?(level, unlockedCompass, unlockedDetector)
        return true
    }

    var canDeliverNow: Bool {
        guard let toolRig, let camp, let playerNode else { return false }
        return toolRig.isCarryingWater && camp.canDeliver(at: playerNode.position)
    }

    var isCarryingWater: Bool { toolRig?.isCarryingWater == true }

    // MARK: - Proximity

    private func checkProximity() {
        guard let playerPos = playerNode?.position else { return }

        for npc in npcs where !npc.task.isCompleted {
            let dx = npc.position.x - playerPos.x
            let dz = npc.position.z - playerPos.z
            let dist = sqrt(dx*dx + dz*dz)
            if dist < npc.interactionRadius {
                onNPCProximity?(npc)
            }
        }

        for oasis in oases {
            let dx = oasis.position.x - playerPos.x
            let dz = oasis.position.z - playerPos.z
            let dist = sqrt(dx*dx + dz*dz)
            if dist < oasis.radius + 1.0 {
                onOasisReached?(oasis)
            }
        }
    }

    private func checkBarrelProximity() {
        let near = canDeliverNow
        if near != wasNearBarrel {
            wasNearBarrel = near
            onNearBarrel?(near)
        }
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
    }
}
