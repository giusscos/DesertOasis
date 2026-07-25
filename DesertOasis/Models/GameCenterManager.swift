import Foundation
import GameKit
import UIKit
import Observation

@Observable
final class GameCenterManager {
    private(set) var isAuthenticated = false

    enum Leaderboard {
        static let waterDeliveries = "desert_oasis.deliveries"
        static let oasesFound     = "desert_oasis.oases"
        static let wanderers      = "desert_oasis.wanderers"
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            if let vc = viewController {
                guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                      let rootVC = scene.keyWindow?.rootViewController else { return }
                rootVC.present(vc, animated: true)
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    func reportAchievement(id: String) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = 100
        achievement.showsCompletionBanner = true
        GKAchievement.report([achievement]) { _ in }
    }

    func submitScore(_ score: Int, toLeaderboard leaderboardID: String) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(
            score, context: 0, player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { _ in }
    }

    func presentDashboard() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }
}
