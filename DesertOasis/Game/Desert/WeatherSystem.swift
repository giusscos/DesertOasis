import SceneKit
import UIKit

/// Occasional daytime sandstorms — fog boost, dust, compass jitter.
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

    /// Storm-tightened fog range for the Metal atmosphere pass (SceneKit fog stays off).
    func metalFogRange(baseFogStart: CGFloat, baseFogEnd: CGFloat) -> (start: CGFloat, end: CGFloat) {
        guard isSandstormActive else { return (baseFogStart, baseFogEnd) }
        let t = CGFloat(intensity)
        return (
            max(8, baseFogStart * (1 - t * 0.55)),
            max(40, baseFogEnd * (1 - t * 0.5))
        )
    }

    /// Sand tint blended into Metal fog while storming.
    func metalFogColor(base: UIColor) -> UIColor {
        guard isSandstormActive else { return base }
        let sand = UIColor(red: 0.82, green: 0.68, blue: 0.42, alpha: 1)
        let t = CGFloat(0.35 + intensity * 0.45)
        return Self.lerp(base, sand, t)
    }

    private static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }
}
