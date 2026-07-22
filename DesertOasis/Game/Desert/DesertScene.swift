import SceneKit
import UIKit

final class DesertScene: SCNScene, SCNPhysicsContactDelegate {

    private(set) var playerNode: PlayerNode!
    private(set) var toolRig: PlayerToolRig!
    private(set) var camp: CampNode!
    private(set) var npcs: [NPCNode] = []
    private(set) var oases: [OasisInfo] = []
    private(set) var waterBodies: [OasisWaterNode] = []
    private var generator: DesertGenerator!

    let cameraNode = SCNNode()
    let cameraArmNode = SCNNode()   // follows player position; yaw is independent

    var onNPCProximity: ((NPCNode) -> Void)?
    var onOasisReached: ((OasisInfo) -> Void)?
    var onWaterCollected: (() -> Void)?
    var onWaterDelivered: ((Float, Bool, Bool) -> Void)? // level, unlockedCompass, unlockedDetector
    var onNearBarrel: ((Bool) -> Void)? // canDeliver

    private var playerHorizontalSpeed: Float = 0
    private var isInWater = false
    private var toolTime: Float = 0
    private var wasNearBarrel = false
    private var deliveryCount = 0

    // MARK: - Build

    func build(from slot: SaveSlot) {
        generator = DesertGenerator(seed: slot.desertSeed)
        background.contents = skyboxGradient()
        deliveryCount = slot.waterDeliveries

        setupLighting()
        let terrain = generator.buildTerrainNode()
        rootNode.addChildNode(terrain)

        let campGround = generator.height(atWorldX: 0, worldZ: 0)
        camp = CampNode(groundHeight: campGround, generator: generator)
        camp.setFillLevel(slot.campWaterLevel)
        rootNode.addChildNode(camp)

        oases = generator.generateOases(count: 6)
        waterBodies.removeAll()
        for oasis in oases {
            let oasisNode = generator.buildOasisNode(info: oasis)
            rootNode.addChildNode(oasisNode)
            if let water = oasisNode.childNode(withName: "oasis_water", recursively: false) as? OasisWaterNode {
                waterBodies.append(water)
            }
        }

        let props = generator.scatterProps(around: oases)
        rootNode.addChildNode(props)

        spawnNPCs()
        setupPlayer(slot: slot)
        setupCamera()
        setupSky()
        setupPhysics()
    }

    // MARK: - Lighting

    private func setupLighting() {
        // Sun
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

        // Sky ambient
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.60, green: 0.70, blue: 0.85, alpha: 1)
        ambient.intensity = 350
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)
    }

    // MARK: - Sky

    private func setupSky() {
        // Simple sky dome using a large inverted sphere
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

        // New games / origin → camp spawn; otherwise resume saved position
        let spawnX = slot.playerPositionX
        let spawnZ = slot.playerPositionZ
        let nearOrigin = abs(spawnX) < 0.5 && abs(spawnZ) < 0.5
        let x = nearOrigin ? 1.5 : spawnX
        let z = nearOrigin ? 0.5 : spawnZ
        let groundH = generator.height(atWorldX: x, worldZ: z)
        playerNode.position = SCNVector3(x, groundH + 0.01, z)
        rootNode.addChildNode(playerNode)

        toolRig = PlayerToolRig()
        toolRig.setCarryingWater(slot.isCarryingWater)
        toolRig.setCompassUnlocked(slot.hasWaterCompass)
        toolRig.setDetectorUnlocked(slot.hasWaterDetector)
        playerNode.addChildNode(toolRig)
    }

    // MARK: - Camera (third person, follows player)

    private let cameraLookTarget = SCNNode()

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 65
        camera.zNear = 0.2
        camera.zFar = 500
        cameraNode.camera = camera

        // Look target rides with the player; the arm does not — otherwise turning
        // the character also yaws the camera and camera-relative move breaks.
        cameraLookTarget.position = SCNVector3(0, 1.2, 0)
        playerNode.addChildNode(cameraLookTarget)

        cameraNode.position = SCNVector3(0, 2.8, 7.5)
        let lookAt = SCNLookAtConstraint(target: cameraLookTarget)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        rootNode.addChildNode(cameraArmNode)
        cameraArmNode.addChildNode(cameraNode)
        syncCameraFollow()
    }

    private func syncCameraFollow() {
        guard let playerNode else { return }
        cameraArmNode.position = playerNode.position
    }

    // MARK: - NPCs

    private func spawnNPCs() {
        var rng = SeededRandom(seed: generator.seed &+ 12345)
        let half = generator.totalSize * 0.5

        // Neighbours at camp
        let campNeighbours: [(NPCPersonality, SCNVector3)] = [
            (.elder, SCNVector3(-6.5, 0, -4.0)),
            (.child, SCNVector3(7.0, 0, -5.5)),
            (.merchant, SCNVector3(-2.0, 0, -8.0)),
        ]
        for (personality, offset) in campNeighbours {
            let wx = offset.x
            let wz = offset.z
            let h = generator.height(atWorldX: wx, worldZ: wz)
            let npc = NPCNode(personality: personality, position: SCNVector3(wx, h, wz))
            rootNode.addChildNode(npc)
            npcs.append(npc)
        }

        // Travellers out in the desert
        for personality: NPCPersonality in [.wanderer, .lost] {
            var pos = SCNVector3(40, 0, 40)
            for _ in 0..<25 {
                let wx = rng.nextFloat() * generator.totalSize - half
                let wz = rng.nextFloat() * generator.totalSize - half
                if sqrt(wx * wx + wz * wz) < 35 { continue }
                let h = generator.height(atWorldX: wx, worldZ: wz)
                if h < generator.heightScale * 0.65 {
                    pos = SCNVector3(wx, h, wz)
                    break
                }
            }
            let npc = NPCNode(personality: personality, position: pos)
            rootNode.addChildNode(npc)
            npcs.append(npc)
        }
    }

    // MARK: - Physics

    private func setupPhysics() {
        physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        physicsWorld.contactDelegate = self
    }

    // MARK: - Player movement

    /// Stick axes: x = strafe (right +), y = forward (stick-up +). Magnitude ≤ 1.
    private var moveInput: SIMD2<Float> = .zero
    private let moveSpeed: Float = 5.5
    private let turnSpeed: Float = 10.0
    private let moveDeadzone: Float = 0.08

    /// Called from the joystick; motion is applied in `update(deltaTime:)`.
    func setMoveInput(dx: Float, dy: Float) {
        var input = SIMD2<Float>(dx, dy)
        let mag = simd_length(input)
        if mag > 1 {
            input /= mag
        }
        moveInput = input
    }

    /// Per-frame tick from the SCNView renderer.
    func update(deltaTime: Float) {
        guard playerNode != nil else { return }
        let dt = max(0, min(deltaTime, 1.0 / 20.0))
        toolTime += dt
        syncCameraFollow()
        applyMovement(deltaTime: dt)
        updateWater(deltaTime: dt)
        updateTools()
        checkProximity()
        checkBarrelProximity()
    }

    private func applyMovement(deltaTime: Float) {
        guard let playerNode else { return }

        let inputLen = simd_length(moveInput)
        guard inputLen > moveDeadzone else {
            playerHorizontalSpeed = 0
            playerNode.setWalking(false)
            // Keep feet sunk / grounded while idle
            let p = playerNode.position
            let groundH = generator.height(atWorldX: p.x, worldZ: p.z)
            let yOff: Float = isInWater ? -0.08 : 0.01
            playerNode.position = SCNVector3(p.x, groundH + yOff, p.z)
            return
        }

        // Arm yaw 0: camera sits on +Z looking toward −Z (into the scene).
        let yaw = cameraArmNode.eulerAngles.y
        let sinY = sin(yaw)
        let cosY = cos(yaw)
        let forward = SIMD2<Float>(-sinY, -cosY) // XZ
        let right   = SIMD2<Float>( cosY, -sinY)

        let desired = right * moveInput.x + forward * moveInput.y
        let desiredLen = simd_length(desired)
        guard desiredLen > 0.0001 else {
            playerHorizontalSpeed = 0
            playerNode.setWalking(false)
            return
        }
        let dir = desired / desiredLen

        // Wading is slower inside a pool; carrying a full bucket is a bit slower too
        let waterMul: Float = isInWater ? 0.52 : 1.0
        let carryMul: Float = toolRig?.isCarryingWater == true ? 0.85 : 1.0
        let speed = moveSpeed * min(inputLen, 1) * waterMul * carryMul
        playerHorizontalSpeed = speed
        let step = dir * speed * deltaTime

        let nextX = playerNode.position.x + step.x
        let nextZ = playerNode.position.z + step.y
        let groundH = generator.height(atWorldX: nextX, worldZ: nextZ)
        // Sink slightly while standing in water
        let yOff: Float = isInWater ? -0.08 : 0.01
        playerNode.position = SCNVector3(nextX, groundH + yOff, nextZ)

        // Face move direction (+Z is character forward after AssetLoader correction)
        let targetYaw = atan2(dir.x, dir.y)
        let delta = shortestAngle(from: playerNode.eulerAngles.y, to: targetYaw)
        let maxTurn = turnSpeed * deltaTime
        playerNode.eulerAngles.y += max(-maxTurn, min(maxTurn, delta))

        playerNode.setWalking(true)
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

    /// 0…1 based on distance to nearest oasis water edge.
    private func nearestWaterSignal() -> Float {
        guard let playerNode else { return 0 }
        var best = Float.greatestFiniteMagnitude
        for oasis in oases {
            let dx = oasis.position.x - playerNode.position.x
            let dz = oasis.position.z - playerNode.position.z
            let dist = max(0, sqrt(dx * dx + dz * dz) - oasis.radius)
            best = min(best, dist)
        }
        // Strong within ~40 m, fades out by ~90 m
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

    func rotateCamera(by delta: Float) {
        cameraArmNode.eulerAngles.y -= delta
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

    // MARK: - Proximity checks

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

    // MARK: - SCNPhysicsContactDelegate

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // Contact handling reserved for future collectibles
    }
}
