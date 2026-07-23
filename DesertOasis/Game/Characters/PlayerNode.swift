import SceneKit
import UIKit

final class PlayerNode: SCNNode {

    private var characterNode: SCNNode!
    private var isWalking = false
    private(set) var isAirborne = false

    init(gender: SaveSlot.CharacterGender) {
        super.init()
        name = "player"
        characterNode = VoxelCharacterBuilder.player(gender: gender)
        addChildNode(characterNode)
        VoxelAnim.playIdle(on: characterNode)
        setupCollider()
    }

    required init?(coder: NSCoder) { nil }

    private func setupCollider() {
        let shape = SCNPhysicsShape(geometry: SCNCapsule(capRadius: 0.3, height: 1.2), options: nil)
        physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape)
        physicsBody?.categoryBitMask  = PhysicsCategory.player
        physicsBody?.contactTestBitMask = PhysicsCategory.npc | PhysicsCategory.item
    }

    func setWalking(_ walking: Bool) {
        guard !isAirborne else {
            isWalking = walking
            return
        }
        guard walking != isWalking else { return }
        isWalking = walking
        notifyWalkAudio(walking)
        if walking {
            VoxelAnim.playWalk(on: characterNode)
        } else {
            VoxelAnim.playIdle(on: characterNode)
        }
    }

    func playJumpAnimation() {
        isAirborne = true
        notifyWalkAudio(false)
        VoxelAnim.playJump(on: characterNode)
    }

    func landFromJump() {
        guard isAirborne else { return }
        isAirborne = false
        if isWalking {
            VoxelAnim.playWalk(on: characterNode)
            notifyWalkAudio(true)
        } else {
            VoxelAnim.playIdle(on: characterNode)
            notifyWalkAudio(false)
        }
    }

    private func notifyWalkAudio(_ walking: Bool) {
        Task { @MainActor in
            AudioManager.shared.setWalking(walking)
        }
    }

    func playTalkAnimation() {
        VoxelAnim.playTalk(on: characterNode)
    }

    func stopTalkAnimation() {
        if isAirborne {
            VoxelAnim.playJump(on: characterNode)
        } else if isWalking {
            VoxelAnim.playWalk(on: characterNode)
        } else {
            VoxelAnim.playIdle(on: characterNode)
        }
    }
}

enum PhysicsCategory {
    static let player: Int = 1 << 0
    static let npc:    Int = 1 << 1
    static let item:   Int = 1 << 2
    static let terrain: Int = 1 << 3
    static let animal: Int = 1 << 4
}
