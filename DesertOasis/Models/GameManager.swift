import Foundation
import Observation

enum GameScreen: Equatable {
    case title
    case slotSelection
    case characterCreation(slotIndex: Int)
    case playing(slotIndex: Int)
    case settings
}

@Observable
final class GameManager {
    var currentScreen: GameScreen = .title
    var saveSlots: [SaveSlot] = [SaveSlot(id: 0), SaveSlot(id: 1), SaveSlot(id: 2)]
    var musicEnabled: Bool = true
    var soundEnabled: Bool = true

    private let slotsKey = "DesertOasis_SaveSlots"
    private let musicKey = "DesertOasis_Music"
    private let soundKey = "DesertOasis_Sound"

    init() {
        loadAll()
    }

    // MARK: - Persistence

    private func loadAll() {
        musicEnabled = UserDefaults.standard.object(forKey: musicKey) as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
        guard let data = UserDefaults.standard.data(forKey: slotsKey),
              let slots = try? JSONDecoder().decode([SaveSlot].self, from: data)
        else { return }
        saveSlots = slots
    }

    func persistSlots() {
        guard let data = try? JSONEncoder().encode(saveSlots) else { return }
        UserDefaults.standard.set(data, forKey: slotsKey)
    }

    func persistSettings() {
        UserDefaults.standard.set(musicEnabled, forKey: musicKey)
        UserDefaults.standard.set(soundEnabled, forKey: soundKey)
    }

    // MARK: - Slot actions

    func startNewGame(slotIndex: Int, gender: SaveSlot.CharacterGender) {
        let now = Date()
        saveSlots[slotIndex] = SaveSlot(id: slotIndex)
        saveSlots[slotIndex].characterGender = gender
        saveSlots[slotIndex].playerName = SaveSlot.timestampName(from: now)
        saveSlots[slotIndex].lastUpdated = now
        persistSlots()
        currentScreen = .playing(slotIndex: slotIndex)
    }

    func continueGame(slotIndex: Int) {
        saveSlots[slotIndex].lastUpdated = Date()
        persistSlots()
        currentScreen = .playing(slotIndex: slotIndex)
    }

    func deleteSlot(_ index: Int) {
        saveSlots[index] = SaveSlot(id: index)
        persistSlots()
    }

    func updateProgress(slotIndex: Int, waterFound: Int? = nil, oasisFound: Int? = nil,
                        tasksCompleted: Int? = nil, posX: Float? = nil, posZ: Float? = nil) {
        if let w = waterFound      { saveSlots[slotIndex].waterFound      = w }
        if let o = oasisFound      { saveSlots[slotIndex].oasisFound      = o }
        if let t = tasksCompleted  { saveSlots[slotIndex].tasksCompleted  = t }
        if let x = posX            { saveSlots[slotIndex].playerPositionX = x }
        if let z = posZ            { saveSlots[slotIndex].playerPositionZ = z }
        saveSlots[slotIndex].lastUpdated = Date()
        persistSlots()
    }

    var activeSlot: SaveSlot? {
        if case .playing(let idx) = currentScreen { return saveSlots[idx] }
        return nil
    }

    var activeSlotIndex: Int? {
        if case .playing(let idx) = currentScreen { return idx }
        return nil
    }
}
