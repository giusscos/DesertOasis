import Foundation

struct SaveSlot: Codable, Identifiable {
    let id: Int
    var characterGender: CharacterGender?
    var playerName: String?
    var lastUpdated: Date?
    var waterFound: Int
    var oasisFound: Int
    var tasksCompleted: Int
    /// Water delivered to the home camp barrel (0…1). Mirrored into campProgress["home"].
    var campWaterLevel: Float
    var waterDeliveries: Int
    var isCarryingWater: Bool
    var hasWaterCompass: Bool
    var hasWaterDetector: Bool
    var desertSeed: UInt64
    var playerPositionX: Float
    var playerPositionZ: Float
    /// Day clock 0…1 (0 = midnight, 0.5 = noon).
    var timeOfDay: Float
    /// Per-camp water + oasis growth.
    var campProgress: [CampProgress]

    var isEmpty: Bool { characterGender == nil }

    var displayName: String {
        if let playerName, !playerName.isEmpty { return playerName }
        if let lastUpdated { return Self.timestampName(from: lastUpdated) }
        return "Save \(id + 1)"
    }

    init(id: Int) {
        self.id = id
        characterGender = nil
        playerName = nil
        lastUpdated = nil
        waterFound = 0
        oasisFound = 0
        tasksCompleted = 0
        campWaterLevel = 0
        waterDeliveries = 0
        isCarryingWater = false
        hasWaterCompass = false
        hasWaterDetector = false
        desertSeed = UInt64.random(in: 1...UInt64.max)
        playerPositionX = 0
        playerPositionZ = 0
        timeOfDay = 0.32
        campProgress = [CampProgress.home(from: 0)]
    }

    static func timestampName(from date: Date) -> String {
        Self.nameFormatter.string(from: date)
    }

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    enum CharacterGender: String, Codable, CaseIterable {
        case man, woman

        var displayName: String {
            switch self {
            case .man:   "He / Him"
            case .woman: "She / Her"
            }
        }

        var emoji: String {
            switch self {
            case .man:   "🧔"
            case .woman: "👩"
            }
        }
    }

    func progress(forCampId id: String) -> CampProgress {
        campProgress.first { $0.id == id } ?? CampProgress(id: id)
    }

    mutating func upsertCampProgress(_ progress: CampProgress) {
        if let idx = campProgress.firstIndex(where: { $0.id == progress.id }) {
            campProgress[idx] = progress
        } else {
            campProgress.append(progress)
        }
        if progress.id == "home" {
            campWaterLevel = progress.waterLevel
        }
    }

    // MARK: - Backward-compatible decode

    enum CodingKeys: String, CodingKey {
        case id, characterGender, playerName, lastUpdated
        case waterFound, oasisFound, tasksCompleted
        case campWaterLevel, waterDeliveries, isCarryingWater
        case hasWaterCompass, hasWaterDetector
        case desertSeed, playerPositionX, playerPositionZ
        case timeOfDay, campProgress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        characterGender = try c.decodeIfPresent(CharacterGender.self, forKey: .characterGender)
        playerName = try c.decodeIfPresent(String.self, forKey: .playerName)
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated)
        waterFound = try c.decodeIfPresent(Int.self, forKey: .waterFound) ?? 0
        oasisFound = try c.decodeIfPresent(Int.self, forKey: .oasisFound) ?? 0
        tasksCompleted = try c.decodeIfPresent(Int.self, forKey: .tasksCompleted) ?? 0
        campWaterLevel = try c.decodeIfPresent(Float.self, forKey: .campWaterLevel) ?? 0
        waterDeliveries = try c.decodeIfPresent(Int.self, forKey: .waterDeliveries) ?? 0
        isCarryingWater = try c.decodeIfPresent(Bool.self, forKey: .isCarryingWater) ?? false
        hasWaterCompass = try c.decodeIfPresent(Bool.self, forKey: .hasWaterCompass) ?? false
        hasWaterDetector = try c.decodeIfPresent(Bool.self, forKey: .hasWaterDetector) ?? false
        desertSeed = try c.decodeIfPresent(UInt64.self, forKey: .desertSeed)
            ?? UInt64.random(in: 1...UInt64.max)
        playerPositionX = try c.decodeIfPresent(Float.self, forKey: .playerPositionX) ?? 0
        playerPositionZ = try c.decodeIfPresent(Float.self, forKey: .playerPositionZ) ?? 0
        timeOfDay = try c.decodeIfPresent(Float.self, forKey: .timeOfDay) ?? 0.32
        campProgress = try c.decodeIfPresent([CampProgress].self, forKey: .campProgress)
            ?? [CampProgress.home(from: campWaterLevel)]
        if !campProgress.contains(where: { $0.id == "home" }) {
            campProgress.insert(CampProgress.home(from: campWaterLevel), at: 0)
        }
    }
}
