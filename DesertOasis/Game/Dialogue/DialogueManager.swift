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

    init() {
        modelAvailable = model.availability == .available
    }

    // MARK: - Start conversation

    func startConversation(with npc: NPCNode, situation: CampSituation) {
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
    }

    func endConversation() {
        activeNPC?.stopTalkAnimation()
        activeNPC?.setConversing(false)
        activeNPC?.showIndicator()
        isVisible = false
        activeNPC = nil
        messages = []
        session = nil
    }

    // MARK: - Send player message

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let session else { return }

        messages.append(DialogueMessage(role: .player, text: text))
        isThinking = true

        Task { @MainActor in
            do {
                let response = try await session.respond(to: text)
                messages.append(DialogueMessage(role: .npc, text: response.content))
            } catch {
                let fallback = fallbackResponse(for: error, playerText: text)
                messages.append(DialogueMessage(role: .npc, text: fallback))
            }
            isThinking = false
        }
    }

    // MARK: - Streaming response (optional upgrade path)

    func sendMessageStreaming(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let session else { return }

        messages.append(DialogueMessage(role: .player, text: text))

        let streamingMsg = DialogueMessage(role: .npc, text: "")
        messages.append(streamingMsg)
        isThinking = true

        Task { @MainActor in
            do {
                let stream = session.streamResponse(to: text)
                var accumulated = ""
                for try await partial in stream {
                    accumulated = partial.content
                    messages[messages.count - 1] = DialogueMessage(role: .npc, text: accumulated)
                }
            } catch {
                messages[messages.count - 1] = DialogueMessage(
                    role: .npc,
                    text: fallbackResponse(for: error, playerText: text)
                )
            }
            isThinking = false
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
}

// MARK: - Message model

struct DialogueMessage: Identifiable {
    let id = UUID()
    let role: DialogueRole
    var text: String
}

enum DialogueRole {
    case player, npc
}
