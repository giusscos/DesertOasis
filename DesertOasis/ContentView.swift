import SwiftUI

struct ContentView: View {
    @State private var gameManager = GameManager()

    var body: some View {
        Group {
            switch gameManager.currentScreen {
            case .playing(let slotIndex):
                GameView(gameManager: gameManager, slotIndex: slotIndex)
            default:
                LobbyContainerView(gameManager: gameManager)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: isInGame)
    }

    private var isInGame: Bool {
        if case .playing = gameManager.currentScreen { return true }
        return false
    }
}

#Preview {
    ContentView()
}
