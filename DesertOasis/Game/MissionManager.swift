import Foundation
import Observation

// MARK: - Mission data types (shared with SaveSlot)

enum MissionStatus: String, Codable {
    case active, completed, failed
}

struct MissionRecord: Codable, Identifiable, Equatable {
    var id: String
    var status: MissionStatus
    var isNew: Bool
}

// MARK: - Mission definition (static catalog entry)

struct MissionDefinition {
    let id: String
    let title: String
    let body: String
    let isNPCOffered: Bool
}

// MARK: - Manager

@Observable
final class MissionManager {

    static let catalog: [MissionDefinition] = [
        .init(
            id: "keeper_first_drop",
            title: "Keeper of the Last Drop",
            body: "The camp barrel sits empty. Head into the desert, find a water source, and bring back your first bucket.",
            isNPCOffered: false
        ),
        .init(
            id: "glimmer_in_dust",
            title: "A Glimmer in the Dust",
            body: "Tales speak of ancient oases hidden beneath the dunes. Seek one out — and discover the buried life of this desert.",
            isNPCOffered: false
        ),
        .init(
            id: "oasis_remembers",
            title: "The Oasis Remembers",
            body: "Your camp's oasis is awakening. Keep bringing water until it becomes a living oasis again.",
            isNPCOffered: false
        ),
        .init(
            id: "beyond_horizon",
            title: "Beyond the Horizon",
            body: "You are not alone out here. Other survivors are scattered across the dunes. Find them and help their camp grow.",
            isNPCOffered: false
        ),
        .init(
            id: "wanderers_plea",
            title: "A Wanderer's Plea",
            body: "A weary traveller is fading in the heat. Give them the water from your bucket before it's too late.",
            isNPCOffered: true
        ),
        .init(
            id: "ancient_trial",
            title: "The Elder's Trial",
            body: "The elder asks you to restore the oasis to a camp pond — a tribute to the world that was, when water ran freely.",
            isNPCOffered: true
        ),
        .init(
            id: "merchants_route",
            title: "The Merchant's Route",
            body: "The merchant needs steady trade. Make 5 total water deliveries to any camp to keep the supply chain alive.",
            isNPCOffered: true
        ),
        .init(
            id: "lost_and_found",
            title: "Lost and Found",
            body: "A lost traveller is desperate and disoriented. Give them your water — it is the only compass they need right now.",
            isNPCOffered: true
        ),
    ]

    private(set) var records: [MissionRecord] = []

    var hasNewMissions: Bool { records.contains { $0.isNew } }

    // MARK: - Load / export

    func load(from saved: [MissionRecord]) {
        records = saved
    }

    var exportedRecords: [MissionRecord] { records }

    // MARK: - Queries

    func definition(for id: String) -> MissionDefinition? {
        Self.catalog.first { $0.id == id }
    }

    func isUnlocked(_ id: String) -> Bool {
        records.contains { $0.id == id }
    }

    func isActive(_ id: String) -> Bool {
        records.first { $0.id == id }?.status == .active
    }

    func isCompleted(_ id: String) -> Bool {
        records.first { $0.id == id }?.status == .completed
    }

    var active: [MissionDefinition] {
        records
            .filter { $0.status == .active }
            .compactMap { r in Self.catalog.first { $0.id == r.id } }
    }

    var completed: [MissionDefinition] {
        records
            .filter { $0.status == .completed }
            .compactMap { r in Self.catalog.first { $0.id == r.id } }
    }

    var failed: [MissionDefinition] {
        records
            .filter { $0.status == .failed }
            .compactMap { r in Self.catalog.first { $0.id == r.id } }
    }

    // MARK: - Mutations

    /// Adds a new active mission. No-op if already unlocked.
    func unlock(_ id: String) {
        guard !isUnlocked(id) else { return }
        records.append(MissionRecord(id: id, status: .active, isNew: true))
    }

    /// Marks an active mission as completed. No-op if not currently active.
    func complete(_ id: String) {
        guard let i = records.firstIndex(where: { $0.id == id && $0.status == .active }) else { return }
        records[i].status = .completed
        records[i].isNew = true
    }

    /// Marks an active mission as failed.
    func fail(_ id: String) {
        guard let i = records.firstIndex(where: { $0.id == id && $0.status == .active }) else { return }
        records[i].status = .failed
        records[i].isNew = true
    }

    /// Clears isNew on all records — call when the player opens the missions list.
    func markAllSeen() {
        for i in records.indices where records[i].isNew {
            records[i].isNew = false
        }
    }
}
