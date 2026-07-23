import SwiftUI

struct LobbyContainerView: View {
    @Bindable var gameManager: GameManager
    @State private var lobbyScene = LobbyScene()
    @State private var cameraState: LobbyCameraState = .title
    @State private var pendingSlotIndex: Int? = nil

    var body: some View {
        ZStack {
            LobbySceneView(
                scene: lobbyScene,
                onDiaryTapped: handleDiaryTap,
                onSettingsTapped: handleSettingsTap,
                onCharacterTapped: handleCharacterTap,
                onBackgroundTapped: handleBackgroundTap
            )
            .ignoresSafeArea()

            overlayContent
        }
    }

    // MARK: - Overlay routing

    @ViewBuilder
    private var overlayContent: some View {
        switch cameraState {
        case .title:
            TitleOverlayView(onTapToContinue: moveToSlots)

        case .slotSelection:
            SlotSelectionOverlayView(
                gameManager: gameManager,
                onSlotSelected: { idx in handleSlotSelect(idx) },
                onBack: moveToTitle,
                onSettings: moveToSettings
            )

        case .characterSelection:
            CharacterSelectionOverlayView(
                onSelect: chooseCharacter,
                onBack: moveToSlotsFromCharacterSelection
            )

        case .settings:
            SettingsOverlayView(
                gameManager: gameManager,
                onBack: moveToTitle,
                onGoToBed: moveToSlots
            )
        }
    }

    // MARK: - Camera transitions

    private func moveToTitle() {
        lobbyScene.closeAllDiaries()
        lobbyScene.resetCharactersToExit()
        lobbyScene.animateCamera(to: .title)
        withAnimation { cameraState = .title }
        pendingSlotIndex = nil
    }

    private func moveToSlots() {
        lobbyScene.resetCharactersToExit()
        lobbyScene.animateCamera(to: .slotSelection)
        withAnimation(.easeInOut(duration: 1.6)) { cameraState = .slotSelection }
        pendingSlotIndex = nil
    }

    private func moveToSlotsFromCharacterSelection() {
        lobbyScene.resetCharactersToExit()
        lobbyScene.animateCamera(to: .slotSelection)
        withAnimation(.easeInOut(duration: 1.6)) { cameraState = .slotSelection }
        pendingSlotIndex = nil
    }

    private func moveToCharacterSelection(slotIndex: Int) {
        pendingSlotIndex = slotIndex
        lobbyScene.animateCamera(to: .characterSelection)
        lobbyScene.presentCharactersForSelection(duration: 1.2)
        withAnimation(.easeInOut(duration: 1.6)) { cameraState = .characterSelection }
    }

    private func moveToSettings() {
        lobbyScene.closeAllDiaries()
        lobbyScene.resetCharactersToExit()
        lobbyScene.animateCamera(to: .settings)
        withAnimation(.easeInOut(duration: 1.6)) { cameraState = .settings }
        pendingSlotIndex = nil
    }

    // MARK: - Tap handlers

    private func handleBackgroundTap() {
        switch cameraState {
        case .title:
            moveToSlots()
        case .slotSelection, .characterSelection, .settings:
            break
        }
    }

    private func handleDiaryTap(_ index: Int) {
        guard cameraState == .slotSelection else {
            if cameraState == .title { moveToSlots() }
            return
        }
        handleSlotSelect(index)
    }

    private func handleSettingsTap() {
        guard cameraState != .settings, cameraState != .characterSelection else { return }
        moveToSettings()
    }

    private func handleCharacterTap(_ gender: SaveSlot.CharacterGender) {
        guard cameraState == .characterSelection else { return }
        chooseCharacter(gender)
    }

    private func handleSlotSelect(_ index: Int) {
        lobbyScene.openDiary(at: index) {
            let slot = self.gameManager.saveSlots[index]
            if slot.isEmpty {
                self.moveToCharacterSelection(slotIndex: index)
            } else {
                self.gameManager.continueGame(slotIndex: index)
            }
        }
    }

    private func chooseCharacter(_ gender: SaveSlot.CharacterGender) {
        guard let idx = pendingSlotIndex else { return }
        gameManager.startNewGame(slotIndex: idx, gender: gender)
    }
}

// MARK: - Title Overlay

struct TitleOverlayView: View {
    var onTapToContinue: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("Touch to Begin")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.8), radius: 4)
            }
            .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapToContinue() }
    }
}

// MARK: - Slot Selection Overlay

struct SlotSelectionOverlayView: View {
    @Bindable var gameManager: GameManager
    var onSlotSelected: (Int) -> Void
    var onBack: () -> Void
    var onSettings: () -> Void

    @State private var showDeleteConfirm = false
    @State private var deleteIndex: Int? = nil

    var body: some View {
        VStack {
            // Top bar
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        AudioManager.shared.play(.uiTap)
                        gameManager.musicEnabled.toggle()
                        gameManager.persistSettings()
                    } label: {
                        Image(systemName: gameManager.musicEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }

                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Slot cards
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("Choose Your Adventure")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                    Text("Open a diary on the bed")
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.55))
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<3) { idx in
                        SlotCardView(slot: gameManager.saveSlots[idx], slotIndex: idx) {
                            onSlotSelected(idx)
                        } onDelete: {
                            deleteIndex = idx
                            showDeleteConfirm = true
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 20)
        }
        .alert("Delete Save?", isPresented: $showDeleteConfirm, presenting: deleteIndex) { idx in
            Button("Delete", role: .destructive) { gameManager.deleteSlot(idx) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This save file will be permanently deleted.")
        }
    }
}

// MARK: - Slot Card View

struct SlotCardView: View {
    let slot: SaveSlot
    let slotIndex: Int
    var onSelect: () -> Void
    var onDelete: () -> Void

    private var accent: Color { Color(red: 0.92, green: 0.75, blue: 0.30) }
    private var panelFill: Color { Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.78) }

    private var journalLabel: String {
        ["I", "II", "III"][slotIndex]
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                if slot.isEmpty {
                    emptyContent
                } else {
                    filledContent
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 168)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Text("JOURNAL \(journalLabel)")
                .font(.system(size: 10, weight: .bold, design: .serif))
                .tracking(1.6)
                .foregroundStyle(accent.opacity(0.75))

            ZStack {
                Circle()
                    .strokeBorder(accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 52, height: 52)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 3) {
                Text("New Journey")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Blank pages await")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
    }

    private var filledContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text("JOURNAL \(journalLabel)")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .tracking(1.6)
                    .foregroundStyle(accent.opacity(0.85))
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(7)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 46, height: 46)
                Circle()
                    .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 46, height: 46)
                Image(systemName: genderSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 2) {
                Text(travelerLabel)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text(slot.displayName)
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(spacing: 5) {
                slotStatBadge(icon: "drop.fill", value: slot.waterFound, color: Color(red: 0.35, green: 0.72, blue: 0.95))
                slotStatBadge(icon: "sun.max.fill", value: slot.oasisFound, color: .orange)
                slotStatBadge(icon: "checkmark.circle.fill", value: slot.tasksCompleted, color: Color(red: 0.35, green: 0.82, blue: 0.52))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var travelerLabel: String {
        switch slot.characterGender {
        case .man: "Wanderer"
        case .woman: "Explorer"
        case .none: "Traveler"
        }
    }

    private var genderSymbol: String {
        switch slot.characterGender {
        case .man: "figure.stand"
        case .woman: "figure.stand.dress"
        case .none: "person.fill"
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(panelFill)
            .overlay {
                if slot.isEmpty {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [accent.opacity(0.55), accent.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func slotStatBadge(icon: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(value)")
                .foregroundStyle(.white)
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

// MARK: - Character Selection (in-scene)

struct CharacterSelectionOverlayView: View {
    var onSelect: (SaveSlot.CharacterGender) -> Void
    var onBack: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 16) {
                Text("Who will you be?")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black, radius: 4)

                Text("Tap a traveler to begin")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.white.opacity(0.55))

                HStack(spacing: 20) {
                    ForEach(SaveSlot.CharacterGender.allCases, id: \.self) { gender in
                        Button {
                            onSelect(gender)
                        } label: {
                            Text(gender.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(Color(red: 0.15, green: 0.1, blue: 0.05))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.92, green: 0.75, blue: 0.3))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Settings Overlay

struct SettingsOverlayView: View {
    @Bindable var gameManager: GameManager
    var onBack: () -> Void
    /// When set (lobby), shows a bed button opposite the chevron to move the camera to slot selection.
    var onGoToBed: (() -> Void)? = nil
    /// When set (game view only), shows a button to leave the run and return to the title screen.
    var onReturnToMainScreen: (() -> Void)? = nil

    var body: some View {
        VStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
                if let onGoToBed {
                    Button(action: onGoToBed) {
                        Image(systemName: "bed.double.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 0) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)

                VStack(spacing: 1) {
                    settingRow(title: "Music", icon: "music.note", isOn: $gameManager.musicEnabled)
                    settingRow(title: "Sound Effects", icon: "speaker.wave.2", isOn: $gameManager.soundEnabled)
                    settingRow(title: "Sky Details", icon: "cloud.sun", isOn: $gameManager.skyDetailsEnabled)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let onReturnToMainScreen {
                    Button(action: onReturnToMainScreen) {
                        HStack {
                            Image(systemName: "house")
                                .frame(width: 24)
                                .foregroundStyle(.orange)
                            Text("Back to Main Screen")
                                .font(.system(size: 16, design: .serif))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }

                Text("Desert Oasis  v1.0")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func settingRow(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.orange)
            Text(title)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(.orange)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    AudioManager.shared.play(.uiTap)
                    gameManager.persistSettings()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.black.opacity(0.5))
    }
}
