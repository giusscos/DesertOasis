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
    static let slotCount = 3

    var currentScreen: GameScreen = .title
    var saveSlots: [SaveSlot] = (0..<GameManager.slotCount).map { SaveSlot(id: $0) }
    var musicEnabled: Bool = true
    var soundEnabled: Bool = true
    /// Visible sun, moon, and clouds — disable for weaker devices.
    var skyDetailsEnabled: Bool = true
    /// Mac only: click-and-drag orbit with a visible cursor (off = pointer-locked mouse look).
    var macClickDragCamera: Bool = false
    /// Mac only: invert camera pitch while orbiting.
    var invertCameraVertical: Bool = false

    #if DEBUG
    /// Live FPS readout while playing.
    var showFPSOverlay: Bool = false
    /// Accumulate avg / min / max FPS and stability while enabled.
    var benchmarkEnabled: Bool = false
    /// World markers + HUD for undiscovered camping zones.
    var showCampZoneDebug: Bool = false
    #endif

    /// Designed for iPad on Mac, or Mac Catalyst.
    static var isMacPlatform: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    private let slotsKey = "DesertOasis_SaveSlots"
    private let musicKey = "DesertOasis_Music"
    private let soundKey = "DesertOasis_Sound"
    private let skyDetailsKey = "DesertOasis_SkyDetails"
    private let macClickDragCameraKey = "DesertOasis_MacClickDragCamera"
    private let invertCameraVerticalKey = "DesertOasis_InvertCameraVertical"
    #if DEBUG
    private let showFPSKey = "DesertOasis_DebugShowFPS"
    private let benchmarkKey = "DesertOasis_DebugBenchmark"
    private let campZoneDebugKey = "DesertOasis_DebugCampZones"
    #endif

    var gameCenter = GameCenterManager()
    @ObservationIgnored private var kvStoreObserver: NSObjectProtocol?

    init() {
        loadAll()
        gameCenter.authenticate()
        kvStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSlotsFromCloud()
        }
    }

    /// Always returns exactly `slotCount` slots so UI/game indexing cannot trap.
    private static func normalizedSlots(_ decoded: [SaveSlot]) -> [SaveSlot] {
        var result = (0..<slotCount).map { SaveSlot(id: $0) }
        for slot in decoded where (0..<slotCount).contains(slot.id) {
            result[slot.id] = slot
        }
        return result
    }

    private func isValidSlotIndex(_ index: Int) -> Bool {
        saveSlots.indices.contains(index)
    }

    // MARK: - Persistence

    private func loadAll() {
        musicEnabled = UserDefaults.standard.object(forKey: musicKey) as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
        skyDetailsEnabled = UserDefaults.standard.object(forKey: skyDetailsKey) as? Bool ?? true
        macClickDragCamera = UserDefaults.standard.object(forKey: macClickDragCameraKey) as? Bool ?? false
        invertCameraVertical = UserDefaults.standard.object(forKey: invertCameraVerticalKey) as? Bool ?? false
        #if DEBUG
        showFPSOverlay = UserDefaults.standard.object(forKey: showFPSKey) as? Bool ?? false
        benchmarkEnabled = UserDefaults.standard.object(forKey: benchmarkKey) as? Bool ?? false
        showCampZoneDebug = UserDefaults.standard.object(forKey: campZoneDebugKey) as? Bool ?? false
        #endif
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.synchronize()
        if let data = kvStore.data(forKey: slotsKey),
           let slots = try? JSONDecoder().decode([SaveSlot].self, from: data) {
            saveSlots = Self.normalizedSlots(slots)
            if slots.count != Self.slotCount || slots.contains(where: { !((0..<Self.slotCount).contains($0.id)) }) {
                persistSlots()
            }
        } else if let data = UserDefaults.standard.data(forKey: slotsKey),
                  let slots = try? JSONDecoder().decode([SaveSlot].self, from: data) {
            // One-time migration from UserDefaults on first launch.
            saveSlots = Self.normalizedSlots(slots)
            persistSlots()
        }
    }

    func persistSlots() {
        guard let data = try? JSONEncoder().encode(saveSlots) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: slotsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func persistSettings() {
        UserDefaults.standard.set(musicEnabled, forKey: musicKey)
        UserDefaults.standard.set(soundEnabled, forKey: soundKey)
        UserDefaults.standard.set(skyDetailsEnabled, forKey: skyDetailsKey)
        UserDefaults.standard.set(macClickDragCamera, forKey: macClickDragCameraKey)
        UserDefaults.standard.set(invertCameraVertical, forKey: invertCameraVerticalKey)
        #if DEBUG
        UserDefaults.standard.set(showFPSOverlay, forKey: showFPSKey)
        UserDefaults.standard.set(benchmarkEnabled, forKey: benchmarkKey)
        UserDefaults.standard.set(showCampZoneDebug, forKey: campZoneDebugKey)
        #endif
    }

    private func reloadSlotsFromCloud() {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: slotsKey),
              let synced = try? JSONDecoder().decode([SaveSlot].self, from: data)
        else { return }
        let normalized = Self.normalizedSlots(synced)
        for i in saveSlots.indices {
            if case .playing(let activeIdx) = currentScreen, activeIdx == i { continue }
            saveSlots[i] = normalized[i]
        }
    }

    // MARK: - Slot actions

    func startNewGame(slotIndex: Int, gender: SaveSlot.CharacterGender) {
        guard isValidSlotIndex(slotIndex) else { return }
        let now = Date()
        saveSlots[slotIndex] = SaveSlot(id: slotIndex)
        saveSlots[slotIndex].characterGender = gender
        saveSlots[slotIndex].playerName = SaveSlot.timestampName(from: now)
        saveSlots[slotIndex].lastUpdated = now
        persistSlots()
        currentScreen = .playing(slotIndex: slotIndex)
    }

    func continueGame(slotIndex: Int) {
        guard isValidSlotIndex(slotIndex) else { return }
        saveSlots[slotIndex].lastUpdated = Date()
        persistSlots()
        currentScreen = .playing(slotIndex: slotIndex)
    }

    func deleteSlot(_ index: Int) {
        guard isValidSlotIndex(index) else { return }
        saveSlots[index] = SaveSlot(id: index)
        persistSlots()
    }

    func updateProgress(
        slotIndex: Int,
        waterFound: Int? = nil,
        oasisFound: Int? = nil,
        tasksCompleted: Int? = nil,
        campWaterLevel: Float? = nil,
        waterDeliveries: Int? = nil,
        isCarryingWater: Bool? = nil,
        hasWaterCompass: Bool? = nil,
        hasWaterDetector: Bool? = nil,
        posX: Float? = nil,
        posZ: Float? = nil,
        timeOfDay: Float? = nil,
        campProgress: CampProgress? = nil,
        missions: [MissionRecord]? = nil,
        equippedTool: String? = nil,
        hasLantern: Bool? = nil,
        tradeBeads: Int? = nil,
        trinkets: [String]? = nil,
        achievements: [String]? = nil,
        diaryPages: [String]? = nil,
        helpedWanderers: Int? = nil,
        helpedLost: Int? = nil,
        helperAnimalKind: String?? = nil,
        clearHelperAnimal: Bool = false,
        isHelperCarryingWater: Bool? = nil,
        helperCarriedBuckets: Int? = nil,
        sleepsCompleted: Int? = nil,
        pendingWildNPCRespawns: [PendingNPCRespawn]? = nil,
        discoveredLandmarks: [String]? = nil,
        hasCampTrinket: Bool? = nil,
        mapScrapsOwned: Int? = nil,
        nextCampHint: String? = nil
    ) {
        guard isValidSlotIndex(slotIndex) else { return }
        if let w = waterFound       { saveSlots[slotIndex].waterFound       = w }
        if let o = oasisFound {
            saveSlots[slotIndex].oasisFound = o
            gameCenter.submitScore(o, toLeaderboard: GameCenterManager.Leaderboard.oasesFound)
        }
        if let t = tasksCompleted   { saveSlots[slotIndex].tasksCompleted   = t }
        if let c = campWaterLevel   {
            saveSlots[slotIndex].campWaterLevel = c
            var home = saveSlots[slotIndex].progress(forCampId: "home")
            home.waterLevel = c
            saveSlots[slotIndex].upsertCampProgress(home)
        }
        if let d = waterDeliveries {
            saveSlots[slotIndex].waterDeliveries = d
            gameCenter.submitScore(d, toLeaderboard: GameCenterManager.Leaderboard.waterDeliveries)
        }
        if let carrying = isCarryingWater { saveSlots[slotIndex].isCarryingWater = carrying }
        if let compass = hasWaterCompass { saveSlots[slotIndex].hasWaterCompass = compass }
        if let detector = hasWaterDetector { saveSlots[slotIndex].hasWaterDetector = detector }
        if let x = posX             { saveSlots[slotIndex].playerPositionX  = x }
        if let z = posZ             { saveSlots[slotIndex].playerPositionZ  = z }
        if let tod = timeOfDay      { saveSlots[slotIndex].timeOfDay        = tod }
        if let cp = campProgress    { saveSlots[slotIndex].upsertCampProgress(cp) }
        if let m = missions         { saveSlots[slotIndex].missions = m }
        if let et = equippedTool    { saveSlots[slotIndex].equippedTool = et }
        if let hl = hasLantern      { saveSlots[slotIndex].hasLantern = hl }
        if let tb = tradeBeads      { saveSlots[slotIndex].tradeBeads = tb }
        if let tr = trinkets        { saveSlots[slotIndex].trinkets = tr }
        if let ach = achievements   { saveSlots[slotIndex].achievements = ach }
        if let dp = diaryPages      { saveSlots[slotIndex].diaryPages = dp }
        if let hw = helpedWanderers {
            saveSlots[slotIndex].helpedWanderers = hw
            gameCenter.submitScore(hw, toLeaderboard: GameCenterManager.Leaderboard.wanderers)
        }
        if let hlost = helpedLost   { saveSlots[slotIndex].helpedLost = hlost }
        if clearHelperAnimal {
            saveSlots[slotIndex].helperAnimalKind = nil
            saveSlots[slotIndex].helperCarriedBuckets = 0
            saveSlots[slotIndex].isHelperCarryingWater = false
        } else if let wrapped = helperAnimalKind {
            saveSlots[slotIndex].helperAnimalKind = wrapped
        }
        if let buckets = helperCarriedBuckets {
            saveSlots[slotIndex].helperCarriedBuckets = max(0, buckets)
            saveSlots[slotIndex].isHelperCarryingWater = buckets > 0
        } else if let hc = isHelperCarryingWater {
            saveSlots[slotIndex].isHelperCarryingWater = hc
            saveSlots[slotIndex].helperCarriedBuckets = hc
                ? max(1, saveSlots[slotIndex].helperCarriedBuckets)
                : 0
        }
        if let sc = sleepsCompleted { saveSlots[slotIndex].sleepsCompleted = sc }
        if let pr = pendingWildNPCRespawns { saveSlots[slotIndex].pendingWildNPCRespawns = pr }
        if let dl = discoveredLandmarks { saveSlots[slotIndex].discoveredLandmarks = dl }
        if let ct = hasCampTrinket  { saveSlots[slotIndex].hasCampTrinket = ct }
        if let ms = mapScrapsOwned  { saveSlots[slotIndex].mapScrapsOwned = ms }
        if let hint = nextCampHint  { saveSlots[slotIndex].nextCampHint = hint }
        saveSlots[slotIndex].lastUpdated = Date()
        persistSlots()
    }

    var activeSlot: SaveSlot? {
        if case .playing(let idx) = currentScreen, isValidSlotIndex(idx) {
            return saveSlots[idx]
        }
        return nil
    }

    var activeSlotIndex: Int? {
        if case .playing(let idx) = currentScreen, isValidSlotIndex(idx) {
            return idx
        }
        return nil
    }

    /// Safe slot lookup for UI / game views that index by slot number.
    func slot(at index: Int) -> SaveSlot? {
        guard isValidSlotIndex(index) else { return nil }
        return saveSlots[index]
    }
}
