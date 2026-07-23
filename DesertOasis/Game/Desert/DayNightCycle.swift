import SceneKit
import UIKit

/// Drives sun/ambient/sky from a 0…1 day clock (0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk).
final class DayNightCycle {

    /// Full day length in real seconds (~10 minutes).
    var dayLengthSeconds: Float = 600
    /// Current time of day in [0, 1).
    private(set) var timeOfDay: Float = 0.32
    /// Latest sky background color from the palette (for celestial tinting).
    private(set) var currentSkyColor: UIColor = UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)

    private weak var sunNode: SCNNode?
    private weak var ambientNode: SCNNode?
    private weak var skyNode: SCNNode?
    private weak var scene: SCNScene?

    private var sunLight: SCNLight?
    private var ambientLight: SCNLight?
    private var skyMaterial: SCNMaterial?

    func attach(scene: SCNScene, sun: SCNNode, ambient: SCNNode, sky: SCNNode) {
        self.scene = scene
        sunNode = sun
        ambientNode = ambient
        skyNode = sky
        sunLight = sun.light
        ambientLight = ambient.light
        skyMaterial = sky.geometry?.firstMaterial
        apply(immediate: true)
    }

    func setTimeOfDay(_ t: Float) {
        timeOfDay = Self.wrap(t)
        apply(immediate: true)
    }

    func update(deltaTime: Float) {
        guard dayLengthSeconds > 1 else { return }
        timeOfDay = Self.wrap(timeOfDay + deltaTime / dayLengthSeconds)
        apply(immediate: false)
    }

    /// Advances clock by `amount` (fraction of a day), used during sleep timelapse.
    func advance(by amount: Float) {
        timeOfDay = Self.wrap(timeOfDay + amount)
        apply(immediate: true)
    }

    /// Next morning just after sunrise (~0.28).
    var nextMorning: Float { 0.30 }

    /// Seconds of game-day needed to reach next morning (wrapping past midnight).
    func fractionUntilMorning() -> Float {
        let target = nextMorning
        if timeOfDay <= target {
            return target - timeOfDay
        }
        return (1 - timeOfDay) + target
    }

    var isNight: Bool {
        timeOfDay < 0.22 || timeOfDay > 0.78
    }

    var isDuskOrNight: Bool {
        timeOfDay > 0.68 || timeOfDay < 0.22
    }

    /// 0 at deep night, 1 at full day — useful for lantern/campfire boost.
    var daylightFactor: Float {
        let t = timeOfDay
        if t > 0.28 && t < 0.72 { return 1 }
        if t >= 0.22 && t <= 0.28 { return (t - 0.22) / 0.06 }
        if t >= 0.72 && t <= 0.78 { return 1 - (t - 0.72) / 0.06 }
        return 0.05
    }

    // MARK: - Apply

    private func apply(immediate: Bool) {
        let sample = Self.sample(at: timeOfDay)

        if let sun = sunLight {
            sun.color = sample.sunColor
            sun.intensity = sample.sunIntensity
            sun.castsShadow = sample.sunIntensity > 200
        }
        if let sunNode {
            // Arc from east→west: pitch from near-horizon through zenith.
            let angle = (timeOfDay - 0.25) * Float.pi * 2
            sunNode.eulerAngles = SCNVector3(-Float.pi * 0.15 - sin(angle) * 0.55, Float.pi * 0.25 + cos(angle) * 0.35, 0)
        }
        if let ambient = ambientLight {
            ambient.color = sample.ambientColor
            ambient.intensity = sample.ambientIntensity
        }
        if let skyMaterial {
            skyMaterial.diffuse.contents = sample.skyColor
        }
        currentSkyColor = sample.skyColor
        scene?.background.contents = sample.skyColor
        scene?.fogColor = sample.fogColor
    }

    // MARK: - Palette

    private struct Sample {
        var sunColor: UIColor
        var sunIntensity: CGFloat
        var ambientColor: UIColor
        var ambientIntensity: CGFloat
        var skyColor: UIColor
        /// Warm sand haze — biased toward sky so the dome still reads as atmosphere when fogged.
        var fogColor: UIColor
    }

    private static func sample(at t: Float) -> Sample {
        // Keyframes: midnight, predawn, sunrise, morning, noon, afternoon, sunset, evening, midnight
        let keys: [(Float, Sample)] = [
            (0.00, Sample(
                sunColor: UIColor(red: 0.35, green: 0.42, blue: 0.70, alpha: 1),
                sunIntensity: 80,
                ambientColor: UIColor(red: 0.18, green: 0.22, blue: 0.38, alpha: 1),
                ambientIntensity: 90,
                skyColor: UIColor(red: 0.06, green: 0.08, blue: 0.18, alpha: 1),
                fogColor: UIColor(red: 0.12, green: 0.11, blue: 0.16, alpha: 1)
            )),
            (0.20, Sample(
                sunColor: UIColor(red: 0.55, green: 0.45, blue: 0.55, alpha: 1),
                sunIntensity: 180,
                ambientColor: UIColor(red: 0.30, green: 0.28, blue: 0.40, alpha: 1),
                ambientIntensity: 140,
                skyColor: UIColor(red: 0.18, green: 0.16, blue: 0.28, alpha: 1),
                fogColor: UIColor(red: 0.28, green: 0.22, blue: 0.26, alpha: 1)
            )),
            (0.26, Sample(
                sunColor: UIColor(red: 1.0, green: 0.55, blue: 0.30, alpha: 1),
                sunIntensity: 700,
                ambientColor: UIColor(red: 0.75, green: 0.45, blue: 0.35, alpha: 1),
                ambientIntensity: 280,
                skyColor: UIColor(red: 0.95, green: 0.55, blue: 0.35, alpha: 1),
                fogColor: UIColor(red: 0.92, green: 0.62, blue: 0.42, alpha: 1)
            )),
            (0.35, Sample(
                sunColor: UIColor(red: 1.0, green: 0.92, blue: 0.72, alpha: 1),
                sunIntensity: 1100,
                ambientColor: UIColor(red: 0.65, green: 0.72, blue: 0.85, alpha: 1),
                ambientIntensity: 380,
                skyColor: UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1),
                fogColor: UIColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 1)
            )),
            (0.50, Sample(
                sunColor: UIColor(red: 1.0, green: 0.95, blue: 0.82, alpha: 1),
                sunIntensity: 1300,
                ambientColor: UIColor(red: 0.70, green: 0.78, blue: 0.90, alpha: 1),
                ambientIntensity: 450,
                skyColor: UIColor(red: 0.48, green: 0.74, blue: 0.96, alpha: 1),
                fogColor: UIColor(red: 0.82, green: 0.74, blue: 0.58, alpha: 1)
            )),
            (0.68, Sample(
                sunColor: UIColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1),
                sunIntensity: 900,
                ambientColor: UIColor(red: 0.80, green: 0.55, blue: 0.40, alpha: 1),
                ambientIntensity: 320,
                skyColor: UIColor(red: 0.85, green: 0.52, blue: 0.32, alpha: 1),
                fogColor: UIColor(red: 0.88, green: 0.58, blue: 0.38, alpha: 1)
            )),
            (0.76, Sample(
                sunColor: UIColor(red: 1.0, green: 0.40, blue: 0.22, alpha: 1),
                sunIntensity: 450,
                ambientColor: UIColor(red: 0.55, green: 0.28, blue: 0.28, alpha: 1),
                ambientIntensity: 200,
                skyColor: UIColor(red: 0.45, green: 0.18, blue: 0.22, alpha: 1),
                fogColor: UIColor(red: 0.42, green: 0.22, blue: 0.20, alpha: 1)
            )),
            (0.85, Sample(
                sunColor: UIColor(red: 0.40, green: 0.42, blue: 0.65, alpha: 1),
                sunIntensity: 120,
                ambientColor: UIColor(red: 0.22, green: 0.24, blue: 0.40, alpha: 1),
                ambientIntensity: 110,
                skyColor: UIColor(red: 0.10, green: 0.10, blue: 0.22, alpha: 1),
                fogColor: UIColor(red: 0.14, green: 0.12, blue: 0.18, alpha: 1)
            )),
            (1.00, Sample(
                sunColor: UIColor(red: 0.35, green: 0.42, blue: 0.70, alpha: 1),
                sunIntensity: 80,
                ambientColor: UIColor(red: 0.18, green: 0.22, blue: 0.38, alpha: 1),
                ambientIntensity: 90,
                skyColor: UIColor(red: 0.06, green: 0.08, blue: 0.18, alpha: 1),
                fogColor: UIColor(red: 0.12, green: 0.11, blue: 0.16, alpha: 1)
            )),
        ]

        var i = 0
        while i + 1 < keys.count && keys[i + 1].0 < t { i += 1 }
        let a = keys[i]
        let b = keys[min(i + 1, keys.count - 1)]
        let span = max(0.0001, b.0 - a.0)
        let u = CGFloat((t - a.0) / span)
        return Sample(
            sunColor: lerpColor(a.1.sunColor, b.1.sunColor, u),
            sunIntensity: a.1.sunIntensity + (b.1.sunIntensity - a.1.sunIntensity) * u,
            ambientColor: lerpColor(a.1.ambientColor, b.1.ambientColor, u),
            ambientIntensity: a.1.ambientIntensity + (b.1.ambientIntensity - a.1.ambientIntensity) * u,
            skyColor: lerpColor(a.1.skyColor, b.1.skyColor, u),
            fogColor: lerpColor(a.1.fogColor, b.1.fogColor, u)
        )
    }

    private static func lerpColor(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
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

    private static func wrap(_ t: Float) -> Float {
        var v = t.truncatingRemainder(dividingBy: 1)
        if v < 0 { v += 1 }
        return v
    }
}
