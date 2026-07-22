import Foundation

struct SaveSlot: Codable, Identifiable {
    let id: Int
    var characterGender: CharacterGender?
    var playerName: String?
    var lastUpdated: Date?
    var waterFound: Int
    var oasisFound: Int
    var tasksCompleted: Int
    var desertSeed: UInt64
    var playerPositionX: Float
    var playerPositionZ: Float

    var isEmpty: Bool { characterGender == nil }

    init(id: Int) {
        self.id = id
        characterGender = nil
        playerName = nil
        lastUpdated = nil
        waterFound = 0
        oasisFound = 0
        tasksCompleted = 0
        desertSeed = UInt64.random(in: 1...UInt64.max)
        playerPositionX = 0
        playerPositionZ = 0
    }

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
}
