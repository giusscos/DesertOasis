import SceneKit
import UIKit

// MARK: - AnimalKind

enum AnimalKind: String, CaseIterable {
    case camel, goat, lizard, bird

    var displayName: String {
        switch self {
        case .camel:  "Camel"
        case .goat:   "Goat"
        case .lizard: "Lizard"
        case .bird:   "Bird"
        }
    }

    var tapMessage: String {
        switch self {
        case .camel:  "The camel blinks slowly."
        case .goat:   "The goat hops with a little snort."
        case .lizard: "The lizard darts aside, then freezes."
        case .bird:   "The bird flaps and hops closer."
        }
    }

    var wanderRadius: Float {
        switch self {
        case .camel:  8
        case .goat:   6
        case .lizard: 3
        case .bird:   10
        }
    }

    var walkSpeed: Float {
        switch self {
        case .camel:  0.85
        case .goat:   1.35
        case .lizard: 1.8
        case .bird:   1.5
        }
    }

    var interactionRadius: Float {
        switch self {
        case .camel:  7
        case .goat:   6
        case .lizard: 5
        case .bird:   6
        }
    }

    var colliderRadius: Float {
        switch self {
        case .camel:  0.55
        case .goat:   0.32
        case .lizard: 0.18
        case .bird:   0.16
        }
    }

    var colliderHeight: Float {
        switch self {
        case .camel:  1.6
        case .goat:   0.85
        case .lizard: 0.25
        case .bird:   0.35
        }
    }

    /// Reserved for a later water-help loop (carry assist / trough).
    var canHelpCarryWater: Bool { false }
}

// MARK: - AnimalNode

final class AnimalNode: SCNNode {
    let kind: AnimalKind
    let animalID = UUID()
    var interactionRadius: Float { kind.interactionRadius }

    private var meshNode: SCNNode!
    private var homeX: Float = 0
    private var homeZ: Float = 0
    private var wanderRadius: Float = 6
    private var targetX: Float?
    private var targetZ: Float?
    private var waitTimer: Float = 0
    private var isWalking = false
    private var isReacting = false
    private var groundY: ((Float, Float) -> Float)?
    private var isBlocked: ((Float, Float) -> Bool)?

    init(kind: AnimalKind, position worldPosition: SCNVector3) {
        self.kind = kind
        super.init()
        position = worldPosition
        homeX = worldPosition.x
        homeZ = worldPosition.z
        name = "animal_\(kind.rawValue)_\(animalID.uuidString)"

        meshNode = VoxelAnimalBuilder.build(kind)
        addChildNode(meshNode)
        AnimalAnim.playIdle(on: meshNode, kind: kind)

        setupPhysics()
        waitTimer = Float.random(in: 0.4...2.8)
        eulerAngles.y = Float.random(in: -.pi...Float.pi)
    }

    required init?(coder: NSCoder) { nil }

    func configureWander(radius: Float? = nil,
                         groundY: @escaping (Float, Float) -> Float,
                         isBlocked: @escaping (Float, Float) -> Bool) {
        wanderRadius = radius ?? kind.wanderRadius
        self.groundY = groundY
        self.isBlocked = isBlocked
        homeX = position.x
        homeZ = position.z
    }

    // MARK: - Physics

    private func setupPhysics() {
        let shape = SCNPhysicsShape(
            geometry: SCNCylinder(radius: CGFloat(kind.colliderRadius),
                                  height: CGFloat(kind.colliderHeight)),
            options: nil
        )
        physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape)
        physicsBody?.categoryBitMask = PhysicsCategory.animal
        physicsBody?.contactTestBitMask = PhysicsCategory.player
    }

    // MARK: - Tap reaction

    func reactToTap() {
        guard !isReacting else { return }
        isReacting = true
        targetX = nil
        targetZ = nil
        setWalking(false)

        AnimalAnim.playReact(on: meshNode, kind: kind) { [weak self] in
            guard let self else { return }
            self.isReacting = false
            self.waitTimer = Float.random(in: 0.6...1.8)
            AnimalAnim.playIdle(on: self.meshNode, kind: self.kind)
        }
    }

    // MARK: - Wander

    func updateWander(deltaTime: Float) {
        guard !isReacting, let groundY, let isBlocked else { return }

        if let tx = targetX, let tz = targetZ {
            let dx = tx - position.x
            let dz = tz - position.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist < 0.22 {
                targetX = nil
                targetZ = nil
                setWalking(false)
                waitTimer = Float.random(in: 1.2...4.0)
                return
            }

            let step = min(kind.walkSpeed * deltaTime, dist)
            let nx = position.x + dx / dist * step
            let nz = position.z + dz / dist * step
            if isBlocked(nx, nz) {
                targetX = nil
                targetZ = nil
                setWalking(false)
                waitTimer = Float.random(in: 0.5...1.4)
                return
            }

            eulerAngles.y = atan2(dx, dz)
            let gy = groundY(nx, nz)
            // Birds hop slightly off the sand while moving.
            let lift: Float = (kind == .bird && isWalking) ? 0.08 : 0
            position = SCNVector3(nx, gy + lift, nz)
            setWalking(true)
            return
        }

        waitTimer -= deltaTime
        guard waitTimer <= 0 else { return }

        if Float.random(in: 0...1) < 0.30 {
            eulerAngles.y = Float.random(in: -.pi...Float.pi)
            waitTimer = Float.random(in: 1.0...2.8)
            return
        }

        pickNewTarget(isBlocked: isBlocked)
    }

    private func pickNewTarget(isBlocked: (Float, Float) -> Bool) {
        for _ in 0..<12 {
            let angle = Float.random(in: 0..<Float.pi * 2)
            let dist = Float.random(in: wanderRadius * 0.2...wanderRadius)
            let tx = homeX + cos(angle) * dist
            let tz = homeZ + sin(angle) * dist
            if isBlocked(tx, tz) { continue }
            let midX = (position.x + tx) * 0.5
            let midZ = (position.z + tz) * 0.5
            if isBlocked(midX, midZ) { continue }
            targetX = tx
            targetZ = tz
            return
        }
        waitTimer = Float.random(in: 0.9...2.2)
    }

    private func setWalking(_ walking: Bool) {
        guard walking != isWalking else { return }
        isWalking = walking
        if walking {
            AnimalAnim.playWalk(on: meshNode, kind: kind)
        } else {
            AnimalAnim.playIdle(on: meshNode, kind: kind)
        }
    }
}
