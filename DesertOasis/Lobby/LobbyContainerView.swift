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
                onBack: moveToSlots
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
            VStack(spacing: 8) {
                Text("Choose Your Adventure")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(color: .black, radius: 3)

                HStack(spacing: 12) {
                    ForEach(0..<3) { idx in
                        SlotCardView(slot: gameManager.saveSlots[idx]) {
                            onSlotSelected(idx)
                        } onDelete: {
                            deleteIndex = idx
                            showDeleteConfirm = true
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
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
    var onSelect: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                if slot.isEmpty {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("New Game")
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(slot.characterGender?.emoji ?? "")
                        .font(.system(size: 28))
                    Text(slot.displayName)
                        .font(.system(size: 11, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    VStack(spacing: 2) {
                        statRow(icon: "drop.fill", value: "\(slot.waterFound)")
                        statRow(icon: "sun.max.fill", value: "\(slot.oasisFound)")
                        statRow(icon: "checkmark.circle", value: "\(slot.tasksCompleted)")
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(slot.isEmpty ? .white.opacity(0.2) : .white.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statRow(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value)
                .font(.system(size: 10))
        }
        .foregroundStyle(.white.opacity(0.7))
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

            VStack(spacing: 0) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)

                VStack(spacing: 1) {
                    settingRow(title: "Music", icon: "music.note", isOn: $gameManager.musicEnabled)
                    settingRow(title: "Sound Effects", icon: "speaker.wave.2", isOn: $gameManager.soundEnabled)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

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
                .onChange(of: isOn.wrappedValue) { _, _ in gameManager.persistSettings() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.black.opacity(0.5))
    }
}
