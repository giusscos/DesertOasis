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

    /// Camel and goat can follow and haul water vessels.
    var canHelpCarryWater: Bool {
        switch self {
        case .camel, .goat: true
        default: false
        }
    }

    /// How many buckets this animal can bring (camel = 2, goat = 1).
    var waterBucketCapacity: Int {
        switch self {
        case .camel: 2
        case .goat:  1
        default:     0
        }
    }
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

    /// Following the player as a water helper.
    private(set) var isFollowingPlayer = false
    /// Buckets currently carried (0…`kind.waterBucketCapacity`).
    private(set) var carriedBuckets = 0
    var isCarryingWater: Bool { carriedBuckets > 0 }
    private weak var followTarget: SCNNode?
    private var vesselRoot: SCNNode?
    /// Synced from the player each frame while following.
    private var followSpeed: Float = 5.5
    private var followRunning = false
    private var isRunningAnim = false

    /// Prefer left (−1) or right (+1) when skirting obstacles.
    private var avoidSide: Float = 1
    private var stuckTimer: Float = 0

    init(kind: AnimalKind, position worldPosition: SCNVector3) {
        self.kind = kind
        super.init()
        position = worldPosition
        homeX = worldPosition.x
        homeZ = worldPosition.z
        name = "animal_\(kind.rawValue)_\(animalID.uuidString)"

        meshNode = VoxelAnimalBuilder.build(kind)
        addChildNode(meshNode)
        if let body = meshNode.childNode(withName: "body", recursively: false) {
            AnimalAnim.bindRestPose(body)
        }
        AnimalAnim.playIdle(on: meshNode, kind: kind)

        setupPhysics()
        waitTimer = Float.random(in: 0.4...2.8)
        eulerAngles.y = Float.random(in: -.pi...Float.pi)
        avoidSide = Float.random(in: 0...1) < 0.5 ? -1 : 1
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

    func beginHelping(player: SCNNode, carriedBuckets buckets: Int = 0) {
        guard kind.canHelpCarryWater else { return }
        isFollowingPlayer = true
        followTarget = player
        setCarriedBuckets(buckets)
        targetX = nil
        targetZ = nil
    }

    /// Match the player's current move speed / run state while following.
    func syncFollowMovement(playerSpeed: Float, isRunning: Bool) {
        followSpeed = playerSpeed
        followRunning = isRunning
    }

    /// Returns `false` when the animal is carrying water (cannot dismiss).
    @discardableResult
    func stopHelping(force: Bool = false) -> Bool {
        if !force, isCarryingWater { return false }
        isFollowingPlayer = false
        followTarget = nil
        followSpeed = kind.walkSpeed
        followRunning = false
        setCarriedBuckets(0)
        homeX = position.x
        homeZ = position.z
        waitTimer = 1.5
        setMoving(false, running: false)
        return true
    }

    /// Fill to this animal's bucket capacity (used when collecting at an oasis).
    func fillWaterToCapacity() {
        guard kind.canHelpCarryWater else { return }
        setCarriedBuckets(kind.waterBucketCapacity)
    }

    func setCarriedBuckets(_ count: Int) {
        carriedBuckets = max(0, min(kind.waterBucketCapacity, count))
        refreshVesselVisual()
    }

    func setCarryingWater(_ carrying: Bool) {
        setCarriedBuckets(carrying ? kind.waterBucketCapacity : 0)
    }

    private func refreshVesselVisual() {
        vesselRoot?.removeFromParentNode()
        vesselRoot = nil
        guard carriedBuckets > 0 else { return }

        let root = SCNNode()
        root.name = "animal_water_vessels"
        let y: Float = kind == .camel ? 1.35 : 0.85
        let spacing: Float = 0.28
        let startX = -spacing * Float(carriedBuckets - 1) * 0.5
        for i in 0..<carriedBuckets {
            let vessel = VoxelPropBuilder.animalWaterVessel(filled: true)
            vessel.position = SCNVector3(startX + Float(i) * spacing + 0.12, y, -0.15)
            vessel.scale = SCNVector3(0.85, 0.85, 0.85)
            root.addChildNode(vessel)
        }
        addChildNode(root)
        vesselRoot = root
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

    // MARK: - Wander / follow

    func updateWander(deltaTime: Float) {
        guard !isReacting, let groundY, let isBlocked else { return }

        if isFollowingPlayer, let target = followTarget {
            updateFollow(deltaTime: deltaTime, target: target, groundY: groundY, isBlocked: isBlocked)
            position.y = groundY(position.x, position.z)
            return
        }

        if let tx = targetX, let tz = targetZ {
            let dx = tx - position.x
            let dz = tz - position.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist < 0.22 {
                targetX = nil
                targetZ = nil
                setWalking(false)
                waitTimer = Float.random(in: 1.2...4.0)
                position.y = groundY(position.x, position.z)
                return
            }

            let step = min(kind.walkSpeed * deltaTime, dist)
            if let next = steeredStep(dirX: dx / dist, dirZ: dz / dist, step: step, isBlocked: isBlocked) {
                eulerAngles.y = atan2(next.x - position.x, next.z - position.z)
                let gy = groundY(next.x, next.z)
                let lift: Float = (kind == .bird && isWalking) ? 0.08 : 0
                position = SCNVector3(next.x, gy + lift, next.z)
                setWalking(true)
            } else {
                targetX = nil
                targetZ = nil
                setWalking(false)
                waitTimer = Float.random(in: 0.5...1.4)
                position.y = groundY(position.x, position.z)
            }
            return
        }

        // Idle / waiting — stay glued to the ground.
        position.y = groundY(position.x, position.z)

        waitTimer -= deltaTime
        guard waitTimer <= 0 else { return }

        if Float.random(in: 0...1) < 0.30 {
            eulerAngles.y = Float.random(in: -.pi...Float.pi)
            waitTimer = Float.random(in: 1.0...2.8)
            return
        }

        pickNewTarget(isBlocked: isBlocked)
    }

    private func updateFollow(deltaTime: Float,
                              target: SCNNode,
                              groundY: (Float, Float) -> Float,
                              isBlocked: (Float, Float) -> Bool) {
        // If somehow inside a collider, step out before chasing.
        if isBlocked(position.x, position.z) {
            if tryUnstick(isBlocked: isBlocked, groundY: groundY) {
                setMoving(true, running: true)
            } else {
                setMoving(false, running: false)
            }
            return
        }

        let dx = target.position.x - position.x
        let dz = target.position.z - position.z
        let dist = sqrt(dx * dx + dz * dz)
        let followDist: Float = kind == .camel ? 3.2 : 2.6
        if dist < followDist {
            stuckTimer = 0
            setMoving(false, running: false)
            return
        }

        let lag = dist - followDist
        let cruise: Float = followSpeed > 0.35 ? followSpeed : max(kind.walkSpeed * 1.5, 4.0)
        let catchUp: Float = lag > 8 ? 1.45 : (lag > 4 ? 1.2 : 1.0)
        let speed = cruise * catchUp
        let step = min(speed * deltaTime, dist - followDist + 0.15)
        let dirX = dx / dist
        let dirZ = dz / dist

        if let next = steeredStep(dirX: dirX, dirZ: dirZ, step: step, isBlocked: isBlocked) {
            stuckTimer = 0
            let moveDx = next.x - position.x
            let moveDz = next.z - position.z
            position.x = next.x
            position.z = next.z
            position.y = groundY(next.x, next.z)
            if moveDx * moveDx + moveDz * moveDz > 1e-6 {
                eulerAngles.y = atan2(moveDx, moveDz)
            }
            let running = followRunning || lag > 5 || speed > 7
            setMoving(true, running: running)
        } else {
            stuckTimer += deltaTime
            if stuckTimer > 0.35 {
                avoidSide = -avoidSide
                stuckTimer = 0
                // Stronger escape nudge perpendicular to the goal.
                let perpX = -dirZ * avoidSide
                let perpZ = dirX * avoidSide
                if let next = steeredStep(dirX: perpX, dirZ: perpZ, step: step * 1.1, isBlocked: isBlocked) {
                    position.x = next.x
                    position.z = next.z
                    position.y = groundY(next.x, next.z)
                    eulerAngles.y = atan2(perpX, perpZ)
                    setMoving(true, running: true)
                    return
                }
            }
            setMoving(false, running: false)
        }
    }

    /// Try direct move, axis slides, then angled detours around obstacles.
    private func steeredStep(dirX: Float,
                             dirZ: Float,
                             step: Float,
                             isBlocked: (Float, Float) -> Bool) -> (x: Float, z: Float)? {
        let len = sqrt(dirX * dirX + dirZ * dirZ)
        guard len > 1e-5, step > 1e-5 else { return nil }
        let fx = dirX / len
        let fz = dirZ / len

        var probes: [(Float, Float)] = [
            (fx, fz),
            (fx, 0),
            (0, fz),
        ]
        // Skirt left/right of the desired heading (preferred side first).
        let angles: [Float] = [0.4, 0.75, 1.15, 1.55, 2.0]
        for angle in angles {
            for side in [avoidSide, -avoidSide] {
                let c = cos(angle * side)
                let s = sin(angle * side)
                // Rotate forward by ±angle around Y.
                let rx = fx * c - fz * s
                let rz = fx * s + fz * c
                probes.append((rx, rz))
            }
        }

        for (px, pz) in probes {
            let plen = sqrt(px * px + pz * pz)
            guard plen > 1e-5 else { continue }
            let nx = position.x + (px / plen) * step
            let nz = position.z + (pz / plen) * step
            let mx = (position.x + nx) * 0.5
            let mz = (position.z + nz) * 0.5
            if !isBlocked(nx, nz), !isBlocked(mx, mz) {
                // Remember which side worked if this wasn't a straight shot.
                if abs(px * fz - pz * fx) > 0.15 {
                    avoidSide = (px * fz - pz * fx) > 0 ? 1 : -1
                }
                return (nx, nz)
            }
        }

        // Shorter step as a last resort (squeeze past corners).
        let short = step * 0.45
        let nx = position.x + fx * short
        let nz = position.z + fz * short
        if !isBlocked(nx, nz) {
            return (nx, nz)
        }
        return nil
    }

    private func tryUnstick(isBlocked: (Float, Float) -> Bool,
                            groundY: (Float, Float) -> Float) -> Bool {
        let radii: [Float] = [0.4, 0.8, 1.3, 2.0, 3.0]
        for r in radii {
            for i in 0..<12 {
                let a = Float(i) / 12 * Float.pi * 2 + (avoidSide > 0 ? 0 : 0.2)
                let nx = position.x + cos(a) * r
                let nz = position.z + sin(a) * r
                if !isBlocked(nx, nz) {
                    position.x = nx
                    position.z = nz
                    position.y = groundY(nx, nz)
                    avoidSide = -avoidSide
                    return true
                }
            }
        }
        return false
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
        setMoving(walking, running: false)
    }

    private func setMoving(_ moving: Bool, running: Bool) {
        let run = moving && running
        guard moving != isWalking || run != isRunningAnim else { return }
        isWalking = moving
        isRunningAnim = run
        if moving {
            if run {
                AnimalAnim.playRun(on: meshNode, kind: kind)
            } else {
                AnimalAnim.playWalk(on: meshNode, kind: kind)
            }
        } else {
            AnimalAnim.playIdle(on: meshNode, kind: kind)
        }
    }
}
