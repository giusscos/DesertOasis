import SwiftUI

struct DialogueView: View {
    @Bindable var manager: DialogueManager
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var npc: NPCNode? { manager.activeNPC }

    var body: some View {
        VStack(spacing: 0) {
            // NPC name bar
            HStack {
                Circle()
                    .fill(npc?.personality.shirtColor.swiftUIColor ?? .orange)
                    .frame(width: 10, height: 10)
                Text(npc.map { nameFor($0.personality) } ?? "Stranger")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    inputFocused = false
                    manager.endConversation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.1, opacity: 0.95))

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(manager.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                        if manager.isThinking {
                            ThinkingBubble()
                        }
                    }
                    .padding(12)
                }
                .onChange(of: manager.messages.count) { _, _ in
                    if let last = manager.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: manager.isThinking) { _, thinking in
                    if thinking, let last = manager.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(Color(white: 0.06, opacity: 0.97))

            // Unavailability notice
            if !manager.modelAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Apple Intelligence not available — tap to use preset responses")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.12))
            }

            // Input bar
            HStack(spacing: 10) {
                TextField("Say something…", text: $inputText)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.white)
                    .tint(.orange)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 18))

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty ? .gray : .orange)
                }
                .disabled(inputText.isEmpty || manager.isThinking)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.10, opacity: 0.98))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !manager.isThinking else { return }
        inputText = ""

        if manager.modelAvailable {
            manager.sendMessageStreaming(text)
        } else {
            manager.messages.append(DialogueMessage(role: .player, text: text))
            let reply = manager.presetReply(to: text)
            manager.messages.append(DialogueMessage(role: .npc, text: reply))
        }
    }

    private func nameFor(_ personality: NPCPersonality) -> String {
        switch personality {
        case .wanderer: "Wanderer"
        case .merchant: "Merchant"
        case .child:    "Lost Child"
        case .elder:    "Desert Elder"
        case .lost:     "Lost Traveler"
        }
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    let message: DialogueMessage

    var isPlayer: Bool { message.role == .player }

    var body: some View {
        HStack {
            if isPlayer { Spacer(minLength: 40) }

            Text(message.text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isPlayer
                    ? Color(red: 0.7, green: 0.45, blue: 0.1)
                    : Color(white: 0.22)
                )
                .clipShape(
                    BubbleShape(isPlayer: isPlayer)
                )
                .frame(maxWidth: 240, alignment: isPlayer ? .trailing : .leading)

            if !isPlayer { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Typing indicator

struct ThinkingBubble: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .offset(y: phase == i ? -4 : 0)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.22))
        .clipShape(BubbleShape(isPlayer: false))
        .onAppear {
            withAnimation { phase = 0 }
        }
    }
}

// MARK: - Bubble shape

struct BubbleShape: Shape {
    let isPlayer: Bool
    let radius: CGFloat = 14
    let tailSize: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = radius
        if isPlayer {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r - tailSize))
            path.addLine(to: CGPoint(x: rect.maxX + tailSize, y: rect.maxY - r))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r + 2))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r + tailSize))
            path.addLine(to: CGPoint(x: rect.minX - tailSize, y: rect.minY + r))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - UIColor → SwiftUI Color

private extension UIColor {
    var swiftUIColor: Color { Color(self) }
}
