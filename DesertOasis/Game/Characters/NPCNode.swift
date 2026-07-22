import SceneKit
import UIKit

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

    var systemInstructions: String {
        switch self {
        case .wanderer:
            return """
            You are a weary desert wanderer in a survival game. You have been walking for days \
            and desperately need water. Speak in short, thirsty sentences. Ask the player to find \
            you water or guide you to an oasis. Keep responses under 3 sentences. Be dramatic.
            """
        case .merchant:
            return """
            You are a friendly desert merchant who trades goods for water and oasis locations. \
            You have information about nearby oases to trade. Speak in a warm, business-like tone. \
            Keep responses under 3 sentences. Occasionally barter.
            """
        case .child:
            return """
            You are a small child lost in the desert looking for your family. Speak in a scared, \
            simple way. You are thirsty and scared. Ask the player to help you find your family or \
            water. Keep responses under 2 sentences.
            """
        case .elder:
            return """
            You are a wise desert elder who knows the land well. Speak in proverbs and hints about \
            where water can be found. Keep responses short, mystical, and under 3 sentences.
            """
        case .lost:
            return """
            You are a confused traveller who is completely lost and panicking. You need the \
            player's help to orient yourself. Keep responses under 3 sentences with some desperation.
            """
        }
    }

    var greeting: String {
        switch self {
        case .wanderer: "Please… do you have water? I've been walking for so long…"
        case .merchant: "Ah, a traveller! I have supplies to trade. Know where the nearest oasis is?"
        case .child:    "Hello? I'm lost… and really thirsty. Can you help me?"
        case .elder:    "The desert speaks to those who listen. You seek water, do you not?"
        case .lost:     "Oh thank goodness! I have no idea where I am. Do you have water?"
        }
    }

    var task: NPCTask {
        switch self {
        case .wanderer: NPCTask(description: "Bring water to the wanderer")
        case .merchant: NPCTask(description: "Show the merchant an oasis")
        case .child:    NPCTask(description: "Help the lost child find their family")
        case .elder:    NPCTask(description: "Listen to the elder's wisdom (find 2 oases)")
        case .lost:     NPCTask(description: "Guide the lost traveller to safety")
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

    // MARK: - Init

    init(personality: NPCPersonality, position worldPosition: SCNVector3) {
        self.personality = personality
        self.task = personality.task
        super.init()
        self.position = worldPosition
        name = "npc_\(npcID.uuidString)"

        characterNode = AssetLoader.loadCharacter(personality.fileName,
                                                   actions: ["idle", "talk", "gesture"])
        addChildNode(characterNode)
        characterNode.animationPlayer(forKey: "idle")?.play()

        setupIndicator()
        setupPhysics()
        startIdleMovement()
    }

    required init?(coder: NSCoder) { nil }

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
        physicsBody = SCNPhysicsBody(type: .static, shape: shape)
        physicsBody?.categoryBitMask = PhysicsCategory.npc
        physicsBody?.contactTestBitMask = PhysicsCategory.player
    }

    // MARK: - Idle movement

    private func startIdleMovement() {
        runAction(.repeatForever(.sequence([
            .rotateTo(x: 0, y: Double.random(in: -0.6...0.6), z: 0,
                      duration: Double.random(in: 2...4)),
            .wait(duration: Double.random(in: 1...2))
        ])))
    }

    // MARK: - Animation helpers

    func playTalkAnimation() {
        characterNode.animationPlayer(forKey: "idle")?.stop()
        characterNode.animationPlayer(forKey: "talk")?.play()
    }

    func stopTalkAnimation() {
        characterNode.animationPlayer(forKey: "talk")?.stop()
        characterNode.animationPlayer(forKey: "idle")?.play()
    }

    func playGestureAnimation() {
        characterNode.animationPlayer(forKey: "gesture")?.play()
    }

    func hideIndicator() { indicatorNode?.isHidden = true }
    func showIndicator() { indicatorNode?.isHidden = false }
}
