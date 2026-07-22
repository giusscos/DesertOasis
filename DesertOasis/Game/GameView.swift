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
    @State private var toastMessage: String? = nil
    @State private var oasisFoundSet: Set<String> = []
    @State private var sceneBuilt = false
    @State private var showDeliverPrompt = false
    @State private var carryingWater = false
    @State private var campWaterLevel: Float = 0

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

            // Deliver water prompt
            if showDeliverPrompt, !dialogueManager.isVisible, nearbyNPCPrompt == nil {
                VStack {
                    Spacer()
                    Button {
                        _ = desertScene.tryDeliverWater()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "drop.fill")
                            Text("Deliver water")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.15, green: 0.50, blue: 0.80), in: Capsule())
                        .shadow(radius: 6)
                    }
                    .padding(.bottom, 140)
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Toast
            if let msg = toastMessage {
                VStack {
                    Text(msg)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.15, green: 0.50, blue: 0.80).opacity(0.92), in: Capsule())
                        .shadow(radius: 8)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.5), value: toastMessage != nil)
            }

            // HUD
            VStack {
                HStack(alignment: .top) {
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

                    VStack(alignment: .trailing, spacing: 8) {
                        campWaterBar

                        HStack(spacing: 10) {
                            if carryingWater {
                                Label("Full bucket", systemImage: "drop.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.55), in: Capsule())
                            }
                            if slot.hasWaterCompass {
                                Image(systemName: "location.north.circle.fill")
                                    .foregroundStyle(.yellow)
                            }
                            if slot.hasWaterDetector {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(.orange)
                            }
                            statBadge(icon: "sun.max.fill", value: slot.oasisFound, color: .orange)
                            statBadge(icon: "checkmark.circle.fill", value: slot.waterDeliveries, color: .green)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

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
            carryingWater = slot.isCarryingWater
            campWaterLevel = slot.campWaterLevel
            desertScene.build(from: slot)
            wireCallbacks()
        }
    }

    private var campWaterBar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Camp water")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.35))
                    Capsule()
                        .fill(Color(red: 0.25, green: 0.60, blue: 0.90))
                        .frame(width: max(4, geo.size.width * CGFloat(campWaterLevel)))
                }
            }
            .frame(width: 120, height: 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
            showToast("Oasis found! (\(found))")
        }

        desertScene.onWaterCollected = {
            carryingWater = true
            gameManager.updateProgress(
                slotIndex: slotIndex,
                waterFound: slot.waterFound + 1,
                isCarryingWater: true
            )
            showToast("Bucket filled — bring it to camp!")
        }

        desertScene.onWaterDelivered = { level, unlockedCompass, unlockedDetector in
            carryingWater = false
            campWaterLevel = level
            showDeliverPrompt = false

            var deliveries = slot.waterDeliveries + 1
            gameManager.updateProgress(
                slotIndex: slotIndex,
                tasksCompleted: slot.tasksCompleted + 1,
                campWaterLevel: level,
                waterDeliveries: deliveries,
                isCarryingWater: false,
                hasWaterCompass: unlockedCompass ? true : nil,
                hasWaterDetector: unlockedDetector ? true : nil
            )

            if unlockedCompass {
                showToast("Water delivered! Compass unlocked.")
            } else if unlockedDetector {
                showToast("Water delivered! Detector unlocked.")
            } else {
                showToast("Water delivered to camp! (\(deliveries))")
            }
        }

        desertScene.onNearBarrel = { canDeliver in
            withAnimation { showDeliverPrompt = canDeliver }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            await MainActor.run { withAnimation { toastMessage = nil } }
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
