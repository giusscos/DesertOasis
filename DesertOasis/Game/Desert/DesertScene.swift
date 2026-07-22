import SceneKit
import UIKit

final class DesertScene: SCNScene, SCNPhysicsContactDelegate {

    private(set) var playerNode: PlayerNode!
    private(set) var npcs: [NPCNode] = []
    private(set) var oases: [OasisInfo] = []
    private var generator: DesertGenerator!

    let cameraNode = SCNNode()
    let cameraArmNode = SCNNode()   // parent of camera, attached to player

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

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 65
        camera.zNear = 0.2
        camera.zFar = 500
        cameraNode.camera = camera

        // Arm length and elevation
        cameraArmNode.position = SCNVector3(0, 1.0, 0)  // pivot above player head
        cameraNode.position = SCNVector3(0, 3.5, 8.0)   // offset behind/above
        cameraNode.look(at: SCNVector3(0, 0.8, 0))

        playerNode.addChildNode(cameraArmNode)
        cameraArmNode.addChildNode(cameraNode)
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

    private var moveDirection: SCNVector3 = .init(0, 0, 0)
    private var isMoving = false

    func setMoveInput(dx: Float, dz: Float) {
        guard let playerNode else { return }

        let mag = sqrt(dx * dx + dz * dz)
        isMoving = mag > 0.05

        if isMoving {
            let speed: Float = 5.0
            let nx = dx / mag; let nz = dz / mag

            // Rotate player toward movement direction (in camera space)
            let camYaw = cameraArmNode.eulerAngles.y
            let worldX = nx * cos(camYaw) + nz * sin(camYaw)
            let worldZ = -nx * sin(camYaw) + nz * cos(camYaw)

            let targetYaw = atan2(worldX, worldZ)
            let currentYaw = playerNode.eulerAngles.y
            let delta = shortestAngle(from: currentYaw, to: targetYaw)
            playerNode.eulerAngles.y += delta * 0.15

            // Move in world space
            let groundH = generator.height(atWorldX: playerNode.position.x + worldX * speed * 0.016,
                                            worldZ: playerNode.position.z + worldZ * speed * 0.016)
            playerNode.position.x += worldX * speed * 0.016
            playerNode.position.z += worldZ * speed * 0.016
            playerNode.position.y = groundH + 0.01
        }

        playerNode.setWalking(isMoving)
        checkProximity()
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
