import Foundation
import Observation

struct AchievementDefinition: Identifiable {
    let id: String
    let title: String
    let body: String
}

@Observable
final class AchievementManager {
    static let catalog: [AchievementDefinition] = [
        .init(id: "first_drop", title: "First Drop", body: "Deliver water to a camp barrel for the first time."),
        .init(id: "first_oasis", title: "Glimmer Found", body: "Discover your first oasis in the dunes."),
        .init(id: "first_remote", title: "Beyond the Horizon", body: "Find another camp out in the desert."),
        .init(id: "oasis_lush", title: "Living Oasis", body: "Grow a camp oasis to a living oasis."),
        .init(id: "oasis_flourishing", title: "Flourishing", body: "Push a camp oasis into flourishing life."),
        .init(id: "five_deliveries", title: "Steady Hands", body: "Make five water deliveries."),
        .init(id: "animal_helper", title: "Trail Companion", body: "Call a camel or goat to follow with the magic stick."),
        .init(id: "five_wanderers", title: "Kindness of the Dunes", body: "Help five weary travellers."),
        .init(id: "sandstorm_survived", title: "Through the Storm", body: "Wait out a sandstorm."),
        .init(id: "merchant_trade", title: "Open the Route", body: "Buy something from the merchant."),
        .init(id: "all_diary", title: "Keeper's Memory", body: "Collect every diary page."),
        .init(id: "landmark_found", title: "Ancient Water", body: "Discover a landmark spring."),
    ]

    private(set) var unlocked: Set<String> = []
    @ObservationIgnored var onUnlock: ((String) -> Void)?

    func load(from ids: [String]) {
        unlocked = Set(ids)
    }

    var exportedIDs: [String] { Array(unlocked).sorted() }

    func isUnlocked(_ id: String) -> Bool { unlocked.contains(id) }

    /// Returns the definition if newly unlocked; nil if already had it.
    @discardableResult
    func unlock(_ id: String) -> AchievementDefinition? {
        guard !unlocked.contains(id),
              let def = Self.catalog.first(where: { $0.id == id }) else { return nil }
        unlocked.insert(id)
        onUnlock?(id)
        return def
    }

    var unlockedDefinitions: [AchievementDefinition] {
        Self.catalog.filter { unlocked.contains($0.id) }
    }
}

enum DiaryCatalog {
    static let pages: [(id: String, title: String, body: String)] = [
        (
            "dream_first_delivery",
            "Dream of the First Pour",
            "In sleep you see hands older than yours tipping water into a cracked barrel. The sand drinks, then sings."
        ),
        (
            "dream_first_help",
            "Dream of Shared Thirst",
            "A stranger drinks, then leaves a footprint that fills with green. Kindness is a seed the desert keeps."
        ),
        (
            "dream_lush",
            "Dream of Palms",
            "Fronds whisper names of rivers that once crossed this land. Your camp remembers them too."
        ),
        (
            "dream_flourishing",
            "Dream of Gathering",
            "At dusk the fire draws neighbours close. Water made a village from a ruin. Beyond the palms, another camping zone waits — walk by compass, lantern in hand."
        ),
        (
            "landmark_shrine",
            "Page of the Shrine",
            "Stone bowls still catch dew. Pilgrims once left beads here — trade of gratitude."
        ),
        (
            "landmark_mirrored",
            "Page of the Mirror",
            "The pool holds the sky so still that birds mistake it for home."
        ),
        (
            "landmark_canyon",
            "Page of the Canyon",
            "Shade and deep water: the desert's quiet hoard, carved by wind and time."
        ),
        (
            "dream_storm",
            "Dream Through Dust",
            "The storm erases tracks, then the morning redraws the world. You walk on."
        ),
    ]

    static func page(id: String) -> (title: String, body: String)? {
        pages.first { $0.id == id }.map { ($0.title, $0.body) }
    }

    static var allIDs: [String] { pages.map(\.id) }
}
