import SceneKit
import UIKit

/// Occasional daytime sandstorms — atmosphere only (fog + compass jitter).
final class WeatherSystem {
    private(set) var isSandstormActive = false
    /// 0…1 storm intensity while active.
    private(set) var intensity: Float = 0

    private var cooldown: Float = 90
    private var stormRemaining: Float = 0
    private var nextStormIn: Float = 120
    private var rng: SeededRandom

    /// Extra fog density applied on top of day/night fog (0…1).
    var fogBoost: Float {
        guard isSandstormActive else { return 0 }
        return 0.35 + intensity * 0.45
    }

    /// Radians of random compass jitter.
    var compassJitter: Float {
        guard isSandstormActive else { return 0 }
        return (Float.random(in: -1...1)) * (0.35 + intensity * 0.55)
    }

    /// Multiplier for detector clarity (lower = weaker).
    var detectorClarity: Float {
        guard isSandstormActive else { return 1 }
        return max(0.35, 1 - intensity * 0.55)
    }

    var onStormBegan: (() -> Void)?
    var onStormEnded: (() -> Void)?

    init(seed: UInt64) {
        rng = SeededRandom(seed: seed &+ 4_044)
        nextStormIn = 80 + rng.nextFloat() * 100
    }

    func update(deltaTime: Float, timeOfDay: Float, isDaytime: Bool) {
        if isSandstormActive {
            stormRemaining -= deltaTime
            // Ease intensity up then hold
            intensity = min(1, intensity + deltaTime * 0.4)
            if stormRemaining <= 0 || !isDaytime {
                endStorm()
            }
            return
        }

        // Only brew storms in daytime
        guard isDaytime else {
            cooldown = max(cooldown, 40)
            return
        }

        nextStormIn -= deltaTime
        if nextStormIn <= 0, cooldown <= 0 {
            beginStorm()
        } else if cooldown > 0 {
            cooldown -= deltaTime
        }
    }

    private func beginStorm() {
        isSandstormActive = true
        intensity = 0.15
        stormRemaining = 28 + rng.nextFloat() * 22
        onStormBegan?()
    }

    private func endStorm() {
        guard isSandstormActive else { return }
        isSandstormActive = false
        intensity = 0
        cooldown = 70 + rng.nextFloat() * 50
        nextStormIn = 100 + rng.nextFloat() * 140
        onStormEnded?()
    }

    /// Apply fog color/density tweak for the active storm.
    func applyFog(to scene: SCNScene, baseFogStart: CGFloat, baseFogEnd: CGFloat, sandColor: UIColor) {
        guard isSandstormActive else { return }
        let t = CGFloat(intensity)
        scene.fogStartDistance = max(8, baseFogStart * (1 - t * 0.55))
        scene.fogEndDistance = max(40, baseFogEnd * (1 - t * 0.5))
        scene.fogColor = sandColor.withAlphaComponent(0.55 + t * 0.35)
    }
}
