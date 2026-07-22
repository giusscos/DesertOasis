import SceneKit
import UIKit

/// Home camp: player tent, neighbour tents, and the shared water barrel.
final class CampNode: SCNNode {

    private(set) var barrelNode: SCNNode!
    private var waterSurface: SCNNode!
    private(set) var fillLevel: Float = 0

    let interactionRadius: Float = 3.5
    /// How much one bucket delivery raises the camp store (0…1).
    static let deliveryAmount: Float = 0.12

    // MARK: - Init

    init(groundHeight: Float, generator: DesertGenerator) {
        super.init()
        name = "camp"
        position = SCNVector3(0, groundHeight, 0)
        buildTents(generator: generator)
        buildBarrel()
        buildCampfire()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Public

    func setFillLevel(_ level: Float) {
        fillLevel = max(0, min(1, level))
        waterSurface.scale.y = max(0.02, fillLevel)
        waterSurface.position.y = 0.08 + fillLevel * 0.95
        waterSurface.isHidden = fillLevel < 0.01
    }

    /// Returns true if the world position is within the barrel interaction zone.
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

    // MARK: - Build

    private func buildTents(generator: DesertGenerator) {
        // Player tent — larger, facing outward
        let playerTent = makeTent(scale: 0.42)
        playerTent.position = SCNVector3(0, 0, 2.5)
        playerTent.eulerAngles.y = Float.pi
        addChildNode(playerTent)

        // Neighbour tents around the clearing
        let neighbourOffsets: [(Float, Float, Float)] = [
            (-8.5, -3.0, 0.6),
            (9.0, -2.0, -0.9),
            (-5.5, -9.0, 2.2),
        ]
        for (i, offset) in neighbourOffsets.enumerated() {
            let tent = makeTent(scale: 0.32)
            let wx = offset.0
            let wz = offset.1
            // Slight ground follow relative to camp origin
            let worldH = generator.height(atWorldX: wx, worldZ: wz)
            let localY = worldH - position.y
            tent.position = SCNVector3(wx, localY, wz)
            tent.eulerAngles.y = offset.2
            tent.name = "neighbour_tent_\(i)"
            addChildNode(tent)
        }
    }

    private func makeTent(scale: Float) -> SCNNode {
        let tent = AssetLoader.loadProp("lobby_tent")
        tent.scale = SCNVector3(scale, scale, scale)
        return tent
    }

    private func buildBarrel() {
        barrelNode = SCNNode()
        barrelNode.name = "water_barrel"
        barrelNode.position = SCNVector3(3.2, 0, -1.5)

        // Wooden cylinder body
        let body = SCNCylinder(radius: 0.48, height: 1.15)
        let wood = SCNMaterial()
        wood.diffuse.contents = UIColor(red: 0.45, green: 0.32, blue: 0.18, alpha: 1)
        wood.lightingModel = .lambert
        body.materials = [wood]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position.y = 0.58
        barrelNode.addChildNode(bodyNode)

        // Iron bands
        let bandMat = SCNMaterial()
        bandMat.diffuse.contents = UIColor(white: 0.25, alpha: 1)
        bandMat.metalness.contents = 0.6
        bandMat.roughness.contents = 0.45
        for y: Float in [0.25, 0.58, 0.92] {
            let band = SCNNode(geometry: SCNCylinder(radius: 0.50, height: 0.06))
            band.geometry?.firstMaterial = bandMat
            band.position.y = y
            barrelNode.addChildNode(band)
        }

        // Inner water surface (scaled by fill level)
        let waterGeom = SCNCylinder(radius: 0.42, height: 1.0)
        let waterMat = SCNMaterial()
        waterMat.diffuse.contents = UIColor(red: 0.20, green: 0.55, blue: 0.75, alpha: 0.85)
        waterMat.transparency = 0.85
        waterMat.lightingModel = .constant
        waterGeom.firstMaterial = waterMat
        waterSurface = SCNNode(geometry: waterGeom)
        waterSurface.name = "water_surface"
        waterSurface.position.y = 0.08
        waterSurface.scale.y = 0.02
        waterSurface.isHidden = true
        barrelNode.addChildNode(waterSurface)

        // Fill-point marker (for future pour FX)
        let fillPoint = SCNNode()
        fillPoint.name = "fill_point"
        fillPoint.position.y = 1.2
        barrelNode.addChildNode(fillPoint)

        addChildNode(barrelNode)
    }

    private func buildCampfire() {
        let fire = SCNNode()
        fire.name = "campfire"
        fire.position = SCNVector3(-1.5, 0, -2.0)

        let stoneMat = SCNMaterial()
        stoneMat.diffuse.contents = UIColor(white: 0.45, alpha: 1)
        for i in 0..<6 {
            let angle = Float(i) / 6.0 * Float.pi * 2
            let stone = SCNNode(geometry: SCNSphere(radius: 0.12))
            stone.geometry?.firstMaterial = stoneMat
            stone.position = SCNVector3(cos(angle) * 0.45, 0.08, sin(angle) * 0.45)
            stone.scale = SCNVector3(1, 0.6, 1)
            fire.addChildNode(stone)
        }

        let logMat = SCNMaterial()
        logMat.diffuse.contents = UIColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 1)
        for angle: Float in [0, Float.pi / 2] {
            let log = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.7))
            log.geometry?.firstMaterial = logMat
            log.eulerAngles = SCNVector3(0, angle, Float.pi / 2)
            log.position.y = 0.1
            fire.addChildNode(log)
        }

        let ember = SCNNode(geometry: SCNSphere(radius: 0.18))
        let emberMat = SCNMaterial()
        emberMat.diffuse.contents = UIColor(red: 1.0, green: 0.35, blue: 0.05, alpha: 1)
        emberMat.emission.contents = UIColor(red: 1.0, green: 0.40, blue: 0.08, alpha: 1)
        emberMat.emission.intensity = 0.55
        emberMat.lightingModel = .constant
        ember.geometry?.firstMaterial = emberMat
        ember.position.y = 0.12
        ember.scale = SCNVector3(1, 0.45, 1)
        ember.name = "embers"
        fire.addChildNode(ember)

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 1)
        light.intensity = 280
        light.attenuationEndDistance = 12
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position.y = 0.5
        fire.addChildNode(lightNode)

        addChildNode(fire)
    }
}
