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

    init() {
        modelAvailable = model.availability == .available
    }

    // MARK: - Start conversation

    func startConversation(with npc: NPCNode) {
        activeNPC = npc
        messages = []
        isVisible = true
        isThinking = false

        session = LanguageModelSession(instructions: npc.personality.systemInstructions)

        let greeting = DialogueMessage(role: .npc, text: npc.personality.greeting)
        messages.append(greeting)
        npc.hideIndicator()
        npc.playTalkAnimation()
    }

    func endConversation() {
        activeNPC?.stopTalkAnimation()
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
                let fallback = fallbackResponse(for: error)
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
                messages[messages.count - 1] = DialogueMessage(role: .npc, text: fallbackResponse(for: error))
            }
            isThinking = false
        }
    }

    // MARK: - Fallback

    private func fallbackResponse(for error: Error) -> String {
        if case LanguageModelSession.GenerationError.unsupportedLanguageOrLocale = error {
            return "I can only speak in supported languages..."
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
