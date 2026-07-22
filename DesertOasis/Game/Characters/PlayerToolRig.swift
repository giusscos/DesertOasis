import SceneKit
import UIKit

/// Procedural placeholder tools until USDZ assets arrive.
/// Attached under the player; visibility / needle driven by DesertScene.
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

    // MARK: - State

    func setCarryingWater(_ carrying: Bool) {
        isCarryingWater = carrying
        bucketWater.isHidden = !carrying
        // Tint bucket bands when full
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

    /// Point compass needle toward a world-space XZ direction (normalized).
    func updateCompass(playerYaw: Float, directionXZ: SIMD2<Float>) {
        guard hasCompass, simd_length(directionXZ) > 0.001 else { return }
        let worldBearing = atan2(directionXZ.x, directionXZ.y)
        // Needle is in player space; cancel player yaw so it stays world-aligned
        compassNeedle.eulerAngles.y = worldBearing - playerYaw
    }

    /// Signal 0…1 drives gauge angle and lamp pulse.
    func updateDetector(signal: Float, time: Float) {
        guard hasDetector else { return }
        let s = max(0, min(1, signal))
        detectorGauge.eulerAngles.z = s * (Float.pi / 2)
        let pulse = 0.25 + s * (0.55 + 0.2 * sin(time * (4 + s * 10)))
        detectorLamp.geometry?.firstMaterial?.emission.intensity = CGFloat(pulse)
    }

    // MARK: - Build

    private func buildBucket() {
        bucketNode = SCNNode()
        bucketNode.name = "prop_bucket"
        // Right-hand side, hip height
        bucketNode.position = SCNVector3(0.38, 0.55, 0.05)

        let body = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 0.28))
        let wood = SCNMaterial()
        wood.diffuse.contents = UIColor(red: 0.50, green: 0.36, blue: 0.20, alpha: 1)
        wood.lightingModel = .lambert
        body.geometry?.firstMaterial = wood
        body.position.y = 0.14
        bucketNode.addChildNode(body)

        let band = SCNNode(geometry: SCNCylinder(radius: 0.125, height: 0.03))
        band.name = "bucket_band"
        band.geometry?.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(white: 0.3, alpha: 1)
            return m
        }()
        band.position.y = 0.1
        bucketNode.addChildNode(band)

        // Handle arch
        let handle = SCNNode(geometry: SCNTorus(ringRadius: 0.14, pipeRadius: 0.012))
        handle.geometry?.firstMaterial = wood
        handle.eulerAngles.x = Float.pi / 2
        handle.position.y = 0.30
        handle.name = "handle"
        bucketNode.addChildNode(handle)

        bucketWater = SCNNode(geometry: SCNCylinder(radius: 0.10, height: 0.18))
        let wMat = SCNMaterial()
        wMat.diffuse.contents = UIColor(red: 0.22, green: 0.55, blue: 0.78, alpha: 0.9)
        wMat.transparency = 0.9
        wMat.lightingModel = .constant
        bucketWater.geometry?.firstMaterial = wMat
        bucketWater.name = "water_fill"
        bucketWater.position.y = 0.12
        bucketNode.addChildNode(bucketWater)

        addChildNode(bucketNode)
    }

    private func buildCompass() {
        compassNode = SCNNode()
        compassNode.name = "prop_water_compass"
        compassNode.position = SCNVector3(-0.32, 0.85, 0.18)
        compassNode.eulerAngles.x = -0.35

        let body = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 0.03))
        let brass = SCNMaterial()
        brass.diffuse.contents = UIColor(red: 0.72, green: 0.55, blue: 0.22, alpha: 1)
        brass.metalness.contents = 0.7
        brass.roughness.contents = 0.35
        body.geometry?.firstMaterial = brass
        compassNode.addChildNode(body)

        let dial = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.008))
        dial.name = "dial"
        dial.geometry?.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.90, green: 0.85, blue: 0.70, alpha: 1)
            return m
        }()
        dial.position.y = 0.02
        compassNode.addChildNode(dial)

        compassNeedle = SCNNode()
        compassNeedle.name = "needle"
        let needleGeom = SCNCone(topRadius: 0, bottomRadius: 0.012, height: 0.11)
        let needleMat = SCNMaterial()
        needleMat.diffuse.contents = UIColor(red: 0.75, green: 0.12, blue: 0.10, alpha: 1)
        needleGeom.firstMaterial = needleMat
        let needleMesh = SCNNode(geometry: needleGeom)
        needleMesh.eulerAngles.x = -Float.pi / 2
        needleMesh.position.z = 0.04
        compassNeedle.addChildNode(needleMesh)
        compassNeedle.position.y = 0.03
        compassNode.addChildNode(compassNeedle)

        addChildNode(compassNode)
    }

    private func buildDetector() {
        detectorNode = SCNNode()
        detectorNode.name = "prop_water_detector"
        detectorNode.position = SCNVector3(0.42, 0.95, -0.05)
        detectorNode.eulerAngles.z = -0.4

        let grip = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 0.22))
        grip.geometry?.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.40, green: 0.28, blue: 0.15, alpha: 1)
            return m
        }()
        grip.position.y = 0.05
        detectorNode.addChildNode(grip)

        let dish = SCNNode(geometry: SCNCone(topRadius: 0.02, bottomRadius: 0.09, height: 0.08))
        dish.name = "dish"
        dish.geometry?.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.65, green: 0.48, blue: 0.20, alpha: 1)
            m.metalness.contents = 0.5
            return m
        }()
        dish.eulerAngles.x = Float.pi / 2
        dish.position = SCNVector3(0, 0.22, 0.06)
        detectorNode.addChildNode(dish)

        // Gauge housing
        let gaugeBody = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 0.02))
        gaugeBody.geometry?.firstMaterial = grip.geometry?.firstMaterial
        gaugeBody.eulerAngles.x = Float.pi / 2
        gaugeBody.position = SCNVector3(0, 0.12, 0.05)
        detectorNode.addChildNode(gaugeBody)

        detectorGauge = SCNNode()
        detectorGauge.name = "gauge_needle"
        let gNeedle = SCNNode(geometry: SCNBox(width: 0.008, height: 0.035, length: 0.004, chamferRadius: 0))
        gNeedle.geometry?.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.red
            return m
        }()
        gNeedle.position.y = 0.015
        detectorGauge.addChildNode(gNeedle)
        detectorGauge.position = SCNVector3(0, 0.12, 0.06)
        detectorNode.addChildNode(detectorGauge)

        detectorLamp = SCNNode(geometry: SCNSphere(radius: 0.02))
        detectorLamp.name = "lamp"
        let lampMat = SCNMaterial()
        lampMat.diffuse.contents = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)
        lampMat.emission.contents = UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1)
        lampMat.emission.intensity = 0.25
        lampMat.lightingModel = .constant
        detectorLamp.geometry?.firstMaterial = lampMat
        detectorLamp.position = SCNVector3(0, 0.18, 0.02)
        detectorNode.addChildNode(detectorLamp)

        addChildNode(detectorNode)
    }
}
