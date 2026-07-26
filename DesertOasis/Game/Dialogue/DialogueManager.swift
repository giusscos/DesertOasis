import Foundation
import FoundationModels
import Observation

@Observable
final class DialogueManager {

    // Currently talking NPC
    var activeNPC: NPCNode? = nil
    var isVisible: Bool = false
    var messages: [DialogueMessage] = []
    var isThinking: Bool = false
    var modelAvailable: Bool = false

    /// Called when a conversation begins — used by GameView to trigger mission offers.
    var onConversationStarted: ((NPCNode) -> Void)?

    private var session: LanguageModelSession?
    private let model = SystemLanguageModel.default
    private var situation = CampSituation(
        campWaterLevel: 0,
        waterDeliveries: 0,
        oasisFound: 0,
        isCarryingWater: false,
        hasCompass: false,
        hasDetector: false,
        playerName: nil
    )
    @ObservationIgnored private var responseTask: Task<Void, Never>?

    init() {
        modelAvailable = model.availability == .available
    }

    // MARK: - Start conversation

    func startConversation(with npc: NPCNode, situation: CampSituation) {
        cancelInFlightResponse()
        activeNPC = npc
        self.situation = situation
        messages = []
        isVisible = true
        isThinking = false

        npc.setConversing(true)
        session = LanguageModelSession(instructions: npc.personality.systemInstructions(situation: situation))

        let greeting = DialogueMessage(role: .npc, text: npc.personality.greeting(for: situation))
        messages.append(greeting)
        npc.hideIndicator()
        npc.playTalkAnimation()
        onConversationStarted?(npc)
    }

    func endConversation() {
        cancelInFlightResponse()
        activeNPC?.stopTalkAnimation()
        activeNPC?.setConversing(false)
        activeNPC?.showIndicator()
        isVisible = false
        activeNPC = nil
        messages = []
        session = nil
        isThinking = false
    }

    // MARK: - Send player message

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let session else { return }

        messages.append(DialogueMessage(role: .player, text: text))
        isThinking = true

        cancelInFlightResponse()
        responseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await session.respond(to: text)
                guard !Task.isCancelled, self.isVisible else { return }
                self.messages.append(DialogueMessage(role: .npc, text: response.content))
            } catch {
                guard !Task.isCancelled, self.isVisible else { return }
                let fallback = self.fallbackResponse(for: error, playerText: text)
                self.messages.append(DialogueMessage(role: .npc, text: fallback))
            }
            if !Task.isCancelled {
                self.isThinking = false
            }
        }
    }

    // MARK: - Streaming response (optional upgrade path)

    func sendMessageStreaming(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let session else { return }

        messages.append(DialogueMessage(role: .player, text: text))

        let streamingMsg = DialogueMessage(role: .npc, text: "")
        let streamingId = streamingMsg.id
        messages.append(streamingMsg)
        isThinking = true

        cancelInFlightResponse()
        responseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = session.streamResponse(to: text)
                var accumulated = ""
                for try await partial in stream {
                    guard !Task.isCancelled, self.isVisible else { return }
                    accumulated = partial.content
                    guard let idx = self.messages.firstIndex(where: { $0.id == streamingId }) else { return }
                    self.messages[idx].text = accumulated
                }
            } catch {
                guard !Task.isCancelled, self.isVisible else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == streamingId }) {
                    self.messages[idx].text = self.fallbackResponse(for: error, playerText: text)
                } else {
                    self.messages.append(DialogueMessage(
                        role: .npc,
                        text: self.fallbackResponse(for: error, playerText: text)
                    ))
                }
            }
            if !Task.isCancelled {
                self.isThinking = false
            }
        }
    }

    /// Preset reply when Apple Intelligence is unavailable.
    func presetReply(to text: String) -> String {
        guard let npc = activeNPC else { return "..." }
        return npc.personality.fallbackReply(to: text, situation: situation)
    }

    // MARK: - Fallback

    private func fallbackResponse(for error: Error, playerText: String) -> String {
        if case LanguageModelSession.GenerationError.unsupportedLanguageOrLocale = error {
            return "I can only speak in supported languages..."
        }
        if let npc = activeNPC {
            return npc.personality.fallbackReply(to: playerText, situation: situation)
        }
        return "The desert wind swallows my words... try again."
    }

    private func cancelInFlightResponse() {
        responseTask?.cancel()
        responseTask = nil
    }
}

// MARK: - Message model

struct DialogueMessage: Identifiable {
    let id: UUID
    let role: DialogueRole
    var text: String

    init(role: DialogueRole, text: String, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum DialogueRole {
    case player, npc
}
