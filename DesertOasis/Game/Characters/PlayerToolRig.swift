import SceneKit
import UIKit

/// Tools built as MagicaVoxel-style unit-cube sculptures.
final class PlayerToolRig: SCNNode {

    private(set) var bucketNode: SCNNode!
    private var bucketWater: SCNNode!
    private(set) var compassNode: SCNNode!
    private var compassNeedle: SCNNode!
    private(set) var detectorNode: SCNNode!
    private var detectorGauge: SCNNode!
    private var detectorLamp: SCNNode!

    private(set) var isCarryingWater = false
    private(set) var hasCompass = false
    private(set) var hasDetector = false

    private static var uf: Float { VoxelMetrics.unit }

    override init() {
        super.init()
        name = "tool_rig"
        buildBucket()
        buildCompass()
        buildDetector()
        setCarryingWater(false)
        setCompassUnlocked(false)
        setDetectorUnlocked(false)
    }

    required init?(coder: NSCoder) { nil }

    func setCarryingWater(_ carrying: Bool) {
        isCarryingWater = carrying
        bucketWater.isHidden = !carrying
        if let band = bucketNode.childNode(withName: "bucket_band", recursively: true) {
            band.geometry?.firstMaterial?.diffuse.contents =
                carrying
                ? UIColor(red: 0.25, green: 0.45, blue: 0.70, alpha: 1)
                : UIColor(white: 0.3, alpha: 1)
        }
    }

    func setCompassUnlocked(_ unlocked: Bool) {
        hasCompass = unlocked
        compassNode.isHidden = !unlocked
    }

    func setDetectorUnlocked(_ unlocked: Bool) {
        hasDetector = unlocked
        detectorNode.isHidden = !unlocked
    }

    func updateCompass(playerYaw: Float, directionXZ: SIMD2<Float>) {
        guard hasCompass, simd_length(directionXZ) > 0.001 else { return }
        let worldBearing = atan2(directionXZ.x, directionXZ.y)
        compassNeedle.eulerAngles.y = worldBearing - playerYaw
    }

    func updateDetector(signal: Float, time: Float) {
        guard hasDetector else { return }
        let s = max(0, min(1, signal))
        detectorGauge.eulerAngles.z = s * (Float.pi / 2)
        let pulse = 0.25 + s * (0.55 + 0.2 * sin(time * (4 + s * 10)))
        detectorLamp.geometry?.firstMaterial?.emission.intensity = CGFloat(pulse)
    }

    private func buildBucket() {
        bucketNode = SCNNode()
        bucketNode.name = "prop_bucket"
        // Slung on the player's back (+Z is forward)
        bucketNode.position = SCNVector3(0, 0.92, -0.34)
        bucketNode.eulerAngles.x = 0.18

        let u = Self.uf
        let s = VoxelSculpture(sizeX: 8, sizeY: 8, sizeZ: 8,
                               origin: SIMD3<Float>(-4, 0, -4) * u)
        s.fillTube(c0: 4, c1: 4, a0: 1, a1: 6, outerR: 3.2, innerR: 2.2, type: .wood)
        s.fillCylinder(c0: 4, c1: 4, a0: 0, a1: 1, radius: 3.0, type: .wood)
        // Rim
        s.fillTube(c0: 4, c1: 4, a0: 6, a1: 7, outerR: 3.4, innerR: 2.2, type: .darkWood)
        bucketNode.addChildNode(s.makeNode(name: "bucket_body"))

        let bandS = VoxelSculpture(sizeX: 8, sizeY: 2, sizeZ: 8,
                                   origin: SIMD3<Float>(-4, 0, -4) * u)
        bandS.fillTube(c0: 4, c1: 4, a0: 0, a1: 1, outerR: 3.5, innerR: 3.0, type: .iron)
        let band = bandS.makeNode(name: "bucket_band")
        band.position.y = 0.18
        bucketNode.addChildNode(band)

        let handleS = VoxelSculpture(sizeX: 8, sizeY: 5, sizeZ: 2,
                                     origin: SIMD3<Float>(-4, 0, -1) * u)
        for x in 0..<8 {
            let y = Int(4.0 * sin(Float(x) / 7.0 * Float.pi))
            handleS.set(x, y, 0, .darkWood)
            handleS.set(x, max(0, y - 1), 0, .darkWood)
        }
        let handle = handleS.makeNode(name: "handle")
        handle.position.y = 0.38
        bucketNode.addChildNode(handle)

        // Shoulder straps so the bucket reads as carried on the back
        let strapS = VoxelSculpture(sizeX: 10, sizeY: 8, sizeZ: 2,
                                    origin: SIMD3<Float>(-5, 0, -1) * u)
        for y in 0..<8 {
            strapS.set(1, y, 0, .darkWood)
            strapS.set(2, y, 0, .darkWood)
            strapS.set(7, y, 0, .darkWood)
            strapS.set(8, y, 0, .darkWood)
        }
        let straps = strapS.makeNode(name: "bucket_straps")
        straps.position = SCNVector3(0, 0.12, 0.12)
        bucketNode.addChildNode(straps)

        let waterS = VoxelSculpture(sizeX: 6, sizeY: 3, sizeZ: 6,
                                    origin: SIMD3<Float>(-3, 0, -3) * u)
        waterS.fillCylinder(c0: 3, c1: 3, a0: 0, a1: 2, radius: 2.4, type: .water)
        bucketWater = waterS.makeNode(name: "water_fill")
        bucketWater.position.y = 0.1
        bucketNode.addChildNode(bucketWater)

        addChildNode(bucketNode)
    }

    private func buildCompass() {
        compassNode = SCNNode()
        compassNode.name = "prop_water_compass"
        compassNode.position = SCNVector3(-0.32, 0.85, 0.18)
        compassNode.eulerAngles.x = -0.35

        let u = Self.uf
        let bodyS = VoxelSculpture(sizeX: 6, sizeY: 2, sizeZ: 6,
                                   origin: SIMD3<Float>(-3, 0, -3) * u)
        bodyS.fillCylinder(c0: 3, c1: 3, a0: 0, a1: 1, radius: 2.6, type: .brass)
        compassNode.addChildNode(bodyS.makeNode(name: "body"))

        let dialS = VoxelSculpture(sizeX: 5, sizeY: 1, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, 0, -2.5) * u)
        dialS.fillCylinder(c0: 2.5, c1: 2.5, a0: 0, a1: 0, radius: 2.2, type: .canvas)
        let dial = dialS.makeNode(name: "dial") { _ in
            UIColor(red: 0.90, green: 0.85, blue: 0.70, alpha: 1)
        }
        dial.position.y = 0.04
        compassNode.addChildNode(dial)

        compassNeedle = SCNNode()
        compassNeedle.name = "needle"
        let needleS = VoxelSculpture(sizeX: 1, sizeY: 1, sizeZ: 4,
                                     origin: SIMD3<Float>(-0.5, 0, 0) * u)
        needleS.fillBox(x0: 0, y0: 0, z0: 0, x1: 0, y1: 0, z1: 3, type: .iron)
        let needle = needleS.makeNode(name: "needle_mesh") { _ in
            UIColor(red: 0.75, green: 0.12, blue: 0.10, alpha: 1)
        }
        needle.position.z = 0.02
        compassNeedle.addChildNode(needle)
        compassNeedle.position.y = 0.05
        compassNode.addChildNode(compassNeedle)

        addChildNode(compassNode)
    }

    private func buildDetector() {
        detectorNode = SCNNode()
        detectorNode.name = "prop_water_detector"
        detectorNode.position = SCNVector3(0.42, 0.95, -0.05)
        detectorNode.eulerAngles.z = -0.4

        let u = Self.uf
        let gripS = VoxelSculpture(sizeX: 3, sizeY: 6, sizeZ: 3,
                                   origin: SIMD3<Float>(-1.5, 0, -1.5) * u)
        gripS.fillCylinder(c0: 1.5, c1: 1.5, a0: 0, a1: 5, radius: 1.1, type: .darkWood)
        let grip = gripS.makeNode(name: "grip")
        grip.position.y = 0.02
        detectorNode.addChildNode(grip)

        let dishS = VoxelSculpture(sizeX: 6, sizeY: 2, sizeZ: 6,
                                   origin: SIMD3<Float>(-3, 0, -3) * u)
        dishS.fillCylinder(c0: 3, c1: 3, a0: 0, a1: 1, radius: 2.6, type: .brass)
        let dish = dishS.makeNode(name: "dish")
        dish.position = SCNVector3(0, 0.22, 0.04)
        detectorNode.addChildNode(dish)

        detectorGauge = SCNNode()
        detectorGauge.name = "gauge_needle"
        let gS = VoxelSculpture(sizeX: 1, sizeY: 3, sizeZ: 1,
                                origin: SIMD3<Float>(-0.5, 0, -0.5) * u)
        gS.fillBox(x0: 0, y0: 0, z0: 0, x1: 0, y1: 2, z1: 0, type: .iron)
        let gNeedle = gS.makeNode(name: "g_mesh") { _ in UIColor.red }
        gNeedle.position.y = 0.02
        detectorGauge.addChildNode(gNeedle)
        detectorGauge.position = SCNVector3(0, 0.12, 0.06)
        detectorNode.addChildNode(detectorGauge)

        let lampS = VoxelSculpture(sizeX: 2, sizeY: 2, sizeZ: 2,
                                   origin: SIMD3<Float>(-1, 0, -1) * u)
        lampS.fillSphere(cx: 1, cy: 1, cz: 1, r: 0.9, type: .brass)
        detectorLamp = lampS.makeNode(name: "lamp") { _ in
            UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)
        }
        detectorLamp.geometry?.firstMaterial?.emission.contents = UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1)
        detectorLamp.geometry?.firstMaterial?.emission.intensity = 0.25
        detectorLamp.geometry?.firstMaterial?.lightingModel = .constant
        detectorLamp.position = SCNVector3(0, 0.18, 0.02)
        detectorNode.addChildNode(detectorLamp)

        addChildNode(detectorNode)
    }
}
