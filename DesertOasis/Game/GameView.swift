import SwiftUI
import SceneKit

struct GameView: View {
    @Bindable var gameManager: GameManager
    let slotIndex: Int

    @State private var desertScene = DesertScene()
    @State private var dialogueManager = DialogueManager()
    @State private var joystickOffset: CGSize = .zero
    @State private var lastCameraTranslation: CGSize = .zero
    @State private var nearbyNPCPrompt: NPCNode? = nil
    @State private var toastMessage: String? = nil
    @State private var oasisFoundSet: Set<String> = []
    @State private var sceneBuilt = false
    @State private var isLoadingWorld = true
    @State private var loadProgress: Float = 0
    @State private var showDeliverPrompt = false
    @State private var carryingWater = false
    @State private var campWaterLevel: Float = 0
    @State private var isRunningHeld = false

    var slot: SaveSlot { gameManager.saveSlots[slotIndex] }

    var body: some View {
        ZStack {
            // 3D game scene
            GameSceneView(scene: desertScene)
                .ignoresSafeArea()
                .gesture(cameraDragGesture)
                .allowsHitTesting(!isLoadingWorld)

            if isLoadingWorld {
                WorldLoadingOverlay(progress: loadProgress)
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Dialogue panel
            if !isLoadingWorld, dialogueManager.isVisible {
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
            if !isLoadingWorld, let npc = nearbyNPCPrompt, !dialogueManager.isVisible {
                VStack {
                    Spacer()
                    Button {
                        dialogueManager.startConversation(
                            with: npc,
                            situation: CampSituation(
                                campWaterLevel: campWaterLevel,
                                waterDeliveries: slot.waterDeliveries,
                                oasisFound: slot.oasisFound,
                                isCarryingWater: carryingWater,
                                hasCompass: slot.hasWaterCompass,
                                hasDetector: slot.hasWaterDetector,
                                playerName: slot.playerName
                            )
                        )
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
            if !isLoadingWorld, showDeliverPrompt, !dialogueManager.isVisible, nearbyNPCPrompt == nil {
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

            // HUD (hidden while chatting / loading)
            if !isLoadingWorld, !dialogueManager.isVisible {
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

                    HStack(alignment: .bottom) {
                        JoystickView(offset: $joystickOffset) { dx, dy in
                            desertScene.setMoveInput(dx: dx, dy: dy)
                            savePositionDebounced()
                        }
                        .padding(.leading, 28)
                        .padding(.bottom, 16)

                        Spacer()

                        VStack(spacing: 14) {
                            HoldActionButton(
                                systemName: "figure.run",
                                isActive: isRunningHeld,
                                activeColor: Color(red: 0.95, green: 0.55, blue: 0.15)
                            ) { held in
                                isRunningHeld = held
                                desertScene.setRunning(held)
                            }

                            TapActionButton(systemName: "arrow.up") {
                                desertScene.jump()
                            }
                        }
                        .padding(.trailing, 28)
                        .padding(.bottom, 28)
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.25), value: dialogueManager.isVisible)
            }
        }
        .onAppear {
            guard !sceneBuilt else { return }
            sceneBuilt = true
            carryingWater = slot.isCarryingWater
            campWaterLevel = slot.campWaterLevel
            desertScene.onBuildProgress = { progress in
                loadProgress = progress
            }
            desertScene.onBuildComplete = {
                withAnimation(.easeOut(duration: 0.45)) {
                    isLoadingWorld = false
                }
                wireCallbacks()
            }
            desertScene.build(from: slot)
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
                guard !isLoadingWorld, !dialogueManager.isVisible else { return }
                let dx = Float(value.translation.width - lastCameraTranslation.width) * 0.005
                let dy = Float(value.translation.height - lastCameraTranslation.height) * 0.004
                // Drag right → yaw; drag up → look up (pitch increases)
                desertScene.rotateCamera(yawDelta: dx, pitchDelta: -dy)
                lastCameraTranslation = value.translation
            }
            .onEnded { _ in lastCameraTranslation = .zero }
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

// MARK: - World loading overlay

struct WorldLoadingOverlay: View {
    let progress: Float
    @State private var pulse = false
    @State private var cubePhase: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.55),
                    Color(red: 0.18, green: 0.12, blue: 0.06).opacity(0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(cubeColor(for: i))
                            .frame(width: 16, height: 16)
                            .offset(y: bounceOffset(for: i))
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                }
                .padding(.bottom, 4)

                Text("Shaping the desert")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 6)

                Text(statusText)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))

                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.18))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.92, green: 0.72, blue: 0.28),
                                            Color(red: 0.95, green: 0.55, blue: 0.18),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(progress)))
                        }
                    }
                    .frame(height: 10)

                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: 260)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                cubePhase = 1
            }
        }
        .allowsHitTesting(true)
    }

    private var statusText: String {
        if progress < 0.25 { return "Laying sand beneath your feet…" }
        if progress < 0.55 { return "Raising dunes from voxels…" }
        if progress < 0.85 { return "Carving the horizon…" }
        if progress < 0.98 { return "Pitching camp…" }
        return "Almost ready…"
    }

    private func cubeColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.90, green: 0.78, blue: 0.45),
            Color(red: 0.82, green: 0.62, blue: 0.30),
            Color(red: 0.72, green: 0.52, blue: 0.28),
            Color(red: 0.55, green: 0.48, blue: 0.38),
            Color(red: 0.35, green: 0.55, blue: 0.70),
        ]
        return colors[index % colors.count].opacity(pulse ? 1 : 0.7)
    }

    private func bounceOffset(for index: Int) -> CGFloat {
        let wave = (cubePhase + Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        return -10 * sin(wave * .pi)
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

// MARK: - Action buttons

struct TapActionButton: View {
    let systemName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.black.opacity(0.38), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct HoldActionButton: View {
    let systemName: String
    var isActive: Bool
    var activeColor: Color = .orange
    var onHoldChanged: (Bool) -> Void

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(isActive ? .white : .white.opacity(0.9))
            .frame(width: 64, height: 64)
            .background(
                (isActive ? activeColor.opacity(0.75) : Color.black.opacity(0.38)),
                in: Circle()
            )
            .overlay(Circle().stroke(.white.opacity(isActive ? 0.55 : 0.28), lineWidth: 1.5))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isActive { onHoldChanged(true) }
                    }
                    .onEnded { _ in
                        onHoldChanged(false)
                    }
            )
    }
}
