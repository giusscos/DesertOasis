import SceneKit
import UIKit

// MARK: - Camera state

enum LobbyCameraState {
    case title
    case slotSelection
    case characterSelection
    case settings
}

// MARK: - LobbyScene

final class LobbyScene: SCNScene {

    // Camera
    let cameraNode = SCNNode()
    private let cameraTargetNode = SCNNode()

    // Tappable nodes (populated from USDZ hierarchy)
    private(set) var diaryNodes: [SCNNode] = []
    private(set) var settingsZoneNode = SCNNode()

    // Lobby characters
    private var manNode: SCNNode!
    private var womanNode: SCNNode!

    /// Diaries that have already been opened.
    private var openedDiaries: Set<Int> = []

    /// Closed local pose for every animated hinge/page node (keyed by node name).
    private var diaryClosedPoses: [String: DiaryPose] = [:]

    /// Cover hinge open: ~22 frames @ 24 fps (pages are not played).
    private var diaryAnimDuration: TimeInterval { 22.0 / 24.0 }

    private struct DiaryPose {
        var position: SCNVector3
        var eulerAngles: SCNVector3
        var scale: SCNVector3

        static func capture(from node: SCNNode) -> DiaryPose {
            DiaryPose(position: node.position, eulerAngles: node.eulerAngles, scale: node.scale)
        }

        static func capturePresentation(from node: SCNNode) -> DiaryPose {
            let p = node.presentation
            return DiaryPose(position: p.position, eulerAngles: p.eulerAngles, scale: p.scale)
        }

        func apply(to node: SCNNode) {
            node.position = position
            node.eulerAngles = eulerAngles
            node.scale = scale
        }
    }

    override init() {
        super.init()
        buildScene()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Build

    private func buildScene() {
        background.contents = UIColor(white: 0.04, alpha: 1)
        setupLighting()
        setupFloor()
        setupTent()
        setupBed()
        setupTable()
        setupCharacters()
        setupCamera()
    }

    // MARK: - Lighting

    private func setupLighting() {
        // Warm ambient so canvas walls stay readable instead of falling to black
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.42, green: 0.34, blue: 0.26, alpha: 1)
        ambient.intensity = 180
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        // Cool moonlight through the open +Z entrance (rim on backs)
        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(red: 0.45, green: 0.55, blue: 0.78, alpha: 1)
        fill.intensity = 55
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi, 0)
        rootNode.addChildNode(fillNode)

        // Warm key under the hanging lantern
        let key = SCNLight()
        key.type = .omni
        key.color = UIColor(red: 1.0, green: 0.68, blue: 0.38, alpha: 1)
        key.intensity = 200
        key.attenuationStartDistance = 0.4
        key.attenuationEndDistance = 8
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0, 2.6, 0)
        rootNode.addChildNode(keyNode)

        // Soft floor bounce
        let bounce = SCNLight()
        bounce.type = .omni
        bounce.color = UIColor(red: 0.80, green: 0.60, blue: 0.40, alpha: 1)
        bounce.intensity = 60
        bounce.attenuationEndDistance = 7
        let bounceNode = SCNNode()
        bounceNode.light = bounce
        bounceNode.position = SCNVector3(0, 0.35, 0.5)
        rootNode.addChildNode(bounceNode)

        // Rear fill — lights the back canvas wall, bed, and table
        let rear = SCNLight()
        rear.type = .omni
        rear.color = UIColor(red: 1.0, green: 0.72, blue: 0.45, alpha: 1)
        rear.intensity = 140
        rear.attenuationStartDistance = 0.5
        rear.attenuationEndDistance = 7
        let rearNode = SCNNode()
        rearNode.light = rear
        rearNode.position = SCNVector3(0, 2.2, -3.2)
        rootNode.addChildNode(rearNode)

        // Bed-side wash
        let bedLight = SCNLight()
        bedLight.type = .omni
        bedLight.color = UIColor(red: 1.0, green: 0.65, blue: 0.35, alpha: 1)
        bedLight.intensity = 70
        bedLight.attenuationEndDistance = 5
        let bedLightNode = SCNNode()
        bedLightNode.light = bedLight
        bedLightNode.position = SCNVector3(-2.5, 1.6, -1.0)
        rootNode.addChildNode(bedLightNode)

        // Table-side wash
        let tableLight = SCNLight()
        tableLight.type = .omni
        tableLight.color = UIColor(red: 1.0, green: 0.70, blue: 0.42, alpha: 1)
        tableLight.intensity = 70
        tableLight.attenuationEndDistance = 5
        let tableLightNode = SCNNode()
        tableLightNode.light = tableLight
        tableLightNode.position = SCNVector3(2.0, 1.6, -1.0)
        rootNode.addChildNode(tableLightNode)
    }

    // MARK: - Floor

    private func setupFloor() {
        // Tent asset is shell-only; add a sand floor so the interior isn't a void
        let floor = SCNNode(geometry: SCNPlane(width: 10, height: 12))
        floor.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.62, green: 0.48, blue: 0.32, alpha: 1)
        floor.geometry?.firstMaterial?.roughness.contents = 0.95
        floor.geometry?.firstMaterial?.lightingModel = .physicallyBased
        floor.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        floor.position = SCNVector3(0, 0.01, 0)
        rootNode.addChildNode(floor)
    }

    // MARK: - Tent

    private func setupTent() {
        let tent = AssetLoader.loadProp("lobby_tent")
        // Tent origin is its floor centre; entrance faces +Z per README
        // Inner bounds ≈ 8 × 10 × 4 m (x × z × y)
        tent.position = SCNVector3(0, 0, 0)
        tent.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { mat in
                mat.isDoubleSided = true
                // USD lantern emission is HDR (~6, 3.3, 1) and blows out the interior
                if emissionIsLit(mat) {
                    mat.emission.contents = UIColor(red: 1.0, green: 0.50, blue: 0.18, alpha: 1)
                    mat.emission.intensity = 0.18
                }
            }
        }
        rootNode.addChildNode(tent)
    }

    private func emissionIsLit(_ mat: SCNMaterial) -> Bool {
        guard let color = mat.emission.contents as? UIColor else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r + g + b) > 0.05
    }

    // MARK: - Bed and diaries

    private func setupBed() {
        let bed = AssetLoader.loadProp("lobby_bed")
        // Place on the left side of the tent
        bed.position = SCNVector3(-3, 0, -1)
        rootNode.addChildNode(bed)

        // Grab diary nodes — named diary_0 / diary_1 / diary_2 in the USDZ
        diaryNodes = []
        for i in 0..<3 {
            if let diary = bed.childNode(withName: "diary_\(i)", recursively: true) {
                prepareDiaryClosed(diary)
                diaryNodes.append(diary)
            }
        }
    }

    /// Stop autoplaying USD open clips and freeze each diary at frame 0 (closed).
    private func prepareDiaryClosed(_ diary: SCNNode) {
        forEachAnimatedDiaryNode(in: diary) { node, player in
            player.speed = 1
            player.paused = false
            player.animation.isAppliedOnCompletion = false
            configureDiaryAnimation(player.animation)
            player.stop()
            configureDiaryAnimation(player.animation)

            if let name = node.name {
                diaryClosedPoses[name] = .capture(from: node)
            }
        }
    }

    private func configureDiaryAnimation(_ animation: SCNAnimation) {
        animation.usesSceneTimeBase = false
        animation.repeatCount = 0
        animation.autoreverses = false
        animation.isRemovedOnCompletion = false
        animation.isAppliedOnCompletion = true
    }

    private func forEachAnimatedDiaryNode(in root: SCNNode,
                                          _ body: (_ node: SCNNode, _ player: SCNAnimationPlayer) -> Void) {
        root.enumerateHierarchy { node, _ in
            for key in node.animationKeys {
                if let player = node.animationPlayer(forKey: key) {
                    body(node, player)
                }
            }
        }
    }

    // MARK: - Table and instruments

    private func setupTable() {
        let table = AssetLoader.loadProp("lobby_table")
        table.position = SCNVector3(2.2, 0, -1)
        // Keep AssetLoader's Z-up correction; yaw 90° only
        table.eulerAngles.y += Float.pi / -2
        // Name the root so the hit-test walk-up in LobbySceneView finds it
        table.name = "settings_zone"
        table.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { mat in
                if emissionIsLit(mat) {
                    mat.emission.contents = UIColor(red: 1.0, green: 0.50, blue: 0.18, alpha: 1)
                    mat.emission.intensity = 0.12
                }
            }
        }
        rootNode.addChildNode(table)
        settingsZoneNode = table

        // Start the hourglass sand-flow animation if present
        if let hourglass = table.childNode(withName: "node_hourglass", recursively: true) {
            hourglass.animationPlayer(forKey: hourglass.animationKeys.first ?? "")?.play()
        }
    }

    // MARK: - Characters

    /// Standing at the +Z entrance, facing out (backs toward the back-wall title camera).
    private let manExitPos   = SCNVector3(-0.55, 0, 3.2)
    private let womanExitPos = SCNVector3( 0.55, 0, 3.2)
    /// Yaw 0 = face +Z (out the entrance). Yaw π = face −Z (toward back-wall camera).
    private let exitFacingYaw: Float = 0
    private let cameraFacingYaw: Float = .pi

    private func setupCharacters() {
        manNode = AssetLoader.loadCharacter("player_man", actions: ["idle", "walk", "talk", "wave"])
        manNode.name = "character_man"
        manNode.position = manExitPos
        manNode.eulerAngles = SCNVector3(0, exitFacingYaw, 0)
        manNode.animationPlayer(forKey: "idle")?.play()
        rootNode.addChildNode(manNode)

        womanNode = AssetLoader.loadCharacter("player_woman", actions: ["idle", "walk", "talk", "wave"])
        womanNode.name = "character_woman"
        womanNode.position = womanExitPos
        womanNode.eulerAngles = SCNVector3(0, exitFacingYaw, 0)
        womanNode.animationPlayer(forKey: "idle")?.play()
        rootNode.addChildNode(womanNode)
    }

    /// Turns both characters to face the camera (for character selection).
    func presentCharactersForSelection(duration: TimeInterval = 1.0) {
        turnCharacters(toYaw: cameraFacingYaw, duration: duration)
    }

    /// Returns both characters to exit pose — backs to the interior camera.
    func resetCharactersToExit(duration: TimeInterval = 0.8) {
        turnCharacters(toYaw: exitFacingYaw, duration: duration)
    }

    private func turnCharacters(toYaw yaw: Float, duration: TimeInterval) {
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: duration)
        turn.timingMode = .easeInEaseOut
        manNode.removeAllActions()
        womanNode.removeAllActions()
        manNode.runAction(turn)
        womanNode.runAction(turn)
    }

    // MARK: - Camera

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 58
        camera.zNear = 0.1
        camera.zFar = 80
        camera.wantsHDR = true
        camera.bloomIntensity = 0.04
        camera.bloomThreshold = 1.5
        camera.minimumExposure = -0.8
        camera.maximumExposure = 0.4
        camera.whitePoint = 2.2
        camera.motionBlurIntensity = 0
        cameraNode.camera = camera
        cameraNode.position = titleCameraPos

        cameraTargetNode.position = titleTargetPos
        rootNode.addChildNode(cameraTargetNode)

        let constraint = SCNLookAtConstraint(target: cameraTargetNode)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]
        rootNode.addChildNode(cameraNode)
    }

    func animateCamera(to state: LobbyCameraState, completion: (() -> Void)? = nil) {
        let (camPos, targetPos) = cameraData(for: state)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.6
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = completion
        cameraNode.position = camPos
        cameraTargetNode.position = targetPos
        SCNTransaction.commit()
    }

    // All cameras sit inside / at the tent shell (≈ 8×10×4 m, entrance at +Z)
    private var titleCameraPos: SCNVector3 { SCNVector3(0, 1.65, -4.2) }
    private var titleTargetPos:  SCNVector3 { SCNVector3(0, 1.2, 3.2) }

    private func cameraData(for state: LobbyCameraState) -> (SCNVector3, SCNVector3) {
        switch state {
        case .title:
            // At the back wall looking toward the entrance — bed & table in midground,
            // travelers ahead with their backs to the camera
            return (SCNVector3(0, 1.65, -4.2), SCNVector3(0, 1.2, 3.2))
        case .slotSelection:
            // From the back-wall side, glide left and in toward the bed / diaries
            return (SCNVector3(-1.8, 1.55, -2.4), SCNVector3(-3.0, 0.55, -1.0))
        case .characterSelection:
            // Close in on the pair from inside; they turn to face the camera
            return (SCNVector3(0, 1.5, 0.8), SCNVector3(0, 1.25, 3.2))
        case .settings:
            // From the back-wall side, glide right and in toward the table / instruments
            return (SCNVector3(1.4, 1.55, -2.4), SCNVector3(2.2, 0.85, -1.0))
        }
    }

    // MARK: - Diary open animation

    /// Plays the cover hinge open once, holds that pose, then calls completion.
    /// Page-flip clips are skipped (wrong pivot in the USDZ). Already-opened diaries
    /// skip the clip and complete immediately.
    func openDiary(at index: Int, completion: @escaping () -> Void) {
        guard index < diaryNodes.count else { completion(); return }

        if openedDiaries.contains(index) {
            completion()
            return
        }
        openedDiaries.insert(index)

        let diary = diaryNodes[index]
        var played = false
        // Only drive the cover hinge — page_* clips flip from the wrong origin.
        forEachAnimatedDiaryNode(in: diary) { node, player in
            guard node.name?.contains("hinge") == true else { return }
            configureDiaryAnimation(player.animation)
            player.speed = 1
            player.paused = false
            player.play()
            played = true
        }

        let delay = played ? diaryAnimDuration : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.openedDiaries.contains(index) else { return }
            // Bake the open pose into the model so we can tween it shut later
            self.bakePresentationTransforms(in: diary)
            completion()
        }
    }

    /// Animates open diaries shut by tweening baked poses back to closed.
    func closeAllDiaries() {
        let toClose = openedDiaries
        openedDiaries.removeAll()
        guard !toClose.isEmpty else { return }

        for index in toClose where index < diaryNodes.count {
            let diary = diaryNodes[index]
            bakePresentationTransforms(in: diary)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = diaryAnimDuration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            forEachAnimatedDiaryNode(in: diary) { node, _ in
                guard let name = node.name,
                      let closed = diaryClosedPoses[name] else { return }
                closed.apply(to: node)
            }
            SCNTransaction.commit()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + diaryAnimDuration) { [weak self] in
            guard let self else { return }
            for diary in self.diaryNodes {
                self.prepareDiaryClosed(diary)
            }
        }
    }

    /// Copies each animated node's presentation pose into its model pose and stops clips.
    private func bakePresentationTransforms(in diary: SCNNode) {
        forEachAnimatedDiaryNode(in: diary) { node, player in
            DiaryPose.capturePresentation(from: node).apply(to: node)
            player.animation.isAppliedOnCompletion = false
            player.stop()
        }
    }
}
