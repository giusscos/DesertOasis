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
    private let cameraPitchMin: Float = -1.05
    private let cameraPitchMax: Float = 0.40

    var onNPCProximity: ((NPCNode) -> Void)?
    var onOasisReached: ((OasisInfo) -> Void)?
    var onWaterCollected: (() -> Void)?
    var onWaterDelivered: ((Float, Bool, Bool) -> Void)?
    var onNearBarrel: ((Bool) -> Void)?

    private var playerHorizontalSpeed: Float = 0
    private var isInWater = false
    private var toolTime: Float = 0
    private var wasNearBarrel = false
    private var deliveryCount = 0

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
            let water = OasisWaterNode(radius: oasis.radius)
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
    }

    private func syncCameraFollow() {
        guard let playerNode else { return }
        cameraArmNode.position = playerNode.position
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
        syncCameraFollow()
        applyMovement(deltaTime: dt)
        updateNPCs(deltaTime: dt)
        updateWater(deltaTime: dt)
        updateTools()
        checkProximity()
        checkBarrelProximity()
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
        for water in waterBodies {
            let entered = water.update(
                deltaTime: deltaTime,
                playerWorldPosition: playerNode.position,
                playerSpeed: playerHorizontalSpeed
            )
            if water.contains(worldPosition: playerNode.position) {
                inside = true
            }
            if entered {
                tryCollectWater()
            }
        }
        isInWater = inside
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
    }

    /// Backward-compatible yaw-only helper.
    func rotateCamera(by delta: Float) {
        rotateCamera(yawDelta: delta, pitchDelta: 0)
    }

    // MARK: - Water carry / deliver

    @discardableResult
    func tryCollectWater() -> Bool {
        guard let toolRig, !toolRig.isCarryingWater else { return false }
        guard isInWater || waterBodies.contains(where: {
            $0.contains(worldPosition: playerNode.position)
        }) else { return false }

        toolRig.setCarryingWater(true)
        onWaterCollected?()
        return true
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
