import SwiftUI

struct ContentView: View {
    @State private var gameManager = GameManager()
    private let audio = AudioManager.shared

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
        .onAppear {
            audio.syncSettings(
                musicEnabled: gameManager.musicEnabled,
                soundEnabled: gameManager.soundEnabled
            )
            audio.startAmbientMusic()
        }
        .onChange(of: gameManager.musicEnabled) { _, enabled in
            audio.syncSettings(
                musicEnabled: enabled,
                soundEnabled: gameManager.soundEnabled
            )
        }
        .onChange(of: gameManager.soundEnabled) { _, enabled in
            audio.syncSettings(
                musicEnabled: gameManager.musicEnabled,
                soundEnabled: enabled
            )
        }
    }

    private var isInGame: Bool {
        if case .playing = gameManager.currentScreen { return true }
        return false
    }
}

#Preview {
    ContentView()
}
