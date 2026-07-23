import SwiftUI
import SceneKit

struct GameView: View {
    @Bindable var gameManager: GameManager
    let slotIndex: Int

    @State private var desertScene = DesertScene()
    @State private var dialogueManager = DialogueManager()
    @State private var joystickOffset: CGSize = .zero
    @State private var lastCameraTranslation: CGSize = .zero
    @State private var toastMessage: String? = nil
    @State private var oasisFoundSet: Set<String> = []
    @State private var sceneBuilt = false
    @State private var isLoadingWorld = true
    @State private var loadProgress: Float = 0
    @State private var isNearBarrel = false
    @State private var isNearWater = false
    @State private var isNearBed = false
    @State private var carryingWater = false
    @State private var campWaterLevel: Float = 0
    @State private var oasisStage: OasisGrowthStage = .barren
    @State private var oasisProgress: Float = 0
    @State private var isRunningHeld = false
    @State private var lastWaterWarningLevel: Float = 1.0
    @State private var isSleeping = false
    @State private var timeOfDay: Float = 0.32

    private enum ActionKind {
        case giveWater(NPCNode), deliver, collect, sleep

        var icon: String {
            switch self {
            case .giveWater: "drop.fill"
            case .deliver:   "drop.fill"
            case .collect:   "drop"
            case .sleep:     "moon.zzz.fill"
            }
        }
        var label: String {
            switch self {
            case .giveWater: "Give"
            case .deliver:   "Deliver"
            case .collect:   "Collect"
            case .sleep:     "Sleep"
            }
        }
        var tint: Color {
            switch self {
            case .giveWater: Color(red: 0.15, green: 0.45, blue: 0.80)
            case .deliver:   Color(red: 0.15, green: 0.50, blue: 0.80)
            case .collect:   Color(red: 0.10, green: 0.55, blue: 0.35)
            case .sleep:     Color(red: 0.28, green: 0.32, blue: 0.62)
            }
        }
    }

    private var currentAction: ActionKind? {
        if dialogueManager.isVisible, carryingWater,
           let npc = dialogueManager.activeNPC,
           npc.personality.canReceiveWater, !npc.task.isCompleted {
            return .giveWater(npc)
        }
        if isNearBarrel { return .deliver }
        if isNearWater && !carryingWater { return .collect }
        if isNearBed && !carryingWater { return .sleep }
        return nil
    }

    var slot: SaveSlot { gameManager.saveSlots[slotIndex] }

    var body: some View {
        ZStack {
            // 3D game scene
            GameSceneView(
                scene: desertScene,
                onNPCTapped: handleNPCTap,
                onBedTapped: handleBedTap,
                onSettingsTableTapped: {
                    guard !isSleeping else { return }
                    showToast("Camp table — rest at the bed to skip the night.")
                }
            )
                .ignoresSafeArea()
                .gesture(cameraDragGesture)
                .allowsHitTesting(!isLoadingWorld && !isSleeping)

            if isLoadingWorld {
                WorldLoadingOverlay(progress: loadProgress)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if isSleeping {
                SleepOverlay()
                    .transition(.opacity)
                    .zIndex(9)
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

            // Give water button — floats above dialogue panel
            if !isLoadingWorld,
               dialogueManager.isVisible,
               carryingWater,
               let npc = dialogueManager.activeNPC,
               npc.personality.canReceiveWater,
               !npc.task.isCompleted {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        contextActionButton(for: .giveWater(npc))
                            .padding(.trailing, 28)
                            .padding(.bottom, 310)
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: carryingWater)
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
                        .padding(.top, 58)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.5), value: toastMessage != nil)
            }

            // HUD (hidden while chatting / loading / sleeping)
            if !isLoadingWorld, !dialogueManager.isVisible, !isSleeping {
                VStack(spacing: 0) {
                    topInfoBar
                        .padding(.horizontal, 12)
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
                            if let action = currentAction {
                                contextActionButton(for: action)
                                    .transition(.scale.combined(with: .opacity))
                            }

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
                        .animation(.spring(duration: 0.3), value: currentAction != nil)
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
            timeOfDay = slot.timeOfDay
            let home = slot.progress(forCampId: "home")
            oasisStage = OasisGrowthStage(rawValue: home.oasisStage) ?? .barren
            oasisProgress = home.oasisProgress
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

    private var topInfoBar: some View {
        HStack(spacing: 8) {
            Button {
                gameManager.currentScreen = .slotSelection
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.4), in: Circle())
            }

            dayNightBadge

            if carryingWater {
                Label("Bucket", systemImage: "drop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.55), in: Capsule())
            }

            if slot.hasWaterCompass {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
            }
            if slot.hasWaterDetector {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                statBadge(icon: "sun.max.fill", value: slot.oasisFound, color: .orange)
                statBadge(icon: "checkmark.circle.fill", value: slot.waterDeliveries, color: .green)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var dayNightBadge: some View {
        let icon = timeOfDay < 0.22 || timeOfDay > 0.78
            ? "moon.stars.fill"
            : (timeOfDay > 0.68 ? "sun.horizon.fill" : "sun.max.fill")
        return Label(timeLabel, systemImage: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
    }

    private var timeLabel: String {
        switch timeOfDay {
        case ..<0.22: "Night"
        case ..<0.30: "Dawn"
        case ..<0.68: "Day"
        case ..<0.78: "Dusk"
        default: "Night"
        }
    }

    private func statBadge(icon: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(value)").foregroundStyle(.white)
        }
        .font(.system(size: 12, weight: .bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.45), in: Capsule())
    }

    // MARK: - Scene callbacks

    private func wireCallbacks() {
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

        desertScene.onWaterDelivered = { level, unlockedCompass, unlockedDetector, campId in
            carryingWater = false
            isNearBarrel = false
            if campId == "home" || desertScene.camp?.site.id == campId {
                campWaterLevel = level
            }

            var deliveries = slot.waterDeliveries + 1
            let stage = desertScene.camps.first { $0.site.id == campId }?.oasisStage ?? oasisStage
            let prog = desertScene.camps.first { $0.site.id == campId }?.oasisProgress ?? oasisProgress
            gameManager.updateProgress(
                slotIndex: slotIndex,
                tasksCompleted: slot.tasksCompleted + 1,
                campWaterLevel: campId == "home" ? level : nil,
                waterDeliveries: deliveries,
                isCarryingWater: false,
                hasWaterCompass: unlockedCompass ? true : nil,
                hasWaterDetector: unlockedDetector ? true : nil,
                campProgress: CampProgress(
                    id: campId,
                    waterLevel: level,
                    oasisStage: stage.rawValue,
                    oasisProgress: prog
                )
            )

            if unlockedCompass {
                showToast("Water delivered! Compass unlocked.")
            } else if unlockedDetector {
                showToast("Water delivered! Detector unlocked.")
            } else if campId != "home" {
                showToast("Water delivered to a new camp!")
            } else {
                showToast("Water delivered to camp! (\(deliveries))")
            }
        }

        desertScene.onNearBarrel = { near in
            withAnimation { isNearBarrel = near }
        }

        desertScene.onNearWater = { near in
            withAnimation { isNearWater = near }
        }

        desertScene.onNearBed = { near in
            withAnimation { isNearBed = near }
        }

        desertScene.onNearSettingsTable = { near in
            // Table is flavour + a quiet shortcut into settings when tapped (handled in scene tap).
            _ = near
        }

        desertScene.onCampDrained = { level, campId in
            if campId == "home" {
                let prev = campWaterLevel
                campWaterLevel = level
                gameManager.updateProgress(slotIndex: slotIndex, campWaterLevel: level)
                if level <= 0 && prev > 0 {
                    showToast("The camp barrel is empty!")
                    lastWaterWarningLevel = 0
                } else if level < 0.2 && lastWaterWarningLevel >= 0.2 {
                    showToast("Camp water running low!")
                    lastWaterWarningLevel = level
                }
            } else {
                persistCamp(campId)
            }
        }

        desertScene.onOasisGrown = { campId, stage, progress, advanced in
            if campId == "home" {
                oasisStage = stage
                oasisProgress = progress
            }
            persistCamp(campId)
            if advanced {
                showToast("The oasis grows — \(stage.displayName)!")
            }
        }

        desertScene.onCampDiscovered = { site in
            showToast("A new camp! Help them grow an oasis.")
            gameManager.updateProgress(
                slotIndex: slotIndex,
                campProgress: CampProgress(id: site.id)
            )
        }

        desertScene.onTimeOfDayChanged = { t in
            timeOfDay = t
            gameManager.updateProgress(slotIndex: slotIndex, timeOfDay: t)
        }

        desertScene.onWaterGivenToNPC = { npc in
            carryingWater = false
            dialogueManager.endConversation()
            gameManager.updateProgress(
                slotIndex: slotIndex,
                tasksCompleted: slot.tasksCompleted + 1,
                isCarryingWater: false
            )
            let name = npc.personality == .wanderer ? "the wanderer" : "the lost traveller"
            showToast("You shared your water with \(name).")
        }

        desertScene.onSleepFinished = {
            withAnimation { isSleeping = false }
            showToast("A new day rises over the camp.")
            persistAllCamps()
        }
    }

    private func persistCamp(_ campId: String) {
        guard let c = desertScene.camps.first(where: { $0.site.id == campId }) else { return }
        gameManager.updateProgress(
            slotIndex: slotIndex,
            campWaterLevel: campId == "home" ? c.fillLevel : nil,
            campProgress: CampProgress(
                id: campId,
                waterLevel: c.fillLevel,
                oasisStage: c.oasisStage.rawValue,
                oasisProgress: c.oasisProgress
            )
        )
    }

    private func persistAllCamps() {
        for c in desertScene.camps {
            persistCamp(c.site.id)
        }
        gameManager.updateProgress(slotIndex: slotIndex, timeOfDay: desertScene.dayNight.timeOfDay)
        timeOfDay = desertScene.dayNight.timeOfDay
        if let home = desertScene.camp {
            oasisStage = home.oasisStage
            oasisProgress = home.oasisProgress
            campWaterLevel = home.fillLevel
        }
    }

    private func handleNPCTap(_ npc: NPCNode) {
        guard !isLoadingWorld, !isSleeping, !dialogueManager.isVisible else { return }
        guard dialogueManager.activeNPC?.npcID != npc.npcID else { return }
        if let player = desertScene.playerNode {
            let dx = npc.position.x - player.position.x
            let dz = npc.position.z - player.position.z
            guard dx * dx + dz * dz < 10 * 10 else { return }
        }
        dialogueManager.startConversation(
            with: npc,
            situation: CampSituation(
                campWaterLevel: campWaterLevel,
                waterDeliveries: slot.waterDeliveries,
                oasisFound: slot.oasisFound,
                isCarryingWater: carryingWater,
                hasCompass: slot.hasWaterCompass,
                hasDetector: slot.hasWaterDetector,
                playerName: slot.playerName,
                oasisStageName: oasisStage.displayName.lowercased(),
                oasisProgress: oasisProgress
            )
        )
    }

    private func handleBedTap() {
        guard !isLoadingWorld, !isSleeping, isNearBed else { return }
        startSleep()
    }

    private func startSleep() {
        guard !isSleeping else { return }
        withAnimation { isSleeping = true }
        desertScene.beginSleep()
    }

    @ViewBuilder
    private func contextActionButton(for action: ActionKind) -> some View {
        Button { performAction(action) } label: {
            VStack(spacing: 3) {
                Image(systemName: action.icon)
                    .font(.system(size: 22, weight: .bold))
                Text(action.label)
                    .font(.system(size: 11, weight: .bold, design: .serif))
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(action.tint.opacity(0.82), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1.5))
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }

    private func performAction(_ action: ActionKind) {
        switch action {
        case .giveWater(let npc): desertScene.giveWaterToNPC(npc)
        case .deliver: _ = desertScene.tryDeliverWater()
        case .collect: _ = desertScene.tryCollectWater()
        case .sleep: startSleep()
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
                guard !isLoadingWorld, !isSleeping, !dialogueManager.isVisible else { return }
                let dx = Float(value.translation.width - lastCameraTranslation.width) * 0.005
                let dy = Float(value.translation.height - lastCameraTranslation.height) * 0.004
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

// MARK: - Sleep overlay

struct SleepOverlay: View {
    @State private var pulse = false

    var body: some View {
        VStack {
            Spacer()
            Text("Night falls over the oasis…")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 8)
                .opacity(pulse ? 1 : 0.7)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color(red: 0.12, green: 0.08, blue: 0.22).opacity(0.35),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .allowsHitTesting(false)
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
    var onNPCTapped: ((NPCNode) -> Void)?
    var onBedTapped: (() -> Void)?
    var onSettingsTableTapped: (() -> Void)?

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

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.pointOfView = scene.activeCameraNode
        context.coordinator.scene = scene
        context.coordinator.onNPCTapped = onNPCTapped
        context.coordinator.onBedTapped = onBedTapped
        context.coordinator.onSettingsTableTapped = onSettingsTableTapped
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var scene: DesertScene
        var onNPCTapped: ((NPCNode) -> Void)?
        var onBedTapped: (() -> Void)?
        var onSettingsTableTapped: (() -> Void)?
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
            if let view = renderer as? SCNView {
                view.pointOfView = scene.activeCameraNode
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let scnView = gesture.view as? SCNView,
                  !scene.isSleeping else { return }
            let point = gesture.location(in: scnView)
            let hits = scnView.hitTest(point, options: nil)
            for hit in hits {
                var node: SCNNode? = hit.node
                while let n = node {
                    if let npc = n as? NPCNode {
                        DispatchQueue.main.async { self.onNPCTapped?(npc) }
                        return
                    }
                    if n.name == "sleep_bed" || n.name == "lobby_bed" {
                        DispatchQueue.main.async { self.onBedTapped?() }
                        return
                    }
                    if n.name == "camp_settings_table" || n.name == "settings_zone" {
                        DispatchQueue.main.async { self.onSettingsTableTapped?() }
                        return
                    }
                    node = n.parent
                }
            }
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
