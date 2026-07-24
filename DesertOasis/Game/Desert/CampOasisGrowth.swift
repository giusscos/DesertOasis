import SceneKit
import UIKit

/// Visual stages of a camp-grown oasis, fed by barrel water that NPCs irrigate over time.
enum OasisGrowthStage: Int, Codable, CaseIterable, Comparable {
    case barren = 0
    case damp = 1
    case puddle = 2
    case pond = 3
    case lush = 4
    case flourishing = 5

    static func < (lhs: OasisGrowthStage, rhs: OasisGrowthStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .barren:       "Barren sand"
        case .damp:         "Damp earth"
        case .puddle:       "Tiny puddle"
        case .pond:         "Camp pond"
        case .lush:         "Living oasis"
        case .flourishing:  "Flourishing"
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
        guard stage != .flourishing else {
            progress = 1
            return false
        }
        progress = min(1, progress + amount)
        var advanced = false
        if progress >= 1, let next = stage.next {
            stage = next
            progress = stage == .flourishing ? 1 : 0
            advanced = true
        }
        applyVisual(animated: true)
        return advanced
    }

    var overallFraction: Float {
        let stages = Float(OasisGrowthStage.flourishing.rawValue)
        return (Float(stage.rawValue) + (stage == .flourishing ? 1 : progress)) / (stages + 1)
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
        waterMat.diffuse.contents = UIColor(red: 0.18, green: 0.52, blue: 0.72, alpha: 1)
        waterMat.transparency = 0.42
        waterMat.lightingModel = .blinn
        waterMat.specular.contents = UIColor(white: 1, alpha: 0.7)
        waterMat.shininess = 0.85
        waterMat.writesToDepthBuffer = false
        waterMat.shaderModifiers = [.surface: MetalMaterialShaders.waterSurface]
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
            (-1.8, -2.2, 1.1), (2.1, 2.0, -0.8),
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
        let palm = VoxelPropBuilder.palmTree()
        palm.scale = SCNVector3(0.72, 0.72, 0.72)
        return palm
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
        case .flourishing: waterScale = 1.7
        default:      waterScale = 0.01
        }
        setNode(waterDisc, visible: waterVisible, scale: waterScale, animated: animated)

        // Plants from pond
        let plantVisible = stage >= .pond
        let plantScale: Float
        switch stage {
        case .pond: plantScale = 0.35 + progress * 0.65
        case .lush: plantScale = 1.0
        case .flourishing: plantScale = 1.2
        default: plantScale = 0.01
        }
        for plant in plantNodes {
            setNode(plant, visible: plantVisible, scale: plantScale, animated: animated)
        }

        // Palms at lush+; extra palms only fully show when flourishing
        let palmVisible = stage >= .lush || (stage == .pond && progress > 0.7)
        let palmScale: Float
        if stage == .flourishing {
            palmScale = 1.05
        } else if stage == .lush {
            palmScale = 0.7 + progress * 0.3
        } else if stage == .pond && progress > 0.7 {
            palmScale = (progress - 0.7) / 0.3 * 0.55
        } else {
            palmScale = 0.01
        }
        for (i, palm) in palmNodes.enumerated() {
            let extra = i >= 3
            let show = palmVisible && palmScale > 0.05 && (!extra || stage >= .flourishing)
            let scale = extra && stage == .flourishing ? palmScale * 0.85 : palmScale
            setNode(palm, visible: show, scale: max(0.01, scale), animated: animated)
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
