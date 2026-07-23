import SceneKit
import UIKit

/// Visible sun, moon, and drifting clouds. Parent root tracks the player so discs stay
/// inside fog start distance and remain readable against `scene.background`.
final class SkyCelestials {

    let root = SCNNode()

    /// Distance from player — kept well inside typical sand-haze fog start.
    private let orbitRadius: Float = 140
    private let sunSize: CGFloat = 14
    private let moonSize: CGFloat = 9

    private weak var sunLightNode: SCNNode?
    private var sunDisc: SCNNode!
    private var moonDisc: SCNNode!
    private var sunMaterial: SCNMaterial!
    private var moonMaterial: SCNMaterial!

    private struct Cloud {
        let node: SCNNode
        let material: SCNMaterial
        var angle: Float
        var elevation: Float
        var radius: Float
        var drift: Float
        var bobPhase: Float
        var bobAmp: Float
        var baseAlpha: CGFloat
    }

    private var clouds: [Cloud] = []
    private var enabled = true
    private var elapsed: Float = 0

    // MARK: - Setup

    func attach(to sceneRoot: SCNNode, sunLightNode: SCNNode) {
        self.sunLightNode = sunLightNode
        root.name = "skyCelestials"
        sceneRoot.addChildNode(root)

        sunDisc = makeDisc(size: sunSize, texture: Self.softDiscImage(color: UIColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1), softness: 0.42))
        sunDisc.name = "sunDisc"
        sunMaterial = sunDisc.geometry?.firstMaterial
        // Directional light shines along local -Z; the source sits on +Z.
        sunDisc.position = SCNVector3(0, 0, orbitRadius)
        sunLightNode.addChildNode(sunDisc)

        moonDisc = makeDisc(size: moonSize, texture: Self.softDiscImage(color: UIColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1), softness: 0.38))
        moonDisc.name = "moonDisc"
        moonMaterial = moonDisc.geometry?.firstMaterial
        moonDisc.position = SCNVector3(0, 0, -orbitRadius)
        sunLightNode.addChildNode(moonDisc)

        buildClouds()
        applyEnabled()
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        applyEnabled()
    }

    // MARK: - Per-frame

    func update(playerPosition: SCNVector3, daylightFactor: Float, skyColor: UIColor, deltaTime: Float) {
        guard enabled else { return }
        elapsed += deltaTime

        // Keep the light node (and thus discs) centered on the player so fog stays mild.
        if let sunLightNode {
            sunLightNode.position = SCNVector3(playerPosition.x, playerPosition.y + 2, playerPosition.z)
        }
        root.position = SCNVector3(playerPosition.x, playerPosition.y, playerPosition.z)

        let sunAlpha = CGFloat(max(0, min(1, daylightFactor)))
        let moonAlpha = CGFloat(max(0, min(1, 1 - daylightFactor * 1.15)))
        sunMaterial?.transparency = 1 - sunAlpha
        moonMaterial?.transparency = 1 - moonAlpha
        sunDisc.isHidden = sunAlpha < 0.04
        moonDisc.isHidden = moonAlpha < 0.04

        // Warm cloud tint from sky; quieter at night.
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        skyColor.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        let warm = UIColor(
            red: min(1, sr * 0.35 + 0.75),
            green: min(1, sg * 0.35 + 0.72),
            blue: min(1, sb * 0.25 + 0.70),
            alpha: 1
        )
        let nightMul = 0.22 + 0.78 * CGFloat(daylightFactor)

        for i in clouds.indices {
            clouds[i].angle += clouds[i].drift * deltaTime
            let elev = clouds[i].elevation
            let r = clouds[i].radius
            let bob = sin(elapsed * 0.35 + clouds[i].bobPhase) * clouds[i].bobAmp
            let y = sin(elev) * r + bob
            let xz = cos(elev) * r
            let x = cos(clouds[i].angle) * xz
            let z = sin(clouds[i].angle) * xz
            clouds[i].node.position = SCNVector3(x, y, z)
            clouds[i].material.multiply.contents = warm
            clouds[i].material.transparency = 1 - (clouds[i].baseAlpha * nightMul)
        }
    }

    // MARK: - Private

    private func applyEnabled() {
        root.isHidden = !enabled
        sunDisc?.isHidden = !enabled
        moonDisc?.isHidden = !enabled
        if !enabled {
            // Leave light node where it is; only visuals hide.
            for c in clouds { c.node.isHidden = true }
        } else {
            for c in clouds { c.node.isHidden = false }
        }
    }

    private func buildClouds() {
        // High elevation keeps clouds in the sky dome, not near camp geometry.
        let specs: [(Float, Float, Float, Float, CGFloat, CGFloat)] = [
            // angle, elevation, radius, drift, width, height
            (0.2, 0.72, 155, 0.012, 28, 11),
            (1.1, 0.85, 162, 0.009, 34, 13),
            (2.0, 0.68, 148, 0.014, 24, 10),
            (2.8, 0.90, 168, 0.008, 38, 14),
            (3.7, 0.78, 158, 0.011, 30, 12),
            (4.5, 0.66, 150, 0.013, 26, 10),
            (5.3, 0.88, 165, 0.009, 36, 13),
            (5.9, 0.74, 160, 0.010, 25, 11),
        ]

        for (i, s) in specs.enumerated() {
            let plane = SCNPlane(width: s.4, height: s.5)
            let mat = skyMaterial(diffuse: Self.softCloudImage())
            mat.multiply.contents = UIColor.white
            plane.firstMaterial = mat

            let node = SCNNode(geometry: plane)
            node.name = "cloud_\(i)"
            node.castsShadow = false
            node.constraints = [SCNBillboardConstraint()]
            root.addChildNode(node)

            clouds.append(Cloud(
                node: node,
                material: mat,
                angle: s.0,
                elevation: s.1,
                radius: s.2,
                drift: s.3,
                bobPhase: Float(i) * 0.9,
                bobAmp: 0.8 + Float(i % 3) * 0.3,
                baseAlpha: 0.32 + CGFloat(i % 4) * 0.04
            ))
        }
    }

    private func makeDisc(size: CGFloat, texture: UIImage) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        plane.firstMaterial = skyMaterial(diffuse: texture)

        let node = SCNNode(geometry: plane)
        node.castsShadow = false
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    /// Unlit sky sprites that still depth-test so tents/terrain occlude them.
    private func skyMaterial(diffuse: Any) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = diffuse
        mat.transparencyMode = .aOne
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = true
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        return mat
    }

    // MARK: - Procedural textures

    private static func softDiscImage(color: UIColor, softness: CGFloat) -> UIImage {
        let dim: CGFloat = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
            let center = CGPoint(x: dim * 0.5, y: dim * 0.5)
            let maxR = dim * 0.48
            let steps = 24
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps - 1)
                let r = maxR * (1 - t * softness)
                let alpha = pow(1 - t, 1.6) * (i == 0 ? 1 : 0.85)
                color.withAlphaComponent(alpha).setFill()
                c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    private static func softCloudImage() -> UIImage {
        let w: CGFloat = 256
        let h: CGFloat = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: w, height: h))
            let blobs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.30, 0.55, 0.28, 0.55),
                (0.48, 0.48, 0.34, 0.62),
                (0.66, 0.55, 0.30, 0.50),
                (0.40, 0.62, 0.22, 0.40),
                (0.58, 0.62, 0.24, 0.42),
            ]
            for b in blobs {
                let rx = b.2 * w
                let ry = b.3 * h
                let rect = CGRect(x: b.0 * w - rx, y: b.1 * h - ry, width: rx * 2, height: ry * 2)
                UIColor.white.withAlphaComponent(0.55).setFill()
                c.fillEllipse(in: rect)
            }
            // Soft falloff via second translucent pass
            for b in blobs {
                let rx = b.2 * w * 1.15
                let ry = b.3 * h * 1.15
                let rect = CGRect(x: b.0 * w - rx, y: b.1 * h - ry, width: rx * 2, height: ry * 2)
                UIColor.white.withAlphaComponent(0.22).setFill()
                c.fillEllipse(in: rect)
            }
        }
    }
}
