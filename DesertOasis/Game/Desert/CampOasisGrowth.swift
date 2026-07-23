import SceneKit
import UIKit

/// Visual stages of a camp-grown oasis, fed by barrel water that NPCs irrigate over time.
enum OasisGrowthStage: Int, Codable, CaseIterable, Comparable {
    case barren = 0
    case damp = 1
    case puddle = 2
    case pond = 3
    case lush = 4

    static func < (lhs: OasisGrowthStage, rhs: OasisGrowthStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .barren: "Barren sand"
        case .damp:   "Damp earth"
        case .puddle: "Tiny puddle"
        case .pond:   "Camp pond"
        case .lush:   "Living oasis"
        }
    }

    var next: OasisGrowthStage? {
        OasisGrowthStage(rawValue: rawValue + 1)
    }
}

/// Procedural oasis that grows beside camp as NPCs spend barrel water.
final class CampOasisGrowthNode: SCNNode {

    private(set) var stage: OasisGrowthStage = .barren
    /// Progress within the current stage toward the next (0…1).
    private(set) var progress: Float = 0

    private let wetPatch = SCNNode()
    private let waterDisc = SCNNode()
    private var plantNodes: [SCNNode] = []
    private var palmNodes: [SCNNode] = []

    /// Water taken from the barrel per irrigation tick.
    static let waterPerTick: Float = 0.018
    /// Progress gained per irrigation tick.
    static let progressPerTick: Float = 0.085

    override init() {
        super.init()
        name = "camp_oasis_growth"
        buildVisuals()
        applyVisual(animated: false)
    }

    required init?(coder: NSCoder) { nil }

    func restore(stage: OasisGrowthStage, progress: Float) {
        self.stage = stage
        self.progress = max(0, min(1, progress))
        applyVisual(animated: false)
    }

    /// Called when NPCs irrigate. Returns true if the stage advanced.
    @discardableResult
    func addProgress(_ amount: Float) -> Bool {
        guard stage != .lush else {
            progress = 1
            return false
        }
        progress = min(1, progress + amount)
        var advanced = false
        if progress >= 1, let next = stage.next {
            stage = next
            progress = stage == .lush ? 1 : 0
            advanced = true
        }
        applyVisual(animated: true)
        return advanced
    }

    var overallFraction: Float {
        let stages = Float(OasisGrowthStage.lush.rawValue)
        return (Float(stage.rawValue) + (stage == .lush ? 1 : progress)) / (stages + 1)
    }

    // MARK: - Visuals

    private func buildVisuals() {
        let wetGeo = SCNCylinder(radius: 1.2, height: 0.04)
        let wetMat = SCNMaterial()
        wetMat.diffuse.contents = UIColor(red: 0.55, green: 0.42, blue: 0.28, alpha: 1)
        wetMat.lightingModel = .lambert
        wetGeo.firstMaterial = wetMat
        wetPatch.geometry = wetGeo
        wetPatch.position = SCNVector3(0, 0.02, 0)
        wetPatch.isHidden = true
        addChildNode(wetPatch)

        let waterGeo = SCNCylinder(radius: 1.0, height: 0.08)
        let waterMat = SCNMaterial()
        waterMat.diffuse.contents = UIColor(red: 0.22, green: 0.55, blue: 0.78, alpha: 0.78)
        waterMat.transparency = 0.72
        waterMat.lightingModel = .lambert
        waterGeo.firstMaterial = waterMat
        waterDisc.geometry = waterGeo
        waterDisc.position = SCNVector3(0, 0.05, 0)
        waterDisc.isHidden = true
        addChildNode(waterDisc)

        // Small shrubs / grass clumps
        let plantOffsets: [(Float, Float)] = [
            (-1.6, 0.4), (1.4, -0.6), (0.8, 1.5), (-1.1, -1.3), (1.8, 1.1),
        ]
        for (i, off) in plantOffsets.enumerated() {
            let plant = makePlant()
            plant.name = "growth_plant_\(i)"
            plant.position = SCNVector3(off.0, 0, off.1)
            plant.isHidden = true
            plant.scale = SCNVector3(0.01, 0.01, 0.01)
            addChildNode(plant)
            plantNodes.append(plant)
        }

        let palmOffsets: [(Float, Float, Float)] = [
            (-2.4, 0.2, 0.4), (2.6, -0.3, -0.5), (0.3, 2.5, 0.2),
        ]
        for (i, off) in palmOffsets.enumerated() {
            let palm = makePalm()
            palm.name = "growth_palm_\(i)"
            palm.position = SCNVector3(off.0, 0, off.1)
            palm.eulerAngles.y = off.2
            palm.isHidden = true
            palm.scale = SCNVector3(0.01, 0.01, 0.01)
            addChildNode(palm)
            palmNodes.append(palm)
        }
    }

    private func makePlant() -> SCNNode {
        let root = SCNNode()
        let s = VoxelSculpture(sizeX: 6, sizeY: 8, sizeZ: 6,
                               origin: SIMD3<Float>(-3, 0, -3) * VoxelMetrics.unit)
        s.fillCylinder(c0: 3, c1: 3, a0: 0, a1: 5, radius: 0.8, type: .cactus)
        s.fillSphere(cx: 3, cy: 6, cz: 3, r: 2.2, type: .leaf)
        root.addChildNode(s.makeNode(name: "plant_mesh"))
        return root
    }

    private func makePalm() -> SCNNode {
        let root = SCNNode()
        let s = VoxelSculpture(sizeX: 10, sizeY: 28, sizeZ: 10,
                               origin: SIMD3<Float>(-5, 0, -5) * VoxelMetrics.unit)
        s.fillCylinder(c0: 5, c1: 5, a0: 0, a1: 20, radius: 1.1, type: .wood)
        s.fillSphere(cx: 5, cy: 22, cz: 5, r: 3.5, type: .leaf)
        s.fillSphere(cx: 2, cy: 21, cz: 5, r: 2.4, type: .leaf)
        s.fillSphere(cx: 8, cy: 21, cz: 5, r: 2.4, type: .leaf)
        s.fillSphere(cx: 5, cy: 21, cz: 2, r: 2.4, type: .leaf)
        s.fillSphere(cx: 5, cy: 21, cz: 8, r: 2.4, type: .leaf)
        root.addChildNode(s.makeNode(name: "palm_mesh"))
        return root
    }

    private func applyVisual(animated: Bool) {

        // Wet patch from damp onward
        let wetVisible = stage >= .damp
        let wetScale = stage == .damp ? 0.6 + progress * 0.5
            : stage == .puddle ? 1.1 + progress * 0.3
            : stage >= .pond ? 1.6 : 0.01
        setNode(wetPatch, visible: wetVisible, scale: wetScale, animated: animated)

        // Water from puddle onward
        let waterVisible = stage >= .puddle
        let waterScale: Float
        switch stage {
        case .puddle: waterScale = 0.35 + progress * 0.45
        case .pond:   waterScale = 0.85 + progress * 0.45
        case .lush:   waterScale = 1.45
        default:      waterScale = 0.01
        }
        setNode(waterDisc, visible: waterVisible, scale: waterScale, animated: animated)

        // Plants from pond
        let plantVisible = stage >= .pond
        let plantScale: Float = stage == .pond ? 0.35 + progress * 0.65 : (stage == .lush ? 1.0 : 0.01)
        for plant in plantNodes {
            setNode(plant, visible: plantVisible, scale: plantScale, animated: animated)
        }

        // Palms at lush
        let palmVisible = stage >= .lush || (stage == .pond && progress > 0.7)
        let palmScale: Float
        if stage == .lush {
            palmScale = 0.7 + progress * 0.3
        } else if stage == .pond && progress > 0.7 {
            palmScale = (progress - 0.7) / 0.3 * 0.55
        } else {
            palmScale = 0.01
        }
        for palm in palmNodes {
            setNode(palm, visible: palmVisible && palmScale > 0.05, scale: max(0.01, palmScale), animated: animated)
        }

    }

    private func setNode(_ node: SCNNode, visible: Bool, scale: Float, animated: Bool) {
        let apply = {
            node.isHidden = !visible
            node.scale = SCNVector3(scale, max(0.15, scale * 0.85), scale)
        }
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.85
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            apply()
            SCNTransaction.commit()
        } else {
            apply()
        }
    }
}
