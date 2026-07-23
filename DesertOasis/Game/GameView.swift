import SwiftUI
import SceneKit
import UIKit
import GameController

struct GameView: View {
    @Bindable var gameManager: GameManager
    let slotIndex: Int

    @State private var desertScene = DesertScene()
    @State private var dialogueManager = DialogueManager()
    @State private var joystickOffset: CGSize = .zero
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
    @State private var isPaused = false
    @State private var isShowingSettings = false
    @State private var timeOfDay: Float = 0.32
    @State private var pressedKeys: Set<GameKey> = []
    @State private var runSources: Set<RunSource> = []
    @State private var missionManager = MissionManager()
    @State private var isShowingMissions = false
    @State private var isShowingIntro = false
    @State private var pendingMissionOffer: MissionDefinition? = nil
    @State private var deniedMissionOffers: Set<String> = []
    @State private var worldReady = false
    @State private var callbacksWired = false

    private enum GameKey: Hashable {
        case moveForward, moveBack, moveLeft, moveRight
    }

    private enum RunSource: Hashable {
        case shiftOrR, touch
    }

    /// Playing with hidden, confined cursor.
    private var isPointerLockedGameplay: Bool {
        !isLoadingWorld && !isSleeping && !isPaused && !isShowingSettings && !isShowingMissions && !isShowingIntro && !dialogueManager.isVisible
    }

    /// Keyboard capture (includes pause so Esc can resume).
    private var acceptsKeyboardInput: Bool {
        !isLoadingWorld && !isSleeping && !dialogueManager.isVisible && !isShowingIntro
    }

    /// Virtual stick for phones/iPads; Mac uses WASD instead.
    private var showsOnScreenJoystick: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        !ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

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
        if isNearBed && !carryingWater && canSleepNow { return .sleep }
        return nil
    }

    /// Sleep is offered from late dusk through night (before dawn).
    private var canSleepNow: Bool {
        timeOfDay > 0.68 || timeOfDay < 0.22
    }

    var slot: SaveSlot { gameManager.saveSlots[slotIndex] }

    var body: some View {
        ZStack {
            // 3D game scene
            GameSceneView(
                scene: desertScene,
                acceptsKeyboard: acceptsKeyboardInput,
                pointerLookEnabled: isPointerLockedGameplay,
                showsJoystick: showsOnScreenJoystick,
                onNPCTapped: handleNPCTap,
                onAnimalTapped: handleAnimalTap,
                onBedTapped: handleBedTap,
                onSettingsTableTapped: {
                    guard !isSleeping, !isPaused else { return }
                    setShowingSettings(true)
                },
                onKeyDown: { handleHardwareKey($0, isDown: true) },
                onKeyUp: { handleHardwareKey($0, isDown: false) },
                onCameraDrag: { yaw, pitch in
                    guard isPointerLockedGameplay else { return }
                    desertScene.rotateCamera(yawDelta: yaw, pitchDelta: pitch)
                }
            )
                .ignoresSafeArea()
                .allowsHitTesting(!isLoadingWorld && !isSleeping)

            if isLoadingWorld, !isShowingIntro {
                WorldLoadingOverlay(progress: loadProgress)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if isSleeping {
                SleepOverlay()
                    .transition(.opacity)
                    .zIndex(9)
            }

            if isPaused, !isLoadingWorld, !isSleeping {
                PauseOverlay(
                    onResume: { setPaused(false) },
                    onExitToCamp: {
                        setPaused(false)
                        gameManager.currentScreen = .slotSelection
                    }
                )
                .transition(.opacity)
                .zIndex(11)
            }

            if isShowingSettings, !isLoadingWorld, !isSleeping {
                SettingsOverlayView(
                    gameManager: gameManager,
                    onBack: { setShowingSettings(false) },
                    onReturnToMainScreen: {
                        setShowingSettings(false)
                        gameManager.currentScreen = .title
                    }
                )
                .transition(.opacity)
                .zIndex(12)
            }

            // Missions list overlay
            if isShowingMissions, !isLoadingWorld, !isSleeping {
                MissionsOverlayView(
                    missionManager: missionManager,
                    onBack: { setShowingMissions(false) }
                )
                .transition(.opacity)
                .zIndex(12)
            }

            // NPC mission offer card — floats above dialogue when an NPC proposes a mission
            if let offer = pendingMissionOffer, !isLoadingWorld {
                MissionOfferView(
                    mission: offer,
                    onAccept: {
                        missionManager.unlock(offer.id)
                        saveMissions()
                        withAnimation(.spring(duration: 0.35)) { pendingMissionOffer = nil }
                        showToast("Mission accepted: \(offer.title)")
                    },
                    onDismiss: {
                        deniedMissionOffers.insert(offer.id)
                        withAnimation(.spring(duration: 0.35)) { pendingMissionOffer = nil }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.4), value: pendingMissionOffer != nil)
                .zIndex(8)
            }

            // Cinematic story intro — shown for new games while world builds in background
            if isShowingIntro {
                IntroStoryView(onBegin: onIntroFinished)
                    .transition(.opacity)
                    .zIndex(14)
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
                .onKeyPress(.escape) {
                    dialogueManager.endConversation()
                    return .handled
                }
                .onKeyPress(KeyEquivalent("e")) {
                    if let action = currentAction {
                        performAction(action)
                        return .handled
                    }
                    return .ignored
                }
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

            // HUD (hidden while chatting / loading / sleeping / paused / settings / missions / intro)
            if !isLoadingWorld, !dialogueManager.isVisible, !isSleeping, !isPaused, !isShowingSettings, !isShowingMissions, !isShowingIntro {
                VStack(spacing: 0) {
                    topInfoBar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    Spacer()

                    HStack(alignment: .bottom) {
                        if showsOnScreenJoystick {
                            JoystickView(offset: $joystickOffset) { dx, dy in
                                desertScene.setMoveInput(dx: dx, dy: dy)
                                savePositionDebounced()
                            }
                            .padding(.leading, 28)
                            .padding(.bottom, 16)
                        }

                        Spacer()

                        VStack(spacing: 14) {
                            if let action = currentAction {
                                contextActionButton(for: action)
                                    .transition(.scale.combined(with: .opacity))
                            }

                            HoldActionButton(
                                systemName: "figure.run",
                                keyLabel: showsOnScreenJoystick ? nil : "⇧",
                                isActive: isRunningHeld,
                                activeColor: Color(red: 0.95, green: 0.55, blue: 0.15)
                            ) { held in
                                if held {
                                    runSources.insert(.touch)
                                } else {
                                    runSources.remove(.touch)
                                }
                                syncRunning()
                            }

                            TapActionButton(
                                systemName: "arrow.up",
                                keyLabel: showsOnScreenJoystick ? nil : "Space"
                            ) {
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
        .onChange(of: isPointerLockedGameplay) { _, locked in
            PointerLockBridge.wantsLock = locked
        }
        .onDisappear {
            PointerLockBridge.wantsLock = false
            AudioManager.shared.setWalking(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPointerLockState.didChangeNotification)) { _ in
            // Re-assert preference after system evaluates click / fullscreen requirements.
            if isPointerLockedGameplay {
                PointerLockBridge.refresh()
            }
        }
        .onChange(of: dialogueManager.isVisible) { _, visible in
            desertScene.isInputBlocked = visible
            if visible {
                AudioManager.shared.play(.dialogue)
                clearKeyboardMovement()
                if isPaused { isPaused = false }
                if isShowingSettings { isShowingSettings = false }
            } else {
                pendingMissionOffer = nil
            }
        }
        .onChange(of: isSleeping) { _, sleeping in
            if sleeping {
                clearKeyboardMovement()
                isPaused = false
                isShowingSettings = false
            }
        }
        .onAppear {
            PointerLockBridge.wantsLock = isPointerLockedGameplay
            guard !sceneBuilt else { return }
            sceneBuilt = true
            carryingWater = slot.isCarryingWater
            campWaterLevel = slot.campWaterLevel
            timeOfDay = slot.timeOfDay
            let home = slot.progress(forCampId: "home")
            oasisStage = OasisGrowthStage(rawValue: home.oasisStage) ?? .barren
            oasisProgress = home.oasisProgress

            // Restore mission state from save, then patch any gaps for returning players.
            missionManager.load(from: slot.missions)
            missionManager.unlock("keeper_first_drop")
            if slot.waterDeliveries > 0 {
                missionManager.complete("keeper_first_drop")
                missionManager.unlock("glimmer_in_dust")
            }
            if slot.oasisFound > 0 {
                missionManager.complete("glimmer_in_dust")
                missionManager.unlock("oasis_remembers")
            }
            if slot.campProgress.count > 1 {
                missionManager.unlock("beyond_horizon")
            }
            if slot.campProgress.count > 2 {
                missionManager.complete("beyond_horizon")
            }
            if oasisStage == .lush  { missionManager.complete("oasis_remembers") }
            if oasisStage >= .pond  { missionManager.complete("ancient_trial") }
            if slot.waterDeliveries >= 5 { missionManager.complete("merchants_route") }
            saveMissions()

            // Show cinematic intro for brand-new saves.
            let isNewGame = slot.waterFound == 0 && slot.oasisFound == 0 && slot.waterDeliveries == 0
            if isNewGame { isShowingIntro = true }

            desertScene.onBuildProgress = { progress in
                loadProgress = progress
            }
            desertScene.onBuildComplete = {
                worldReady = true
                if !isShowingIntro {
                    withAnimation(.easeOut(duration: 0.45)) { isLoadingWorld = false }
                    ensureCallbacksWired()
                }
            }

            // Wire the NPC mission-offer callback on DialogueManager.
            dialogueManager.onConversationStarted = { npc in
                guard let offerId = npc.personality.missionOffer,
                      !missionManager.isUnlocked(offerId),
                      !deniedMissionOffers.contains(offerId),
                      let def = MissionManager.catalog.first(where: { $0.id == offerId })
                else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    await MainActor.run {
                        withAnimation(.spring(duration: 0.4)) { pendingMissionOffer = def }
                    }
                }
            }

            desertScene.build(from: slot)
        }
    }

    // MARK: - Keyboard / pause

    private func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        if paused { isShowingSettings = false }
        withAnimation(.easeOut(duration: 0.2)) {
            isPaused = paused
        }
        if paused {
            clearKeyboardMovement()
            desertScene.isInputBlocked = true
            PointerLockBridge.wantsLock = false
        } else {
            desertScene.isInputBlocked = false
            PointerLockBridge.wantsLock = isPointerLockedGameplay
        }
    }

    private func setShowingSettings(_ showing: Bool) {
        guard isShowingSettings != showing else { return }
        if showing { isPaused = false; isShowingMissions = false }
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingSettings = showing
        }
        if showing {
            clearKeyboardMovement()
            desertScene.isInputBlocked = true
            PointerLockBridge.wantsLock = false
        } else {
            desertScene.isInputBlocked = false
            PointerLockBridge.wantsLock = isPointerLockedGameplay
        }
    }

    private func setShowingMissions(_ showing: Bool) {
        guard isShowingMissions != showing else { return }
        if showing { isPaused = false; isShowingSettings = false }
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingMissions = showing
        }
        if showing {
            clearKeyboardMovement()
            desertScene.isInputBlocked = true
            PointerLockBridge.wantsLock = false
        } else {
            desertScene.isInputBlocked = false
            PointerLockBridge.wantsLock = isPointerLockedGameplay
        }
    }

    private func ensureCallbacksWired() {
        guard !callbacksWired else { return }
        callbacksWired = true
        wireCallbacks()
    }

    private func onIntroFinished() {
        withAnimation(.easeOut(duration: 0.5)) { isShowingIntro = false }
        ensureCallbacksWired()
        if worldReady {
            withAnimation(.easeOut(duration: 0.45).delay(0.2)) { isLoadingWorld = false }
        }
        // If world not ready, WorldLoadingOverlay appears and onBuildComplete handles it.
    }

    private func saveMissions() {
        gameManager.updateProgress(slotIndex: slotIndex, missions: missionManager.exportedRecords)
    }

    private func clearKeyboardMovement() {
        pressedKeys.removeAll()
        runSources.remove(.shiftOrR)
        joystickOffset = .zero
        desertScene.setMoveInput(dx: 0, dy: 0)
        syncRunning()
    }

    private func applyKeyboardMoveInput() {
        var dx: Float = 0
        var dy: Float = 0
        if pressedKeys.contains(.moveLeft) { dx -= 1 }
        if pressedKeys.contains(.moveRight) { dx += 1 }
        if pressedKeys.contains(.moveForward) { dy += 1 }
        if pressedKeys.contains(.moveBack) { dy -= 1 }

        desertScene.setMoveInput(dx: dx, dy: dy)
        if dx != 0 || dy != 0 {
            savePositionDebounced()
        }
    }

    private func syncRunning() {
        let running = !runSources.isEmpty
        guard running != isRunningHeld else { return }
        isRunningHeld = running
        desertScene.setRunning(running)
    }

    private func handleHardwareKey(_ key: GameHardwareKey, isDown: Bool) {
        // Dialogue Esc/E are handled via SwiftUI onKeyPress so the text field can focus.
        guard !dialogueManager.isVisible else { return }
        guard !isLoadingWorld, !isSleeping else { return }

        if key == .escape {
            if isDown {
                if isShowingSettings {
                    setShowingSettings(false)
                } else if isShowingMissions {
                    setShowingMissions(false)
                } else {
                    setPaused(!isPaused)
                }
            }
            return
        }

        guard !isPaused else { return }

        switch key {
        case .moveForward:
            if isDown { pressedKeys.insert(.moveForward) } else { pressedKeys.remove(.moveForward) }
            applyKeyboardMoveInput()
        case .moveBack:
            if isDown { pressedKeys.insert(.moveBack) } else { pressedKeys.remove(.moveBack) }
            applyKeyboardMoveInput()
        case .moveLeft:
            if isDown { pressedKeys.insert(.moveLeft) } else { pressedKeys.remove(.moveLeft) }
            applyKeyboardMoveInput()
        case .moveRight:
            if isDown { pressedKeys.insert(.moveRight) } else { pressedKeys.remove(.moveRight) }
            applyKeyboardMoveInput()

        case .run:
            if isDown {
                runSources.insert(.shiftOrR)
            } else {
                runSources.remove(.shiftOrR)
            }
            syncRunning()

        case .jump:
            if isDown { desertScene.jump() }

        case .action:
            if isDown, let action = currentAction {
                performAction(action)
            }

        case .escape:
            break
        }
    }

    private var topInfoBar: some View {
        HStack(spacing: 8) {
            Button {
                setShowingSettings(true)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.4), in: Circle())
            }

            Button {
                missionManager.markAllSeen()
                saveMissions()
                setShowingMissions(true)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.4), in: Circle())

                    if missionManager.hasNewMissions {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 15, height: 15)
                            .background(Color(red: 1.0, green: 0.85, blue: 0.15), in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(duration: 0.3), value: missionManager.hasNewMissions)

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
            DispatchQueue.main.async {
                let key = "\(oasis.position.x)-\(oasis.position.z)"
                guard !oasisFoundSet.contains(key) else { return }
                oasisFoundSet.insert(key)

                let found = slot.oasisFound + 1
                gameManager.updateProgress(slotIndex: slotIndex, oasisFound: found)
                missionManager.complete("glimmer_in_dust")
                missionManager.unlock("oasis_remembers")
                saveMissions()
                showToast("Oasis found! (\(found))")
            }
        }

        desertScene.onWaterCollected = {
            carryingWater = true
            AudioManager.shared.play(.collect)
            gameManager.updateProgress(
                slotIndex: slotIndex,
                waterFound: slot.waterFound + 1,
                isCarryingWater: true
            )
            missionManager.unlock("glimmer_in_dust")
            saveMissions()
            showToast("Bucket filled — bring it to camp!")
        }

        desertScene.onWaterDelivered = { level, unlockedCompass, unlockedDetector, campId in
            carryingWater = false
            isNearBarrel = false
            AudioManager.shared.play(.deliver)
            if campId == "home" || desertScene.camp?.site.id == campId {
                campWaterLevel = level
            }

            let deliveries = slot.waterDeliveries + 1
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

            // Mission tracking for water delivery
            missionManager.complete("keeper_first_drop")
            if deliveries >= 5 { missionManager.complete("merchants_route") }
            saveMissions()

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
            DispatchQueue.main.async { withAnimation { isNearBarrel = near } }
        }

        desertScene.onNearWater = { near in
            DispatchQueue.main.async { withAnimation { isNearWater = near } }
        }

        desertScene.onNearBed = { near in
            DispatchQueue.main.async { withAnimation { isNearBed = near } }
        }

        desertScene.onNearSettingsTable = { near in
            // Table is flavour + a quiet shortcut into settings when tapped (handled in scene tap).
            _ = near
        }

        desertScene.onCampDrained = { level, campId in
            DispatchQueue.main.async {
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
        }

        desertScene.onOasisGrown = { campId, stage, progress, advanced in
            DispatchQueue.main.async {
                if campId == "home" {
                    oasisStage = stage
                    oasisProgress = progress
                    if stage >= .pond { missionManager.complete("ancient_trial") }
                    if stage == .lush { missionManager.complete("oasis_remembers") }
                    saveMissions()
                }
                persistCamp(campId)
                if advanced {
                    showToast("The oasis grows — \(stage.displayName)!")
                }
            }
        }

        desertScene.onCampDiscovered = { site in
            showToast("A new camp! Help them grow an oasis.")
            gameManager.updateProgress(
                slotIndex: slotIndex,
                campProgress: CampProgress(id: site.id)
            )
            // First remote camp found → unlock the mission; second → complete it.
            if missionManager.isActive("beyond_horizon") {
                missionManager.complete("beyond_horizon")
            } else {
                missionManager.unlock("beyond_horizon")
            }
            saveMissions()
        }

        desertScene.onTimeOfDayChanged = { t in
            DispatchQueue.main.async {
                timeOfDay = t
                gameManager.updateProgress(slotIndex: slotIndex, timeOfDay: t)
            }
        }

        desertScene.onWaterGivenToNPC = { npc in
            carryingWater = false
            dialogueManager.endConversation()
            gameManager.updateProgress(
                slotIndex: slotIndex,
                tasksCompleted: slot.tasksCompleted + 1,
                isCarryingWater: false
            )
            switch npc.personality {
            case .wanderer: missionManager.complete("wanderers_plea")
            case .lost:     missionManager.complete("lost_and_found")
            default: break
            }
            saveMissions()
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

    private func handleAnimalTap(_ animal: AnimalNode) {
        guard !isLoadingWorld, !isSleeping, !dialogueManager.isVisible else { return }
        if let player = desertScene.playerNode {
            let dx = animal.position.x - player.position.x
            let dz = animal.position.z - player.position.z
            let r = animal.interactionRadius
            guard dx * dx + dz * dz < r * r else { return }
        }
        animal.reactToTap()
        showToast(animal.kind.tapMessage)
    }

    private func handleBedTap() {
        guard !isLoadingWorld, !isSleeping, isNearBed else { return }
        guard canSleepNow else {
            showToast("Too early to sleep — wait until dusk.")
            return
        }
        startSleep()
    }

    private func startSleep() {
        guard !isSleeping, canSleepNow else { return }
        withAnimation { isSleeping = true }
        desertScene.beginSleep()
    }

    @ViewBuilder
    private func contextActionButton(for action: ActionKind) -> some View {
        Button { performAction(action) } label: {
            ZStack(alignment: .topTrailing) {
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

                if !showsOnScreenJoystick {
                    KeyCaptionBadge(label: "E")
                        .offset(x: 6, y: -4)
                }
            }
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
        AudioManager.shared.play(.toast)
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            await MainActor.run { withAnimation { toastMessage = nil } }
        }
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

// MARK: - Pause overlay

struct PauseOverlay: View {
    var onResume: () -> Void
    var onExitToCamp: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Text("Paused")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(.white)

                Text("Cursor unlocked — click Resume (or Esc), then click the game to capture the cursor again.")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    Button(action: onResume) {
                        HStack(spacing: 10) {
                            Text("Resume")
                                .font(.system(size: 17, weight: .bold, design: .serif))
                            KeyCaptionBadge(label: "Esc")
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.15, green: 0.50, blue: 0.80).opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button(action: onExitToCamp) {
                        Text("Back to Camp")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: 260)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.white.opacity(0.22), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
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

// MARK: - Hardware keyboard keys

enum GameHardwareKey: Hashable {
    case moveForward, moveBack, moveLeft, moveRight
    case run, jump, action, escape
}

// MARK: - SCNView wrapper

struct GameSceneView: UIViewRepresentable {
    let scene: DesertScene
    var acceptsKeyboard: Bool = true
    var pointerLookEnabled: Bool = true
    /// When true the on-screen joystick is visible; camera drag is restricted to the right portion of screen.
    var showsJoystick: Bool = false
    var onNPCTapped: ((NPCNode) -> Void)?
    var onAnimalTapped: ((AnimalNode) -> Void)?
    var onBedTapped: (() -> Void)?
    var onSettingsTableTapped: (() -> Void)?
    var onKeyDown: ((GameHardwareKey) -> Void)?
    var onKeyUp: ((GameHardwareKey) -> Void)?
    var onCameraDrag: ((Float, Float) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: scene)
    }

    func makeUIView(context: Context) -> GameSCNView {
        let v = GameSCNView()
        v.scene = scene
        v.delegate = context.coordinator
        v.allowsCameraControl = false
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.preferredFramesPerSecond = 60
        v.backgroundColor = UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)
        v.onKeyDown = { [weak coordinator = context.coordinator] key in
            coordinator?.onKeyDown?(key)
        }
        v.onKeyUp = { [weak coordinator = context.coordinator] key in
            coordinator?.onKeyUp?(key)
        }
        v.onCameraDrag = { [weak coordinator = context.coordinator] yaw, pitch in
            coordinator?.onCameraDrag?(yaw, pitch)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        v.addGestureRecognizer(tap)

        // Touch-only drag orbit (phones / direct finger).
        let pan = UIPanGestureRecognizer(target: v, action: #selector(GameSCNView.handleCameraPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.delegate = v
        v.cameraPanRecognizer = pan
        v.addGestureRecognizer(pan)
        context.coordinator.cameraPanGesture = pan

        // Pointer look (relative while pointer-locked on Mac / trackpad).
        let hover = UIHoverGestureRecognizer(target: v, action: #selector(GameSCNView.handleCameraHover(_:)))
        v.addGestureRecognizer(hover)

        return v
    }

    func updateUIView(_ uiView: GameSCNView, context: Context) {
        uiView.pointOfView = scene.activeCameraNode
        context.coordinator.scene = scene
        context.coordinator.onNPCTapped = onNPCTapped
        context.coordinator.onAnimalTapped = onAnimalTapped
        context.coordinator.onBedTapped = onBedTapped
        context.coordinator.onSettingsTableTapped = onSettingsTableTapped
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onKeyUp = onKeyUp
        context.coordinator.onCameraDrag = onCameraDrag
        uiView.onKeyDown = { [weak coordinator = context.coordinator] key in
            coordinator?.onKeyDown?(key)
        }
        uiView.onKeyUp = { [weak coordinator = context.coordinator] key in
            coordinator?.onKeyUp?(key)
        }
        uiView.onCameraDrag = { [weak coordinator = context.coordinator] yaw, pitch in
            coordinator?.onCameraDrag?(yaw, pitch)
        }
        uiView.pointerLookEnabled = pointerLookEnabled
        uiView.joystickVisible = showsJoystick
        uiView.setKeyboardCaptureEnabled(acceptsKeyboard)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var scene: DesertScene
        var onNPCTapped: ((NPCNode) -> Void)?
        var onAnimalTapped: ((AnimalNode) -> Void)?
        var onBedTapped: (() -> Void)?
        var onSettingsTableTapped: (() -> Void)?
        var onKeyDown: ((GameHardwareKey) -> Void)?
        var onKeyUp: ((GameHardwareKey) -> Void)?
        var onCameraDrag: ((Float, Float) -> Void)?
        var cameraPanGesture: UIPanGestureRecognizer?
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
                  let scnView = gesture.view as? GameSCNView,
                  !scene.isSleeping else { return }
            scnView.claimKeyboardFocus()
            guard scnView.pointerLookEnabled else { return }
            let point = gesture.location(in: scnView)
            let hits = scnView.hitTest(point, options: nil)
            for hit in hits {
                var node: SCNNode? = hit.node
                while let n = node {
                    if let npc = n as? NPCNode {
                        DispatchQueue.main.async { self.onNPCTapped?(npc) }
                        return
                    }
                    if let animal = n as? AnimalNode {
                        DispatchQueue.main.async { self.onAnimalTapped?(animal) }
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

/// Captures hardware keyboard for Mac (Designed for iPad) and iPad keyboards.
final class GameSCNView: SCNView, UIGestureRecognizerDelegate {
    var onKeyDown: ((GameHardwareKey) -> Void)?
    var onKeyUp: ((GameHardwareKey) -> Void)?
    var onCameraDrag: ((Float, Float) -> Void)?
    /// When false (dialogue / sleep / pause), ignore pointer look deltas.
    var pointerLookEnabled = true {
        didSet {
            if !pointerLookEnabled {
                lastHoverPoint = nil
                cancelCameraInertia()
            }
            bindMouseLook()
            if pointerLookEnabled {
                PointerLockBridge.refresh()
            }
        }
    }
    /// Set to true when the on-screen joystick is visible so camera orbit is
    /// restricted to the right portion of the screen (avoiding joystick area).
    var joystickVisible: Bool = false
    /// Reference to the camera pan recognizer; set by the UIViewRepresentable wrapper.
    var cameraPanRecognizer: UIPanGestureRecognizer?

    private var keyboardCaptureEnabled = true
    private var heldKeys: Set<GameHardwareKey> = []
    private var runKeyCount = 0
    private var lastPanPoint: CGPoint?
    private var lastHoverPoint: CGPoint?
    private var mouseObservers: [NSObjectProtocol] = []
    // Inertia state for touch orbit
    private var panVelocity: CGPoint = .zero
    private var inertiaActive = false

    private let pointerLookSensitivity: Float = 0.0045
    private let mouseLookSensitivity: Float = 0.0028

    override var canBecomeFirstResponder: Bool { keyboardCaptureEnabled }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if keyboardCaptureEnabled {
                claimKeyboardFocus()
            }
            startMouseMonitoring()
            bindMouseLook()
        } else {
            stopMouseMonitoring()
        }
    }

    deinit {
        stopMouseMonitoring()
    }

    func setKeyboardCaptureEnabled(_ enabled: Bool) {
        keyboardCaptureEnabled = enabled
        if enabled {
            claimKeyboardFocus()
        } else {
            releaseAllKeys()
            lastHoverPoint = nil
            resignFirstResponder()
        }
    }

    func claimKeyboardFocus() {
        guard keyboardCaptureEnabled else { return }
        _ = becomeFirstResponder()
        if pointerLookEnabled {
            PointerLockBridge.refresh()
        }
    }

    private func startMouseMonitoring() {
        guard mouseObservers.isEmpty else { return }
        let center = NotificationCenter.default
        mouseObservers = [
            center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] _ in
                self?.bindMouseLook()
            },
            center.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                self?.bindMouseLook()
            },
        ]
        bindMouseLook()
    }

    private func stopMouseMonitoring() {
        mouseObservers.forEach(NotificationCenter.default.removeObserver)
        mouseObservers.removeAll()
        GCMouse.mice().forEach { $0.mouseInput?.mouseMovedHandler = nil }
    }

    private func bindMouseLook() {
        for mouse in GCMouse.mice() {
            mouse.mouseInput?.mouseMovedHandler = { [weak self] (_: GCMouseInput, deltaX: Float, deltaY: Float) in
                guard let self, self.pointerLookEnabled else { return }
                let dx = deltaX * self.mouseLookSensitivity
                let dy = deltaY * self.mouseLookSensitivity
                if abs(dx) > 0.0001 || abs(dy) > 0.0001 {
                    self.onCameraDrag?(dx, -dy)
                }
            }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let mapped = mapKey(press.key) else { continue }
            handled = true
            beginKey(mapped)
        }
        if handled { return }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let mapped = mapKey(press.key) else { continue }
            handled = true
            endKey(mapped)
        }
        if handled { return }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let mapped = mapKey(press.key) else { continue }
            handled = true
            endKey(mapped)
        }
        if handled { return }
        super.pressesCancelled(presses, with: event)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === cameraPanRecognizer, joystickVisible else { return true }
        // When joystick is on-screen, only allow camera orbit from the right 55% of the view
        // so the joystick area (bottom-left) doesn't trigger spurious camera movement.
        return touch.location(in: self).x > bounds.width * 0.45
    }

    @objc func handleCameraPan(_ gesture: UIPanGestureRecognizer) {
        guard pointerLookEnabled else {
            lastPanPoint = nil
            cancelCameraInertia()
            return
        }
        switch gesture.state {
        case .began:
            cancelCameraInertia()
            lastPanPoint = gesture.translation(in: self)
        case .changed:
            let point = gesture.translation(in: self)
            let last = lastPanPoint ?? point
            let rawDx = point.x - last.x
            let rawDy = point.y - last.y
            lastPanPoint = point
            panVelocity = CGPoint(x: rawDx, y: rawDy)
            let (dx, dy) = touchCameraDelta(dx: rawDx, dy: rawDy)
            onCameraDrag?(dx, -dy)
        case .ended:
            lastPanPoint = nil
            let v = gesture.velocity(in: self)
            panVelocity = v
            beginCameraInertia()
        default:
            lastPanPoint = nil
            cancelCameraInertia()
        }
    }

    /// Converts a raw touch delta (points) to camera yaw/pitch deltas (radians),
    /// normalised to screen size so sensitivity is consistent on iPhone and iPad.
    private func touchCameraDelta(dx: CGFloat, dy: CGFloat) -> (Float, Float) {
        let w = max(320, bounds.width)
        let h = max(320, bounds.height)
        return (Float(dx / w) * .pi * 1.6, Float(dy / h) * .pi * 1.2)
    }

    private func beginCameraInertia() {
        let threshold: CGFloat = 12
        guard abs(panVelocity.x) > threshold || abs(panVelocity.y) > threshold else {
            panVelocity = .zero
            return
        }
        inertiaActive = true
        scheduleInertiaStep()
    }

    private func cancelCameraInertia() {
        inertiaActive = false
        panVelocity = .zero
    }

    private func scheduleInertiaStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            self?.inertiaStep()
        }
    }

    private func inertiaStep() {
        guard inertiaActive, pointerLookEnabled else {
            cancelCameraInertia()
            return
        }
        // Decay: velocity reaches ~5% after ≈1 second at 60fps
        panVelocity.x *= 0.90
        panVelocity.y *= 0.90

        let threshold: CGFloat = 6
        guard abs(panVelocity.x) > threshold || abs(panVelocity.y) > threshold else {
            cancelCameraInertia()
            return
        }

        // velocity is in pts/sec; divide by 60 for one frame's worth
        let (dx, dy) = touchCameraDelta(dx: panVelocity.x / 60, dy: panVelocity.y / 60)
        onCameraDrag?(dx, -dy)
        scheduleInertiaStep()
    }

    @objc func handleCameraHover(_ gesture: UIHoverGestureRecognizer) {
        // Prefer GCMouse relative deltas while locked; hover is a fallback.
        guard !PointerLockBridge.isSystemLocked else {
            lastHoverPoint = nil
            return
        }
        switch gesture.state {
        case .began:
            lastHoverPoint = gesture.location(in: self)
        case .changed:
            guard pointerLookEnabled else {
                lastHoverPoint = gesture.location(in: self)
                return
            }
            let point = gesture.location(in: self)
            defer { lastHoverPoint = point }
            guard let last = lastHoverPoint else { return }
            let dx = Float(point.x - last.x) * pointerLookSensitivity
            let dy = Float(point.y - last.y) * pointerLookSensitivity
            if abs(dx) > 0.0001 || abs(dy) > 0.0001 {
                onCameraDrag?(dx, -dy)
            }
        case .ended, .cancelled:
            lastHoverPoint = nil
        default:
            break
        }
    }

    private func beginKey(_ key: GameHardwareKey) {
        if key == .run {
            runKeyCount += 1
            if runKeyCount == 1 {
                heldKeys.insert(.run)
                onKeyDown?(.run)
            }
            return
        }
        guard !heldKeys.contains(key) else { return }
        heldKeys.insert(key)
        onKeyDown?(key)
    }

    private func endKey(_ key: GameHardwareKey) {
        if key == .run {
            runKeyCount = max(0, runKeyCount - 1)
            if runKeyCount == 0, heldKeys.remove(.run) != nil {
                onKeyUp?(.run)
            }
            return
        }
        if heldKeys.remove(key) != nil {
            onKeyUp?(key)
        }
    }

    private func releaseAllKeys() {
        let keys = heldKeys
        heldKeys.removeAll()
        runKeyCount = 0
        for key in keys {
            onKeyUp?(key)
        }
    }

    private func mapKey(_ key: UIKey?) -> GameHardwareKey? {
        guard let key else { return nil }
        switch key.keyCode {
        case .keyboardW, .keyboardUpArrow: return .moveForward
        case .keyboardS, .keyboardDownArrow: return .moveBack
        case .keyboardA, .keyboardLeftArrow: return .moveLeft
        case .keyboardD, .keyboardRightArrow: return .moveRight
        case .keyboardLeftShift, .keyboardRightShift, .keyboardR: return .run
        case .keyboardSpacebar: return .jump
        case .keyboardE: return .action
        case .keyboardEscape: return .escape
        default:
            break
        }
        let chars = key.charactersIgnoringModifiers.lowercased()
        switch chars {
        case "w": return .moveForward
        case "s": return .moveBack
        case "a": return .moveLeft
        case "d": return .moveRight
        case "e": return .action
        case "r": return .run
        case " ": return .jump
        default: return nil
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

private struct KeyCaptionBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, label.count > 2 ? 5 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
    }
}

struct TapActionButton: View {
    let systemName: String
    var keyLabel: String? = nil
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.38), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1.5))

                if let keyLabel {
                    KeyCaptionBadge(label: keyLabel)
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct HoldActionButton: View {
    let systemName: String
    var keyLabel: String? = nil
    var isActive: Bool
    var activeColor: Color = .orange
    var onHoldChanged: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isActive ? .white : .white.opacity(0.9))
                .frame(width: 64, height: 64)
                .background(
                    (isActive ? activeColor.opacity(0.75) : Color.black.opacity(0.38)),
                    in: Circle()
                )
                .overlay(Circle().stroke(.white.opacity(isActive ? 0.55 : 0.28), lineWidth: 1.5))

            if let keyLabel {
                KeyCaptionBadge(label: keyLabel)
                    .offset(x: 6, y: -4)
            }
        }
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
