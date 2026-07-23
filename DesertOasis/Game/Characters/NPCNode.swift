import SceneKit
import UIKit

// MARK: - Camp situation (drives adaptive dialogue)

struct CampSituation {
    var campWaterLevel: Float
    var waterDeliveries: Int
    var oasisFound: Int
    var isCarryingWater: Bool
    var hasCompass: Bool
    var hasDetector: Bool
    var playerName: String?

    var waterLabel: String {
        switch campWaterLevel {
        case ..<0.12: "nearly empty"
        case ..<0.35: "running low"
        case ..<0.65: "about half full"
        case ..<0.9:  "comfortably stocked"
        default:      "brimming full"
        }
    }

    var situationSummary: String {
        var lines: [String] = [
            "Camp barrel is \(waterLabel) (\(Int(campWaterLevel * 100))% full).",
            "Water deliveries so far: \(waterDeliveries).",
            "Oases the player has found: \(oasisFound).",
        ]
        if isCarryingWater {
            lines.append("The player is currently carrying a full water bucket.")
        }
        if hasCompass { lines.append("The player has a water compass.") }
        if hasDetector { lines.append("The player has a water detector.") }
        if let name = playerName, !name.isEmpty {
            lines.append("The player's name is \(name).")
        }
        return lines.joined(separator: " ")
    }
}

// MARK: - NPCTask

struct NPCTask: Identifiable {
    let id: UUID
    let description: String
    var isCompleted: Bool

    init(description: String) {
        id = UUID()
        self.description = description
        isCompleted = false
    }
}

// MARK: - NPCPersonality

enum NPCPersonality: CaseIterable {
    case wanderer, merchant, child, elder, lost

    var fileName: String {
        switch self {
        case .wanderer: "npc_wanderer"
        case .merchant: "npc_merchant"
        case .child:    "npc_child"
        case .elder:    "npc_elder"
        case .lost:     "npc_lost"
        }
    }

    func systemInstructions(situation: CampSituation) -> String {
        let base: String
        switch self {
        case .wanderer:
            base = """
            You are a weary desert wanderer in a survival game. You have been walking for days \
            and desperately need water. Speak in short, thirsty sentences. Ask the player to find \
            you water or guide you to an oasis. Keep responses under 3 sentences. Be dramatic.
            """
        case .merchant:
            base = """
            You are a friendly desert merchant living at the player's camp. You trade tips \
            about oasis locations for water delivered to the shared camp barrel. Speak in a \
            warm, business-like tone. Keep responses under 3 sentences. Occasionally barter.
            """
        case .child:
            base = """
            You are a small child living at the desert camp. You worry when the water barrel \
            is empty and cheer up when it is full. Speak in a simple way. Keep responses under 2 sentences.
            """
        case .elder:
            base = """
            You are a wise desert elder living at the camp. Speak in proverbs and hints about \
            where water can be found. Encourage the player to keep the camp barrel healthy. \
            Keep responses short, mystical, and under 3 sentences.
            """
        case .lost:
            base = """
            You are a confused traveller who is completely lost and panicking. You need the \
            player's help to orient yourself. Keep responses under 3 sentences with some desperation.
            """
        }
        return base + """


            Current camp situation (react to this naturally; do not recite it verbatim):
            \(situation.situationSummary)
            """
    }

    func greeting(for situation: CampSituation) -> String {
        let low = situation.campWaterLevel < 0.2
        let high = situation.campWaterLevel > 0.7
        let carrying = situation.isCarryingWater
        let variants: [String]
        switch self {
        case .wanderer:
            if carrying {
                variants = [
                    "Is that water? Please—share a drop with a traveller!",
                    "A full bucket… my throat sings just looking at it.",
                ]
            } else if situation.oasisFound == 0 {
                variants = [
                    "Please… do you know where the water hides?",
                    "I've walked for days. Point me toward an oasis?",
                ]
            } else {
                variants = [
                    "You found oasis tracks—any chance you still carry water?",
                    "The dunes drain me. Spare a sip if you can.",
                ]
            }
        case .merchant:
            if carrying {
                variants = [
                    "Ha! A full bucket means good business. Pour it in and I'll talk oasis tips.",
                    "Water on your back—deliver it and we'll trade news.",
                ]
            } else if low {
                variants = [
                    "Barrel's thirsty, neighbour. Fill it and I'll mark an oasis for you.",
                    "Dry barrel, dry trade. Bring water and I'll open my map.",
                ]
            } else if high {
                variants = [
                    "Camp's looking healthy! Still, another delivery buys better tips.",
                    "Well stocked today. Fancy trading for a fresher oasis rumour?",
                ]
            } else {
                variants = [
                    "Ah, a neighbour! Keep the barrel climbing and I'll keep the tips flowing.",
                    "Halfway isn't enough for a caravan. Bring more water?",
                ]
            }
        case .child:
            if carrying {
                variants = [
                    "You brought water! Pour it in the barrel, please!",
                    "Is that for us? The barrel needs it!",
                ]
            } else if low {
                variants = [
                    "I'm so thirsty… the barrel is almost dry!",
                    "Mommy said the water's almost gone… can you find an oasis?",
                ]
            } else if high {
                variants = [
                    "The barrel is full today! Want to play by the fire?",
                    "Lots of water now. The camp feels safe again!",
                ]
            } else {
                variants = [
                    "Our barrel could use more… can you find an oasis?",
                    "It's okay today, but I'm still a little worried.",
                ]
            }
        case .elder:
            if carrying {
                variants = [
                    "Water walks with you. Let it rest in our barrel.",
                    "The desert returns what you carry—pour, and the camp drinks.",
                ]
            } else if low {
                variants = [
                    "When the barrel whispers emptiness, the dunes grow louder. Fill it.",
                    "A dry camp forgets its name. Seek the oasis before dusk.",
                ]
            } else if high {
                variants = [
                    "Full barrel, quiet hearts. Still—the desert rewards those who keep giving.",
                    "The camp drinks well today. Walk farther; the next oasis waits.",
                ]
            } else if situation.oasisFound > 0 {
                variants = [
                    "You have tasted the green places. Bring their gift home again.",
                    "Each oasis found is a promise—keep our barrel honest.",
                ]
            } else {
                variants = [
                    "The desert speaks to those who listen. Fill our camp, and the oasis will find you.",
                    "Patience is a canteen. Seek water, and share it.",
                ]
            }
        case .lost:
            if situation.hasCompass || situation.hasDetector {
                variants = [
                    "You have tools I lack! Which way is camp—or water?",
                    "Please—point me somewhere wet. I'm turned around completely.",
                ]
            } else if carrying {
                variants = [
                    "Water! Oh thank goodness—can you spare a direction too?",
                    "You found water and I can't even find north… help?",
                ]
            } else {
                variants = [
                    "Oh thank goodness! I have no idea where I am. Do you have water?",
                    "Every dune looks the same. Which way to camp?",
                ]
            }
        }
        return variants.randomElement() ?? variants[0]
    }

    /// Preset replies when Apple Intelligence is unavailable.
    func fallbackReply(to playerText: String, situation: CampSituation) -> String {
        let lower = playerText.lowercased()
        let asksWater = lower.contains("water") || lower.contains("oasis") || lower.contains("barrel")
        let asksHelp = lower.contains("help") || lower.contains("where") || lower.contains("how")

        switch self {
        case .wanderer:
            if situation.isCarryingWater {
                return "That bucket… please, even a mouthful would save me."
            }
            if asksWater {
                return situation.oasisFound > 0
                    ? "You already found green places—lead me toward the nearest?"
                    : "I smell nothing but sand. Find an oasis and I'll follow."
            }
            return greeting(for: situation)
        case .merchant:
            if asksWater || asksHelp {
                return situation.campWaterLevel < 0.35
                    ? "Deliver to the barrel first. Tips flow after water does."
                    : "Keep the barrel rising and I'll mark better oasis routes."
            }
            if situation.waterDeliveries == 0 {
                return "First delivery unlocks my friendliest prices—and my best rumour."
            }
            return "Business is slow without water. What are you trading today?"
        case .child:
            if situation.isCarryingWater {
                return "Yay! Put it in the barrel—hurry!"
            }
            if situation.campWaterLevel > 0.7 {
                return "I'm not scared today. Thanks for the water!"
            }
            return asksHelp
                ? "Look for shiny water far away… then bring it home!"
                : greeting(for: situation)
        case .elder:
            if asksWater {
                return "Follow the cool breath of the dunes at dawn. Return with what you find."
            }
            if situation.campWaterLevel < 0.2 {
                return "A cracked canteen teaches haste. Our barrel waits."
            }
            return "Share what the desert gives, and it will give again."
        case .lost:
            if asksHelp || asksWater {
                return situation.hasCompass
                    ? "Your compass—does it point to water? Please, I'm spinning."
                    : "Any landmark? A tent, a barrel, a palm—anything!"
            }
            return greeting(for: situation)
        }
    }

    var task: NPCTask {
        switch self {
        case .wanderer: NPCTask(description: "Bring water to the wanderer")
        case .merchant: NPCTask(description: "Trade oasis news with the merchant")
        case .child:    NPCTask(description: "Fill the camp barrel for the child")
        case .elder:    NPCTask(description: "Deliver water to help the camp")
        case .lost:     NPCTask(description: "Guide the lost traveller toward an oasis")
        }
    }

    // Used in DialogueView for the coloured indicator dot
    var shirtColor: UIColor {
        switch self {
        case .wanderer: UIColor(red: 0.65, green: 0.55, blue: 0.40, alpha: 1)
        case .merchant: UIColor(red: 0.70, green: 0.20, blue: 0.15, alpha: 1)
        case .child:    UIColor(red: 0.40, green: 0.65, blue: 0.75, alpha: 1)
        case .elder:    UIColor(red: 0.25, green: 0.25, blue: 0.55, alpha: 1)
        case .lost:     UIColor(red: 0.80, green: 0.75, blue: 0.55, alpha: 1)
        }
    }
}

// MARK: - NPCNode

final class NPCNode: SCNNode {
    let personality: NPCPersonality
    var task: NPCTask
    let npcID = UUID()
    let interactionRadius: Float = 4.0

    private var characterNode: SCNNode!
    private var indicatorNode: SCNNode!

    // Wander
    private var homeX: Float = 0
    private var homeZ: Float = 0
    private var wanderRadius: Float = 4
    private var targetX: Float?
    private var targetZ: Float?
    private var waitTimer: Float = 0
    private var isWalking = false
    private(set) var isConversing = false
    private var groundY: ((Float, Float) -> Float)?
    private var isBlocked: ((Float, Float) -> Bool)?
    private let walkSpeed: Float = 1.15

    // MARK: - Init

    init(personality: NPCPersonality, position worldPosition: SCNVector3) {
        self.personality = personality
        self.task = personality.task
        super.init()
        self.position = worldPosition
        homeX = worldPosition.x
        homeZ = worldPosition.z
        name = "npc_\(npcID.uuidString)"

        characterNode = VoxelCharacterBuilder.npc(personality)
        addChildNode(characterNode)
        VoxelAnim.playIdle(on: characterNode)

        setupIndicator()
        setupPhysics()
        waitTimer = Float.random(in: 0.5...2.5)
    }

    required init?(coder: NSCoder) { nil }

    /// Configure roaming around a home point; `isBlocked` should reject tent interiors etc.
    func configureWander(radius: Float,
                         groundY: @escaping (Float, Float) -> Float,
                         isBlocked: @escaping (Float, Float) -> Bool) {
        wanderRadius = radius
        self.groundY = groundY
        self.isBlocked = isBlocked
        homeX = position.x
        homeZ = position.z
    }

    func setConversing(_ talking: Bool) {
        isConversing = talking
        if talking {
            targetX = nil
            targetZ = nil
            setWalking(false)
        } else {
            waitTimer = Float.random(in: 0.8...2.0)
        }
    }

    // MARK: - Indicator (! bubble above head)

    private func setupIndicator() {
        let container = SCNNode()

        let bubble = SCNNode(geometry: SCNSphere(radius: 0.25))
        let mat = SCNMaterial(); mat.diffuse.contents = UIColor(white: 0, alpha: 0.35)
        bubble.geometry?.firstMaterial = mat
        container.addChildNode(bubble)

        let textGeo = SCNText(string: "!", extrusionDepth: 0.05)
        textGeo.font = UIFont.boldSystemFont(ofSize: 0.35)
        textGeo.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1)
        let textNode = SCNNode(geometry: textGeo)
        textNode.position = SCNVector3(-0.08, -0.15, 0.15)
        container.addChildNode(textNode)

        container.position = SCNVector3(0, 1.9, 0)
        container.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.15, z: 0, duration: 0.8),
            .moveBy(x: 0, y: -0.15, z: 0, duration: 0.8)
        ])))

        indicatorNode = container
        addChildNode(container)
    }

    // MARK: - Physics

    private func setupPhysics() {
        let shape = SCNPhysicsShape(geometry: SCNCylinder(radius: 0.3, height: 1.2), options: nil)
        physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape)
        physicsBody?.categoryBitMask = PhysicsCategory.npc
        physicsBody?.contactTestBitMask = PhysicsCategory.player
    }

    // MARK: - Wander update

    func updateWander(deltaTime: Float) {
        guard !isConversing, let groundY, let isBlocked else { return }

        if let tx = targetX, let tz = targetZ {
            let dx = tx - position.x
            let dz = tz - position.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist < 0.25 {
                targetX = nil
                targetZ = nil
                setWalking(false)
                waitTimer = Float.random(in: 1.5...4.5)
                return
            }

            let step = min(walkSpeed * deltaTime, dist)
            let nx = position.x + dx / dist * step
            let nz = position.z + dz / dist * step
            if isBlocked(nx, nz) {
                targetX = nil
                targetZ = nil
                setWalking(false)
                waitTimer = Float.random(in: 0.6...1.5)
                return
            }

            let yaw = atan2(dx, dz)
            eulerAngles.y = yaw
            let gy = groundY(nx, nz)
            position = SCNVector3(nx, gy, nz)
            setWalking(true)
            return
        }

        waitTimer -= deltaTime
        guard waitTimer <= 0 else { return }

        // Occasional idle turn in place
        if Float.random(in: 0...1) < 0.28 {
            let yaw = Float.random(in: -.pi...Float.pi)
            eulerAngles.y = yaw
            waitTimer = Float.random(in: 1.2...3.0)
            return
        }

        pickNewTarget(isBlocked: isBlocked)
    }

    private func pickNewTarget(isBlocked: (Float, Float) -> Bool) {
        for _ in 0..<12 {
            let angle = Float.random(in: 0..<Float.pi * 2)
            let dist = Float.random(in: wanderRadius * 0.25...wanderRadius)
            let tx = homeX + cos(angle) * dist
            let tz = homeZ + sin(angle) * dist
            if isBlocked(tx, tz) { continue }
            // Also reject if mid-path home→target is blocked (coarse)
            let midX = (position.x + tx) * 0.5
            let midZ = (position.z + tz) * 0.5
            if isBlocked(midX, midZ) { continue }
            targetX = tx
            targetZ = tz
            return
        }
        waitTimer = Float.random(in: 1.0...2.5)
    }

    private func setWalking(_ walking: Bool) {
        guard walking != isWalking else { return }
        isWalking = walking
        if walking {
            VoxelAnim.playWalk(on: characterNode)
        } else {
            VoxelAnim.playIdle(on: characterNode)
        }
    }

    // MARK: - Animation helpers

    func playTalkAnimation() {
        setWalking(false)
        VoxelAnim.playTalk(on: characterNode)
    }

    func stopTalkAnimation() {
        VoxelAnim.playIdle(on: characterNode)
    }

    func playGestureAnimation() {
        VoxelAnim.playGesture(on: characterNode)
    }

    func hideIndicator() { indicatorNode?.isHidden = true }
    func showIndicator() { indicatorNode?.isHidden = false }
}
