import SwiftUI
import SceneKit

struct LobbySceneView: UIViewRepresentable {
    let scene: LobbyScene
    var onDiaryTapped: (Int) -> Void
    var onSettingsTapped: () -> Void
    var onCharacterTapped: (SaveSlot.CharacterGender) -> Void
    var onBackgroundTapped: () -> Void

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.pointOfView = scene.cameraNode
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(white: 0.04, alpha: 1)
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 60

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onDiaryTapped      = onDiaryTapped
        context.coordinator.onSettingsTapped   = onSettingsTapped
        context.coordinator.onCharacterTapped  = onCharacterTapped
        context.coordinator.onBackgroundTapped = onBackgroundTapped
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: scene,
                    onDiaryTapped: onDiaryTapped,
                    onSettingsTapped: onSettingsTapped,
                    onCharacterTapped: onCharacterTapped,
                    onBackgroundTapped: onBackgroundTapped)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let scene: LobbyScene
        var onDiaryTapped: (Int) -> Void
        var onSettingsTapped: () -> Void
        var onCharacterTapped: (SaveSlot.CharacterGender) -> Void
        var onBackgroundTapped: () -> Void

        init(scene: LobbyScene,
             onDiaryTapped: @escaping (Int) -> Void,
             onSettingsTapped: @escaping () -> Void,
             onCharacterTapped: @escaping (SaveSlot.CharacterGender) -> Void,
             onBackgroundTapped: @escaping () -> Void) {
            self.scene = scene
            self.onDiaryTapped = onDiaryTapped
            self.onSettingsTapped = onSettingsTapped
            self.onCharacterTapped = onCharacterTapped
            self.onBackgroundTapped = onBackgroundTapped
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scnView = recognizer.view as? SCNView else { return }
            let location = recognizer.location(in: scnView)
            let hits = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .boundingBoxOnly: false
            ])

            guard let hit = hits.first else {
                onBackgroundTapped()
                return
            }

            // Walk up the node hierarchy looking for a named node
            var node: SCNNode? = hit.node
            while let n = node {
                let name = n.name ?? ""
                if name.hasPrefix("diary_"), let idx = Int(name.suffix(1)) {
                    onDiaryTapped(idx)
                    return
                }
                if name == "settings_zone" {
                    onSettingsTapped()
                    return
                }
                if name == "character_man" {
                    onCharacterTapped(.man)
                    return
                }
                if name == "character_woman" {
                    onCharacterTapped(.woman)
                    return
                }
                node = n.parent
            }
            onBackgroundTapped()
        }
    }
}
