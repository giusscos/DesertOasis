import SceneKit
import UIKit

final class PlayerNode: SCNNode {

    private var characterNode: SCNNode!
    private var isWalking = false

    // MARK: - Init

    init(gender: SaveSlot.CharacterGender) {
        super.init()
        name = "player"
        let modelName = gender == .man ? "player_man" : "player_woman"
        characterNode = AssetLoader.loadCharacter(modelName, actions: ["idle", "walk", "talk", "wave"])
        addChildNode(characterNode)
        characterNode.animationPlayer(forKey: "idle")?.play()
        setupCollider()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Physics

    private func setupCollider() {
        let shape = SCNPhysicsShape(geometry: SCNCapsule(capRadius: 0.3, height: 1.2), options: nil)
        physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape)
        physicsBody?.categoryBitMask  = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.npc | PhysicsCategory.item
    }

    // MARK: - Animation control

    func setWalking(_ walking: Bool) {
        guard walking != isWalking else { return }
        isWalking = walking
        if walking {
            characterNode.animationPlayer(forKey: "idle")?.stop()
            characterNode.animationPlayer(forKey: "walk")?.play()
        } else {
            characterNode.animationPlayer(forKey: "walk")?.stop()
            characterNode.animationPlayer(forKey: "idle")?.play()
        }
    }

    func playTalkAnimation() {
        characterNode.animationPlayer(forKey: "walk")?.stop()
        characterNode.animationPlayer(forKey: "idle")?.stop()
        characterNode.animationPlayer(forKey: "talk")?.play()
    }

    func stopTalkAnimation() {
        characterNode.animationPlayer(forKey: "talk")?.stop()
        characterNode.animationPlayer(forKey: isWalking ? "walk" : "idle")?.play()
    }
}

// MARK: - Physics categories

enum PhysicsCategory {
    static let player: Int = 1 << 0
    static let npc:    Int = 1 << 1
    static let item:   Int = 1 << 2
    static let terrain: Int = 1 << 3
}
