import Foundation

/// Tools the player can equip via the HUD tool button.
enum EquippableTool: String, Codable, CaseIterable, Identifiable {
    case bucket
    case magicStick
    case compass
    case detector
    case lantern

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bucket:     "Bucket"
        case .magicStick: "Magic Stick"
        case .compass:    "Compass"
        case .detector:   "Water Detector"
        case .lantern:    "Lantern"
        }
    }

    var systemImage: String {
        switch self {
        case .bucket:     "drop.fill"
        case .magicStick: "wand.and.stars"
        case .compass:    "location.north.circle.fill"
        case .detector:   "antenna.radiowaves.left.and.right"
        case .lantern:    "lantern.fill"
        }
    }

    func isUnlocked(in slot: SaveSlot) -> Bool {
        switch self {
        case .bucket, .magicStick: true
        case .compass:  slot.hasWaterCompass
        case .detector: slot.hasWaterDetector
        case .lantern:  slot.hasLantern
        }
    }

    static func unlocked(in slot: SaveSlot) -> [EquippableTool] {
        allCases.filter { $0.isUnlocked(in: slot) }
    }

    /// Next unlocked tool after `self` (wraps).
    func nextUnlocked(in slot: SaveSlot) -> EquippableTool {
        let list = Self.unlocked(in: slot)
        guard let idx = list.firstIndex(of: self), !list.isEmpty else { return .bucket }
        return list[(idx + 1) % list.count]
    }

    static func resolved(_ raw: String?, slot: SaveSlot) -> EquippableTool {
        if let raw, let tool = EquippableTool(rawValue: raw), tool.isUnlocked(in: slot) {
            return tool
        }
        return .bucket
    }
}

/// Merchant shop items bought with trade beads.
enum TradeGood: String, Codable, CaseIterable, Identifiable {
    case lantern
    case mapScrap
    case campTrinket

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lantern:     "Lantern"
        case .mapScrap:    "Map Scrap"
        case .campTrinket: "Camp Trinket"
        }
    }

    var detail: String {
        switch self {
        case .lantern:     "Light the dunes at night."
        case .mapScrap:    "Hints at a landmark spring."
        case .campTrinket: "A decoration for home camp."
        }
    }

    var cost: Int {
        switch self {
        case .lantern:     4
        case .mapScrap:    3
        case .campTrinket: 2
        }
    }

    var systemImage: String {
        switch self {
        case .lantern:     "lantern.fill"
        case .mapScrap:    "map.fill"
        case .campTrinket: "star.fill"
        }
    }
}

/// Landmark oasis varieties.
enum LandmarkKind: String, Codable, CaseIterable {
    case shrine
    case mirrored
    case canyon

    var displayName: String {
        switch self {
        case .shrine:   "Shrine Spring"
        case .mirrored: "Mirrored Pool"
        case .canyon:   "Canyon Well"
        }
    }

    var discoveryToast: String {
        switch self {
        case .shrine:   "You found the Shrine Spring — stone still remembers water."
        case .mirrored: "You found the Mirrored Pool — the sky drinks with you."
        case .canyon:   "You found the Canyon Well — cool shade between the walls."
        }
    }

    var diaryPageID: String { "landmark_\(rawValue)" }
}
