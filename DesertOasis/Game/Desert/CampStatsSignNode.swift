import SceneKit
import UIKit

/// Weathered wood post + plank beside camp, showing that camp's barrel and oasis stats.
final class CampStatsSignNode: SCNNode {

    private let titleNode = SCNNode()
    private let waterNode = SCNNode()
    private let oasisNode = SCNNode()
    private let progressNode = SCNNode()

    private let title: String
    private var lastWater: Float = -1
    private var lastStage: OasisGrowthStage?
    private var lastProgress: Float = -1

    /// Parchment face in local metres (must match `buildWood`).
    private let faceWidth: Float = 2.65
    private let faceBottom: Float = 1.40
    private let faceTop: Float = 2.95
    private let faceZ: Float = 0.28

    private let titleScale: Float = 0.030
    private let bodyScale: Float = 0.026

    init(title: String) {
        self.title = title
        super.init()
        name = "camp_stats_sign"
        buildWood()
        buildTextSlots()
        refresh(water: 0, stage: .barren, progress: 0)
    }

    required init?(coder: NSCoder) { nil }

    func refresh(water: Float, stage: OasisGrowthStage, progress: Float) {
        let w = max(0, min(1, water))
        let p = max(0, min(1, progress))
        guard w != lastWater || stage != lastStage || p != lastProgress else { return }
        lastWater = w
        lastStage = stage
        lastProgress = p

        let maxW = faceWidth * 0.86
        applyText(titleNode, string: title, color: carvedInk, scale: titleScale, maxWidth: maxW)
        applyText(waterNode, string: "Water  \(Int((w * 100).rounded()))%", color: waterInk(for: w), scale: bodyScale, maxWidth: maxW)
        applyText(oasisNode, string: stage.displayName, color: oasisInk, scale: bodyScale, maxWidth: maxW)
        let bar = progressBar(for: stage == .lush ? 1 : p)
        let suffix = stage == .lush ? "done" : "\(Int((p * 100).rounded()))%"
        applyText(progressNode, string: "\(bar) \(suffix)", color: carvedInk, scale: bodyScale, maxWidth: maxW)
    }

    // MARK: - Build

    private func buildWood() {
        let uf = VoxelMetrics.unit
        // ~3.25 m wide × ~3.4 m tall board on twin posts.
        let rootS = VoxelSculpture(sizeX: 54, sizeY: 56, sizeZ: 8,
                                   origin: SIMD3<Float>(-27, 0, -4) * uf)

        // Twin posts
        rootS.fillBox(x0: 6, y0: 0, z0: 3, x1: 10, y1: 48, z1: 5, type: .darkWood)
        rootS.fillBox(x0: 44, y0: 0, z0: 3, x1: 48, y1: 48, z1: 5, type: .darkWood)
        // Main plank
        rootS.fillBox(x0: 1, y0: 18, z0: 2, x1: 52, y1: 52, z1: 4, type: .wood)
        // Dark frame
        rootS.fillBox(x0: 1, y0: 18, z0: 2, x1: 52, y1: 21, z1: 4, type: .darkWood)
        rootS.fillBox(x0: 1, y0: 49, z0: 2, x1: 52, y1: 52, z1: 4, type: .darkWood)
        rootS.fillBox(x0: 1, y0: 18, z0: 2, x1: 4, y1: 52, z1: 4, type: .darkWood)
        rootS.fillBox(x0: 50, y0: 18, z0: 2, x1: 52, y1: 52, z1: 4, type: .darkWood)
        // Light parchment inset (y 21…49 → 1.31…3.06 m)
        rootS.fillBox(x0: 5, y0: 22, z0: 4, x1: 48, y1: 48, z1: 5, type: .canvas)

        addChildNode(rootS.makeNode(name: "sign_wood"))
    }

    private func buildTextSlots() {
        // Four evenly spaced lines with padding inside the parchment.
        let pad: Float = 0.22
        let top = faceTop - pad
        let bottom = faceBottom + pad
        let step = (top - bottom) / 3
        place(titleNode, at: SCNVector3(0, top, faceZ))
        place(waterNode, at: SCNVector3(0, top - step, faceZ))
        place(oasisNode, at: SCNVector3(0, top - step * 2, faceZ))
        place(progressNode, at: SCNVector3(0, bottom, faceZ))
    }

    private func place(_ node: SCNNode, at position: SCNVector3) {
        node.position = position
        addChildNode(node)
    }

    private func applyText(_ node: SCNNode,
                           string: String,
                           color: UIColor,
                           scale: Float,
                           maxWidth: Float) {
        node.childNodes.forEach { $0.removeFromParentNode() }

        let geo = SCNText(string: string, extrusionDepth: 1.0)
        geo.font = UIFont(name: "AvenirNext-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
        geo.flatness = 0.12
        geo.chamferRadius = 0.06
        geo.alignmentMode = CATextLayerAlignmentMode.center.rawValue

        let front = SCNMaterial()
        front.diffuse.contents = color
        front.emission.contents = color.withAlphaComponent(0.12)
        front.lightingModel = .constant
        let side = SCNMaterial()
        side.diffuse.contents = color.withAlphaComponent(0.65)
        side.lightingModel = .constant
        geo.materials = [front, side]

        let text = SCNNode(geometry: geo)
        let (minB, maxB) = geo.boundingBox
        var s = scale
        let rawW = Float(maxB.x - minB.x) * s
        if rawW > maxWidth, rawW > 0.001 {
            s *= maxWidth / rawW
        }
        text.scale = SCNVector3(s, s, s)

        // Pivot at glyph centre so slot Y is the visual midline.
        let midX = (minB.x + maxB.x) * 0.5
        let midY = (minB.y + maxB.y) * 0.5
        text.pivot = SCNMatrix4MakeTranslation(midX, midY, 0)
        text.position = SCNVector3Zero
        node.addChildNode(text)
    }

    private func progressBar(for value: Float) -> String {
        let filled = Int((value * 6).rounded())
        let clamped = max(0, min(6, filled))
        return String(repeating: "=", count: clamped)
            + String(repeating: "-", count: 6 - clamped)
    }

    private var carvedInk: UIColor {
        UIColor(red: 0.16, green: 0.10, blue: 0.06, alpha: 1)
    }

    private var oasisInk: UIColor {
        UIColor(red: 0.10, green: 0.36, blue: 0.18, alpha: 1)
    }

    private func waterInk(for level: Float) -> UIColor {
        if level < 0.2 {
            return UIColor(red: 0.62, green: 0.18, blue: 0.10, alpha: 1)
        }
        return UIColor(red: 0.08, green: 0.32, blue: 0.58, alpha: 1)
    }
}
