import SceneKit

/// Central loader for all USDZ assets.
/// Props are cached in memory; characters are loaded fresh each call (animations are grafted in).
enum AssetLoader {

    // MARK: - Character loading (README pattern)

    /// Loads the base character USDZ and grafts per-action animation files onto the returned node.
    /// The model is wrapped so callers can set yaw/position without undoing the Z-up correction.
    static func loadCharacter(_ name: String, actions: [String]) -> SCNNode {
        guard let scene = SCNScene(named: "\(name).usdz") else {
            return placeholderNode()
        }
        let model = scene.rootNode.clone()
        applyZUpCorrection(model)

        let container = SCNNode()
        container.name = name
        container.addChildNode(model)

        for action in actions {
            guard let animScene = SCNScene(named: "\(name)_\(action).usdz") else { continue }
            animScene.rootNode.enumerateHierarchy { child, _ in
                for key in child.animationKeys {
                    if let player = child.animationPlayer(forKey: key) {
                        player.stop()
                        container.addAnimationPlayer(player, forKey: action)
                    }
                }
            }
        }
        return container
    }

    // MARK: - Prop loading (cached clone)

    private static var propCache: [String: SCNNode] = [:]

    /// Returns a cloned instance of the named prop USDZ. The first load caches the template.
    /// Wrapped like characters so callers can set yaw/position without undoing the Z-up correction.
    static func loadProp(_ name: String) -> SCNNode {
        if let template = propCache[name] {
            return template.clone()
        }
        guard let scene = SCNScene(named: "\(name).usdz") else {
            return placeholderNode()
        }
        let model = scene.rootNode.clone()
        applyZUpCorrection(model)

        let template = SCNNode()
        template.name = name
        template.addChildNode(model)
        propCache[name] = template
        return template.clone()
    }

    /// Loads a prop and starts a named animation on it (e.g. palm sway, tumbleweed roll).
    static func loadAnimatedProp(_ name: String, animationKey: String) -> SCNNode {
        let node = loadProp(name)
        node.animationPlayer(forKey: animationKey)?.play()
        return node
    }

    // MARK: - Orientation

    /// Blender exports these USDZs with `upAxis = Z`, but SceneKit's `SCNScene(named:)`
    /// does not convert that to Y-up — assets load lying on their side.
    /// `-90°` pitch stands them up; `180°` yaw maps Blender +Y (front/entrance) to SceneKit +Z.
    private static func applyZUpCorrection(_ node: SCNNode) {
        node.eulerAngles = SCNVector3(-Float.pi / 2, Float.pi, 0)
    }

    // MARK: - Fallback

    private static func placeholderNode() -> SCNNode {
        let sphere = SCNNode(geometry: SCNSphere(radius: 0.3))
        sphere.geometry?.firstMaterial?.diffuse.contents = UIColor.magenta
        return sphere
    }
}
