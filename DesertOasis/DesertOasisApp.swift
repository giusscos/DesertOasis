import SwiftUI

@main
struct DesertOasisApp: App {
    init() {
        PointerLockBridge.installIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
