import SceneKit
import UIKit

final class DesertScene: SCNScene, SCNPhysicsContactDelegate {

    private(set) var playerNode: PlayerNode!
    private(set) var npcs: [NPCNode] = []
    private(set) var oases: [OasisInfo] = []
    private var generator: DesertGenerator!

    let cameraNode = SCNNode()
    let cameraArmNode = SCNNode()   // follows player position; yaw is independent

    var onNPCProximity: ((NPCNode) -> Void)?
    var onOasisReached: ((OasisInfo) -> Void)?
    var onWaterFound: (() -> Void)?

    // MARK: - Build

    func build(from slot: SaveSlot) {
        generator = DesertGenerator(seed: slot.desertSeed)
        background.contents = skyboxGradient()

        setupLighting()
        let terrain = generator.buildTerrainNode()
        rootNode.addChildNode(terrain)

        oases = generator.generateOases(count: 6)
        for oasis in oases {
            rootNode.addChildNode(generator.buildOasisNode(info: oasis))
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
        let spawnX = slot.playerPositionX
        let spawnZ = slot.playerPositionZ
        let groundH = generator.height(atWorldX: spawnX, worldZ: spawnZ)
        playerNode.position = SCNVector3(spawnX, groundH + 0.01, spawnZ)
        rootNode.addChildNode(playerNode)
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
        let personalities = NPCPersonality.allCases
        var rng = SeededRandom(seed: generator.seed &+ 12345)
        let half = generator.totalSize * 0.5

        for personality in personalities {
            var pos = SCNVector3(0, 0, 0)
            for _ in 0..<20 {
                let wx = rng.nextFloat() * generator.totalSize - half
                let wz = rng.nextFloat() * generator.totalSize - half
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
        syncCameraFollow()
        applyMovement(deltaTime: dt)
        checkProximity()
    }

    private func applyMovement(deltaTime: Float) {
        guard let playerNode else { return }

        let inputLen = simd_length(moveInput)
        guard inputLen > moveDeadzone else {
            playerNode.setWalking(false)
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
            playerNode.setWalking(false)
            return
        }
        let dir = desired / desiredLen

        // Analog speed from stick magnitude
        let speed = moveSpeed * min(inputLen, 1)
        let step = dir * speed * deltaTime

        let nextX = playerNode.position.x + step.x
        let nextZ = playerNode.position.z + step.y
        let groundH = generator.height(atWorldX: nextX, worldZ: nextZ)
        playerNode.position = SCNVector3(nextX, groundH + 0.01, nextZ)

        // Face move direction (+Z is character forward after AssetLoader correction)
        let targetYaw = atan2(dir.x, dir.y)
        let delta = shortestAngle(from: playerNode.eulerAngles.y, to: targetYaw)
        let maxTurn = turnSpeed * deltaTime
        playerNode.eulerAngles.y += max(-maxTurn, min(maxTurn, delta))

        playerNode.setWalking(true)
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

    // MARK: - SCNPhysicsContactDelegate

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // Contact handling reserved for future collectibles
    }
}
