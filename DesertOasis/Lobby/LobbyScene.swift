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

    let cameraNode = SCNNode()
    private let cameraTargetNode = SCNNode()

    private(set) var diaryNodes: [SCNNode] = []
    private(set) var settingsZoneNode = SCNNode()

    private var manNode: SCNNode!
    private var womanNode: SCNNode!

    private var openedDiaries: Set<Int> = []
    private var diaryAnimDuration: TimeInterval { 0.55 }

    override init() {
        super.init()
        buildScene()
    }

    required init?(coder: NSCoder) { nil }

    private func buildScene() {
        background.contents = UIColor(red: 0.04, green: 0.05, blue: 0.11, alpha: 1)
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
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1)
        ambient.intensity = 180
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        // Main ceiling lantern fill (lantern mesh also carries its own omni)
        let key = SCNLight()
        key.type = .omni
        key.color = UIColor(red: 1.0, green: 0.78, blue: 0.48, alpha: 1)
        key.intensity = 420
        key.attenuationStartDistance = 0.8
        key.attenuationEndDistance = 12
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0, 3.2, 0)
        rootNode.addChildNode(keyNode)

        let bounce = SCNLight()
        bounce.type = .omni
        bounce.color = UIColor(red: 0.95, green: 0.70, blue: 0.42, alpha: 1)
        bounce.intensity = 90
        bounce.attenuationStartDistance = 0.3
        bounce.attenuationEndDistance = 8
        let bounceNode = SCNNode()
        bounceNode.light = bounce
        bounceNode.position = SCNVector3(0, 0.35, 0.5)
        rootNode.addChildNode(bounceNode)

        let rear = SCNLight()
        rear.type = .omni
        rear.color = UIColor(red: 1.0, green: 0.74, blue: 0.48, alpha: 1)
        rear.intensity = 200
        rear.attenuationStartDistance = 0.4
        rear.attenuationEndDistance = 10
        let rearNode = SCNNode()
        rearNode.light = rear
        rearNode.position = SCNVector3(0, 1.8, -2.2)
        rootNode.addChildNode(rearNode)

        // Character key lights — faces readable when looking at the entrance
        let faceWarm = SCNLight()
        faceWarm.type = .omni
        faceWarm.color = UIColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1)
        faceWarm.intensity = 160
        faceWarm.attenuationStartDistance = 0.3
        faceWarm.attenuationEndDistance = 6
        let faceNode = SCNNode()
        faceNode.light = faceWarm
        faceNode.position = SCNVector3(0, 1.7, 1.6)
        rootNode.addChildNode(faceNode)

        let bedLight = SCNLight()
        bedLight.type = .omni
        bedLight.color = UIColor(red: 1.0, green: 0.72, blue: 0.42, alpha: 1)
        bedLight.intensity = 140
        bedLight.attenuationStartDistance = 0.2
        bedLight.attenuationEndDistance = 4
        let bedLightNode = SCNNode()
        bedLightNode.light = bedLight
        bedLightNode.position = SCNVector3(-2.2, 1.5, -0.7)
        rootNode.addChildNode(bedLightNode)

        let tableLight = SCNLight()
        tableLight.type = .omni
        tableLight.color = UIColor(red: 1.0, green: 0.74, blue: 0.44, alpha: 1)
        tableLight.intensity = 140
        tableLight.attenuationStartDistance = 0.2
        tableLight.attenuationEndDistance = 4
        let tableLightNode = SCNNode()
        tableLightNode.light = tableLight
        tableLightNode.position = SCNVector3(2.0, 1.5, -1.0)
        rootNode.addChildNode(tableLightNode)

        let moon = SCNLight()
        moon.type = .directional
        moon.color = UIColor(red: 0.42, green: 0.50, blue: 0.75, alpha: 1)
        moon.intensity = 35
        let moonNode = SCNNode()
        moonNode.light = moon
        moonNode.eulerAngles = SCNVector3(-Float.pi * 0.12, Float.pi, 0)
        rootNode.addChildNode(moonNode)
    }

    private func setupFloor() {
        let floor = SCNNode(geometry: SCNBox(width: 14, height: 0.15, length: 16, chamferRadius: 0))
        floor.geometry?.firstMaterial?.diffuse.contents = VoxelType.sand.color
        floor.geometry?.firstMaterial?.lightingModel = .lambert
        floor.position = SCNVector3(0, -0.05, 0)
        rootNode.addChildNode(floor)
    }

    private func setupTent() {
        let tent = VoxelPropBuilder.lobbyTentShell()
        tent.position = SCNVector3(0, 0, 0)
        rootNode.addChildNode(tent)
    }

    private func setupBed() {
        let bed = VoxelPropBuilder.lobbyBed()
        // Along the left tent wall, clear of the canvas.
        bed.position = SCNVector3(-2.45, 0, -0.7)
        rootNode.addChildNode(bed)

        diaryNodes = []
        for i in 0..<3 {
            if let diary = bed.childNode(withName: "diary_\(i)", recursively: true) {
                diaryNodes.append(diary)
            }
        }
    }

    private func setupTable() {
        let table = VoxelPropBuilder.lobbyTable()
        table.position = SCNVector3(2.2, 0, -1)
        table.eulerAngles.y = Float.pi / -2
        rootNode.addChildNode(table)
        settingsZoneNode = table
    }

    private let manExitPos   = SCNVector3(-0.55, 0, 3.2)
    private let womanExitPos = SCNVector3( 0.55, 0, 3.2)
    private let exitFacingYaw: Float = 0
    private let cameraFacingYaw: Float = .pi

    private func setupCharacters() {
        manNode = VoxelCharacterBuilder.player(gender: .man)
        manNode.name = "character_man"
        manNode.position = manExitPos
        manNode.eulerAngles = SCNVector3(0, exitFacingYaw, 0)
        VoxelAnim.playIdle(on: manNode)
        rootNode.addChildNode(manNode)

        womanNode = VoxelCharacterBuilder.player(gender: .woman)
        womanNode.name = "character_woman"
        womanNode.position = womanExitPos
        womanNode.eulerAngles = SCNVector3(0, exitFacingYaw, 0)
        VoxelAnim.playIdle(on: womanNode)
        rootNode.addChildNode(womanNode)
    }

    func presentCharactersForSelection(duration: TimeInterval = 1.0) {
        turnCharacters(toYaw: cameraFacingYaw, duration: duration)
    }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            VoxelAnim.playIdle(on: self.manNode)
            VoxelAnim.playIdle(on: self.womanNode)
        }
    }

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 58
        camera.zNear = 0.1
        camera.zFar = 80
        camera.wantsHDR = true
        camera.bloomIntensity = 0.09
        camera.bloomThreshold = 1.3
        camera.minimumExposure = -0.8
        camera.maximumExposure = 0.0
        camera.whitePoint = 2.8
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

    private var titleCameraPos: SCNVector3 { SCNVector3(0, 1.65, -4.2) }
    private var titleTargetPos:  SCNVector3 { SCNVector3(0, 1.2, 3.2) }

    private func cameraData(for state: LobbyCameraState) -> (SCNVector3, SCNVector3) {
        switch state {
        case .title:
            return (SCNVector3(0, 1.65, -4.2), SCNVector3(0, 1.2, 3.2))
        case .slotSelection:
            return (SCNVector3(-1.2, 1.55, -2.3), SCNVector3(-2.45, 0.55, -0.7))
        case .characterSelection:
            return (SCNVector3(0, 1.5, 0.8), SCNVector3(0, 1.25, 3.2))
        case .settings:
            return (SCNVector3(1.4, 1.55, -2.4), SCNVector3(2.2, 0.85, -1.0))
        }
    }

    func openDiary(at index: Int, completion: @escaping () -> Void) {
        guard index < diaryNodes.count else { completion(); return }

        if openedDiaries.contains(index) {
            completion()
            return
        }
        openedDiaries.insert(index)

        let diary = diaryNodes[index]
        if let hinge = diary.childNode(withName: "hinge", recursively: false) {
            // Cover hinged on the right — swings up and open right-to-left.
            let open = SCNAction.rotateTo(x: 0, y: 0, z: -CGFloat.pi * 0.85, duration: diaryAnimDuration)
            open.timingMode = .easeOut
            hinge.runAction(open)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + diaryAnimDuration) {
            completion()
        }
    }

    func closeAllDiaries() {
        let toClose = openedDiaries
        openedDiaries.removeAll()
        guard !toClose.isEmpty else { return }

        for index in toClose where index < diaryNodes.count {
            let diary = diaryNodes[index]
            if let hinge = diary.childNode(withName: "hinge", recursively: false) {
                let close = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: diaryAnimDuration)
                close.timingMode = .easeInEaseOut
                hinge.runAction(close)
            }
        }
    }
}
