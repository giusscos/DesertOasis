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
/// Uses the same `OasisWaterNode` pool as wild oases; props stay outside this radius.
final class CampOasisGrowthNode: SCNNode {

    /// Finished pool radius in metres — keep barrel / sign / trough outside this.
    static let poolRadius: Float = 2.5

    private(set) var stage: OasisGrowthStage = .barren
    /// Progress within the current stage toward the next (0…1).
    private(set) var progress: Float = 0

    private let bankNode = SCNNode()
    private let wetPatch = SCNNode()
    private var poolWater: OasisWaterNode?
    private var plantNodes: [SCNNode] = []
    private var palmNodes: [SCNNode] = []

    /// Water taken from the barrel per irrigation tick.
    static let waterPerTick: Float = 0.018
    /// Progress gained per irrigation tick.
    static let progressPerTick: Float = 0.085

    override init() {
        super.init()
        name = "camp_oasis_growth"
        buildBank()
        buildWetPatch()
        buildPlants()
        buildPalms()
        applyVisual(animated: false)
    }

    required init?(coder: NSCoder) { nil }

    /// Builds the wild-style voxel water pool once the camp knows its world position.
    func attachPool(worldX: Float, worldZ: Float) {
        poolWater?.removeFromParentNode()
        let water = OasisWaterNode(
            radius: Self.poolRadius,
            oasisWorldX: worldX,
            oasisWorldZ: worldZ
        )
        water.name = "camp_oasis_water"
        addChildNode(water)
        poolWater = water
        applyVisual(animated: false)
    }

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

    /// Drive pool waves (visual only — not registered as a collectable wild oasis).
    func updateWater(deltaTime: Float, playerWorldPosition: SCNVector3, playerSpeed: Float) {
        guard stage >= .puddle, let poolWater, !poolWater.isHidden else { return }
        _ = poolWater.update(
            deltaTime: deltaTime,
            playerWorldPosition: playerWorldPosition,
            playerSpeed: playerSpeed
        )
    }

    // MARK: - Visuals

    private func buildBank() {
        let r = Self.poolRadius
        let geo = SCNCylinder(radius: CGFloat(r * 1.22), height: 0.12)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.72, green: 0.58, blue: 0.38, alpha: 1)
        mat.lightingModel = .lambert
        geo.firstMaterial = mat
        bankNode.geometry = geo
        bankNode.position = SCNVector3(0, 0.01, 0)
        bankNode.isHidden = true
        addChildNode(bankNode)
    }

    private func buildWetPatch() {
        let r = Self.poolRadius
        let wetGeo = SCNCylinder(radius: CGFloat(r * 1.05), height: 0.04)
        let wetMat = SCNMaterial()
        wetMat.diffuse.contents = UIColor(red: 0.42, green: 0.32, blue: 0.20, alpha: 1)
        wetMat.lightingModel = .lambert
        wetGeo.firstMaterial = wetMat
        wetPatch.geometry = wetGeo
        wetPatch.position = SCNVector3(0, 0.04, 0)
        wetPatch.isHidden = true
        addChildNode(wetPatch)
    }

    private func buildPlants() {
        let r = Self.poolRadius
        let plantAngles: [Float] = [0.35, 1.2, 2.1, 3.5, 4.3, 5.4]
        for (i, angle) in plantAngles.enumerated() {
            let dist = r * 1.12
            let plant = makePlant()
            plant.name = "growth_plant_\(i)"
            plant.position = SCNVector3(cos(angle) * dist, 0, sin(angle) * dist)
            plant.isHidden = true
            plant.scale = SCNVector3(0.01, 0.01, 0.01)
            addChildNode(plant)
            plantNodes.append(plant)
        }
    }

    private func buildPalms() {
        let r = Self.poolRadius
        // Rim palms outside the pool — same placement idea as wild oases.
        let palmSpecs: [(Float, Float, Float)] = [
            (0.20, r * 1.32, 0.9),
            (1.10, r * 1.40, 0.75),
            (2.20, r * 1.34, 1.05),
            (3.45, r * 1.42, 0.85),
            (4.55, r * 1.36, 1.15),
            (5.45, r * 1.38, 0.7),
        ]
        for (i, spec) in palmSpecs.enumerated() {
            let palm = makePalm()
            palm.name = "growth_palm_\(i)"
            palm.position = SCNVector3(cos(spec.0) * spec.1, 0, sin(spec.0) * spec.1)
            palm.eulerAngles.y = spec.2
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
        palm.scale = SCNVector3(0.85, 0.85, 0.85)
        return palm
    }

    private func applyVisual(animated: Bool) {
        let bankVisible = stage >= .damp
        let bankScale: Float = stage == .damp ? 0.55 + progress * 0.35
            : stage == .puddle ? 0.9 + progress * 0.12
            : 1.0
        setNode(bankNode, visible: bankVisible, scale: bankScale, animated: animated, flattenY: true)

        let wetVisible = stage >= .damp
        let wetScale = stage == .damp ? 0.5 + progress * 0.35
            : stage == .puddle ? 0.9 + progress * 0.1
            : 1.0
        setNode(wetPatch, visible: wetVisible, scale: wetScale, animated: animated, flattenY: true)

        let waterVisible = stage >= .puddle
        if let poolWater {
            let applyWater = {
                poolWater.isHidden = !waterVisible
                // Grow from a small puddle up to full wild-pool size.
                let s: Float
                switch self.stage {
                case .puddle: s = 0.35 + self.progress * 0.4
                case .pond:   s = 0.75 + self.progress * 0.25
                case .lush:   s = 1.0
                case .flourishing: s = 1.0
                default: s = 0.01
                }
                poolWater.scale = SCNVector3(s, 1, s)
                poolWater.setDepleted(!waterVisible)
            }
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.85
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                applyWater()
                SCNTransaction.commit()
            } else {
                applyWater()
            }
        }

        let plantVisible = stage >= .pond
        let plantScale: Float
        switch stage {
        case .pond: plantScale = 0.4 + progress * 0.6
        case .lush: plantScale = 1.0
        case .flourishing: plantScale = 1.15
        default: plantScale = 0.01
        }
        for plant in plantNodes {
            setNode(plant, visible: plantVisible, scale: plantScale, animated: animated)
        }

        let palmVisible = stage >= .lush || (stage == .pond && progress > 0.55)
        let palmScale: Float
        if stage == .flourishing {
            palmScale = 1.0
        } else if stage == .lush {
            palmScale = 0.72 + progress * 0.28
        } else if stage == .pond && progress > 0.55 {
            palmScale = (progress - 0.55) / 0.45 * 0.55
        } else {
            palmScale = 0.01
        }
        for (i, palm) in palmNodes.enumerated() {
            let extra = i >= 4
            let show = palmVisible && palmScale > 0.05 && (!extra || stage >= .flourishing)
            let scale = extra && stage == .flourishing ? palmScale * 0.88 : palmScale
            setNode(palm, visible: show, scale: max(0.01, scale), animated: animated)
        }
    }

    private func setNode(_ node: SCNNode,
                         visible: Bool,
                         scale: Float,
                         animated: Bool,
                         flattenY: Bool = false) {
        let sy = flattenY ? max(0.2, scale * 0.35) : max(0.15, scale)
        let apply = {
            node.isHidden = !visible
            node.scale = SCNVector3(scale, sy, scale)
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
