import SwiftUI
import SceneKit

struct GameView: View {
    @Bindable var gameManager: GameManager
    let slotIndex: Int

    @State private var desertScene = DesertScene()
    @State private var dialogueManager = DialogueManager()
    @State private var joystickOffset: CGSize = .zero
    @State private var lastCameraTranslation: CGFloat = 0
    @State private var nearbyNPCPrompt: NPCNode? = nil
    @State private var oasisReachedMessage: String? = nil
    @State private var oasisFoundSet: Set<String> = []
    @State private var sceneBuilt = false

    var slot: SaveSlot { gameManager.saveSlots[slotIndex] }

    var body: some View {
        ZStack {
            // 3D game scene
            GameSceneView(scene: desertScene)
                .ignoresSafeArea()
                .gesture(cameraDragGesture)

            // Dialogue panel
            if dialogueManager.isVisible {
                VStack {
                    Spacer()
                    DialogueView(manager: dialogueManager)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.4), value: dialogueManager.isVisible)
            }

            // NPC tap-to-talk prompt
            if let npc = nearbyNPCPrompt, !dialogueManager.isVisible {
                VStack {
                    Spacer()
                    Button {
                        dialogueManager.startConversation(with: npc)
                        nearbyNPCPrompt = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                            Text("Talk")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.7, green: 0.45, blue: 0.1), in: Capsule())
                        .shadow(radius: 6)
                    }
                    .padding(.bottom, 140)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: nearbyNPCPrompt != nil)
            }

            // Oasis found message
            if let msg = oasisReachedMessage {
                VStack {
                    Text(msg)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.15, green: 0.50, blue: 0.80).opacity(0.9), in: Capsule())
                        .shadow(radius: 8)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.5), value: oasisReachedMessage != nil)
            }

            // HUD
            VStack {
                HStack {
                    // Back to menu
                    Button {
                        gameManager.currentScreen = .slotSelection
                    } label: {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }

                    Spacer()

                    // Stats
                    HStack(spacing: 14) {
                        statBadge(icon: "drop.fill", value: slot.waterFound, color: .blue)
                        statBadge(icon: "sun.max.fill", value: slot.oasisFound, color: .orange)
                        statBadge(icon: "checkmark.circle.fill", value: slot.tasksCompleted, color: .green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Joystick
                if !dialogueManager.isVisible {
                    HStack {
                        JoystickView(offset: $joystickOffset) { dx, dy in
                            desertScene.setMoveInput(dx: dx, dy: dy)
                            savePositionDebounced()
                        }
                        .padding(.leading, 28)
                        .padding(.bottom, 16)
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            guard !sceneBuilt else { return }
            sceneBuilt = true
            desertScene.build(from: slot)
            wireCallbacks()
        }
    }

    private func statBadge(icon: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(value)").foregroundStyle(.white)
        }
        .font(.system(size: 13, weight: .bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
    }

    // MARK: - Scene callbacks

    private func wireCallbacks() {
        desertScene.onNPCProximity = { npc in
            guard nearbyNPCPrompt?.npcID != npc.npcID,
                  dialogueManager.activeNPC?.npcID != npc.npcID else { return }
            withAnimation { nearbyNPCPrompt = npc }
            // Auto-dismiss after 4 s if no interaction
            Task {
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run {
                    withAnimation { nearbyNPCPrompt = nil }
                }
            }
        }

        desertScene.onOasisReached = { oasis in
            let key = "\(oasis.position.x)-\(oasis.position.z)"
            guard !oasisFoundSet.contains(key) else { return }
            oasisFoundSet.insert(key)

            let found = slot.oasisFound + 1
            gameManager.updateProgress(slotIndex: slotIndex, oasisFound: found)

            withAnimation { oasisReachedMessage = "Oasis found! (\(found))" }
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run { withAnimation { oasisReachedMessage = nil } }
            }
        }
    }

    // MARK: - Camera drag

    var cameraDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !dialogueManager.isVisible else { return }
                let delta = Float(value.translation.width - lastCameraTranslation) * 0.005
                desertScene.rotateCamera(by: delta)
                lastCameraTranslation = value.translation.width
            }
            .onEnded { _ in lastCameraTranslation = 0 }
    }

    // MARK: - Save debounce

    @State private var saveTask: Task<Void, Never>? = nil

    private func savePositionDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let p = desertScene.playerNode?.position
            await MainActor.run {
                gameManager.updateProgress(slotIndex: slotIndex,
                                           posX: p.map { $0.x },
                                           posZ: p.map { $0.z })
            }
        }
    }
}

// MARK: - SCNView wrapper

struct GameSceneView: UIViewRepresentable {
    let scene: DesertScene

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: scene)
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = scene
        v.delegate = context.coordinator
        v.allowsCameraControl = false
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.preferredFramesPerSecond = 60
        v.backgroundColor = UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.pointOfView = scene.cameraNode
        context.coordinator.scene = scene
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var scene: DesertScene
        private var lastTime: TimeInterval?

        init(scene: DesertScene) {
            self.scene = scene
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt: Float
            if let lastTime {
                dt = Float(time - lastTime)
            } else {
                dt = 1.0 / 60.0
            }
            lastTime = time
            scene.update(deltaTime: dt)
        }
    }
}

// MARK: - Joystick

struct JoystickView: View {
    @Binding var offset: CGSize
    /// dx = right, dy = forward (stick-up is positive).
    var onMove: (Float, Float) -> Void

    private let radius: CGFloat = 55
    private let thumbRadius: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))

            Circle()
                .fill(.white.opacity(0.5))
                .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                .offset(clampedOffset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let clamped = clampToRadius(v.translation)
                    offset = clamped
                    let dx = Float(clamped.width / radius)
                    let dy = Float(-clamped.height / radius) // screen-up → forward +
                    onMove(dx, dy)
                }
                .onEnded { _ in
                    offset = .zero
                    onMove(0, 0)
                }
        )
    }

    private var clampedOffset: CGSize {
        clampToRadius(offset)
    }

    private func clampToRadius(_ value: CGSize) -> CGSize {
        let len = sqrt(value.width * value.width + value.height * value.height)
        guard len > radius else { return value }
        let scale = radius / len
        return CGSize(width: value.width * scale, height: value.height * scale)
    }
}
