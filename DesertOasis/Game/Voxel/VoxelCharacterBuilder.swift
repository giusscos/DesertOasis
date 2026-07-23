import SceneKit
import UIKit

/// MagicaVoxel-style characters: each limb is a sculpture of unit cubes (not one stretched box).
enum VoxelCharacterBuilder {

    struct Palette {
        var skin: UIColor
        var shirt: UIColor
        var pants: UIColor
        var hair: UIColor
        var hat: UIColor?
        var scale: Float

        static func player(man: Bool) -> Palette {
            if man {
                return Palette(
                    skin: VoxelType.skin.color,
                    shirt: UIColor(red: 0.72, green: 0.62, blue: 0.42, alpha: 1),
                    pants: UIColor(red: 0.35, green: 0.40, blue: 0.28, alpha: 1),
                    hair: UIColor(red: 0.22, green: 0.16, blue: 0.10, alpha: 1),
                    hat: UIColor(red: 0.55, green: 0.42, blue: 0.28, alpha: 1),
                    scale: 1.0
                )
            }
            return Palette(
                skin: VoxelType.skin.color,
                shirt: UIColor(red: 0.72, green: 0.42, blue: 0.38, alpha: 1),
                pants: UIColor(red: 0.45, green: 0.28, blue: 0.55, alpha: 1),
                hair: UIColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1),
                hat: UIColor(red: 0.70, green: 0.60, blue: 0.35, alpha: 1),
                scale: 0.95
            )
        }

        static func npc(_ p: NPCPersonality) -> Palette {
            switch p {
            case .wanderer:
                return Palette(skin: VoxelType.skin.color,
                               shirt: UIColor(red: 0.65, green: 0.55, blue: 0.40, alpha: 1),
                               pants: UIColor(red: 0.40, green: 0.35, blue: 0.28, alpha: 1),
                               hair: UIColor(red: 0.45, green: 0.40, blue: 0.30, alpha: 1),
                               hat: nil, scale: 1.0)
            case .merchant:
                return Palette(skin: VoxelType.skin.color,
                               shirt: UIColor(red: 0.70, green: 0.20, blue: 0.15, alpha: 1),
                               pants: UIColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1),
                               hair: UIColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1),
                               hat: UIColor(red: 0.75, green: 0.15, blue: 0.12, alpha: 1),
                               scale: 1.0)
            case .child:
                return Palette(skin: VoxelType.skin.color,
                               shirt: UIColor(red: 0.40, green: 0.65, blue: 0.75, alpha: 1),
                               pants: UIColor(red: 0.30, green: 0.35, blue: 0.50, alpha: 1),
                               hair: UIColor(red: 0.40, green: 0.28, blue: 0.15, alpha: 1),
                               hat: nil, scale: 0.72)
            case .elder:
                return Palette(skin: UIColor(red: 0.88, green: 0.78, blue: 0.68, alpha: 1),
                               shirt: UIColor(red: 0.85, green: 0.85, blue: 0.80, alpha: 1),
                               pants: UIColor(red: 0.75, green: 0.75, blue: 0.72, alpha: 1),
                               hair: UIColor(white: 0.85, alpha: 1),
                               hat: nil, scale: 0.98)
            case .lost:
                return Palette(skin: VoxelType.skin.color,
                               shirt: UIColor(red: 0.80, green: 0.75, blue: 0.55, alpha: 1),
                               pants: UIColor(red: 0.35, green: 0.38, blue: 0.42, alpha: 1),
                               hair: UIColor(red: 0.30, green: 0.22, blue: 0.15, alpha: 1),
                               hat: nil, scale: 1.0)
            }
        }
    }

    private static var uf: Float { VoxelMetrics.unit }

    private static func sculptNode(_ sculpture: VoxelSculpture,
                                   name: String,
                                   colors: [VoxelType: UIColor] = [:]) -> SCNNode {
        sculpture.makeNode(name: name) { type in colors[type] ?? type.color }
    }

    /// ~1.75 m tall adult on a 28-unit grid. Pivot at feet; +Z forward.
    static func build(palette: Palette) -> SCNNode {
        let root = SCNNode()
        root.name = "voxel_character"
        let u = uf

        let boot = UIColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1)
        let colors: [VoxelType: UIColor] = [
            .skin: palette.skin,
            .cloth: palette.shirt,
            .canvas: palette.pants,
            .hair: palette.hair,
            .darkWood: boot,
            .brass: palette.hat ?? VoxelType.brass.color,
        ]

        // --- Legs (pivot at hip) ---
        // Pants run all the way to the hip so they meet the waist; a short top flare
        // closes the crotch gap under the torso.
        let legL = SCNNode()
        legL.name = "leg_L"
        legL.position = SCNVector3(-2.2 * u, 12 * u, 0)
        let legLS = VoxelSculpture(sizeX: 5, sizeY: 13, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, -12, -2.5) * u)
        legLS.fillCylinder(c0: 2.5, c1: 2.5, a0: 2, a1: 12, radius: 1.8, type: .canvas)
        legLS.fillCylinder(c0: 2.5, c1: 2.5, a0: 10, a1: 12, radius: 2.2, type: .canvas)
        legLS.fillEllipsoid(cx: 2.5, cy: 1.2, cz: 2.5, rx: 2.1, ry: 1.2, rz: 2.2, type: .darkWood)
        legL.addChildNode(sculptNode(legLS, name: "leg_L_mesh", colors: colors))
        root.addChildNode(legL)

        let legR = SCNNode()
        legR.name = "leg_R"
        legR.position = SCNVector3(2.2 * u, 12 * u, 0)
        let legRS = VoxelSculpture(sizeX: 5, sizeY: 13, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, -12, -2.5) * u)
        legRS.fillCylinder(c0: 2.5, c1: 2.5, a0: 2, a1: 12, radius: 1.8, type: .canvas)
        legRS.fillCylinder(c0: 2.5, c1: 2.5, a0: 10, a1: 12, radius: 2.2, type: .canvas)
        legRS.fillEllipsoid(cx: 2.5, cy: 1.2, cz: 2.5, rx: 2.1, ry: 1.2, rz: 2.2, type: .darkWood)
        legR.addChildNode(sculptNode(legRS, name: "leg_R_mesh", colors: colors))
        root.addChildNode(legR)

        // --- Torso ---
        // Origin starts 2 units below the hip so hips/waist overlap pant tops
        // (the old ellipsoid tapered away and left a visible midsection hole).
        let torsoS = VoxelSculpture(sizeX: 11, sizeY: 14, sizeZ: 7,
                                    origin: SIMD3<Float>(-5.5, -2, -3.5) * u)
        // Hips / pelvis bridge (pants) + tucked shirt over them
        torsoS.fillEllipsoid(cx: 5.5, cy: 1.8, cz: 3.5, rx: 5.0, ry: 2.2, rz: 2.7, type: .canvas)
        torsoS.fillCylinder(c0: 5.5, c1: 3.5, a0: 2, a1: 5, radius: 4.5, type: .cloth)
        // Belt
        torsoS.fillCylinder(c0: 5.5, c1: 3.5, a0: 3, a1: 4.5, radius: 4.8, type: .darkWood)
        // Chest / upper shirt
        torsoS.fillEllipsoid(cx: 5.5, cy: 8.5, cz: 3.5, rx: 4.8, ry: 5.2, rz: 2.8, type: .cloth)
        let torso = sculptNode(torsoS, name: "torso", colors: colors)
        torso.position.y = 12 * u
        root.addChildNode(torso)

        // --- Arms ---
        let armL = SCNNode()
        armL.name = "arm_L"
        armL.position = SCNVector3(-6.5 * u, 20 * u, 0)
        let armLS = VoxelSculpture(sizeX: 5, sizeY: 12, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, -10, -2.5) * u)
        armLS.fillCylinder(c0: 2.5, c1: 2.5, a0: 3, a1: 10, radius: 1.5, type: .cloth)
        armLS.fillSphere(cx: 2.5, cy: 1.5, cz: 2.5, r: 1.7, type: .skin)
        armL.addChildNode(sculptNode(armLS, name: "arm_L_mesh", colors: colors))
        root.addChildNode(armL)

        let armR = SCNNode()
        armR.name = "arm_R"
        armR.position = SCNVector3(6.5 * u, 20 * u, 0)
        let armRS = VoxelSculpture(sizeX: 5, sizeY: 12, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, -10, -2.5) * u)
        armRS.fillCylinder(c0: 2.5, c1: 2.5, a0: 3, a1: 10, radius: 1.5, type: .cloth)
        armRS.fillSphere(cx: 2.5, cy: 1.5, cz: 2.5, r: 1.7, type: .skin)
        armR.addChildNode(sculptNode(armRS, name: "arm_R_mesh", colors: colors))
        root.addChildNode(armR)

        // --- Head ---
        let headS = VoxelSculpture(sizeX: 10, sizeY: 10, sizeZ: 10,
                                   origin: SIMD3<Float>(-5, 0, -5) * u)
        headS.fillEllipsoid(cx: 5, cy: 5, cz: 5, rx: 4.2, ry: 4.5, rz: 4.0, type: .skin)
        // Eyes
        headS.fillBox(x0: 2, y0: 5, z0: 8, x1: 3, y1: 6, z1: 9, type: .canvas) // white via override
        headS.fillBox(x0: 6, y0: 5, z0: 8, x1: 7, y1: 6, z1: 9, type: .canvas)
        headS.set(3, 5, 9, .iron) // pupil
        headS.set(6, 5, 9, .iron)
        // Nose
        headS.fillSphere(cx: 5, cy: 4, cz: 8.5, r: 0.9, type: .skin)
        // Hair: top cap + back of head (+Z is forward, so low Z is the nape)
        for y in 7...9 {
            for z in 0...8 {
                for x in 1...8 {
                    let dx = Float(x) + 0.5 - 5
                    let dz = Float(z) + 0.5 - 5
                    if dx * dx + dz * dz < 16 { headS.set(x, y, z, .hair) }
                }
            }
        }
        // Back hair / nape (covers the bare rear of the head ellipsoid)
        for y in 3...8 {
            for z in 0...2 {
                for x in 1...8 {
                    let dx = Float(x) + 0.5 - 5
                    let halfW = 3.6 - Float(2 - z) * 0.35
                    if abs(dx) <= halfW { headS.set(x, y, z, .hair) }
                }
            }
        }
        // Sideburns
        headS.fillBox(x0: 0, y0: 4, z0: 3, x1: 1, y1: 7, z1: 6, type: .hair)
        headS.fillBox(x0: 8, y0: 4, z0: 3, x1: 9, y1: 7, z1: 6, type: .hair)

        let headColors = colors.merging([
            .canvas: UIColor.white,
            .iron: UIColor.black,
        ]) { _, new in new }

        let head = sculptNode(headS, name: "head", colors: headColors)
        head.position.y = 23 * u
        root.addChildNode(head)

        if let hatColor = palette.hat {
            let hatS = VoxelSculpture(sizeX: 14, sizeY: 6, sizeZ: 14,
                                      origin: SIMD3<Float>(-7, 0, -7) * u)
            hatS.fillCylinder(c0: 7, c1: 7, a0: 0, a1: 1, radius: 6.5, type: .brass) // brim
            hatS.fillCylinder(c0: 7, c1: 7, a0: 1, a1: 4, radius: 3.5, type: .brass) // crown
            let hat = sculptNode(hatS, name: "hat", colors: [.brass: hatColor])
            hat.position.y = 31 * u
            root.addChildNode(hat)
        }

        let s = palette.scale
        root.scale = SCNVector3(s, s, s)
        return root
    }

    static func player(gender: SaveSlot.CharacterGender) -> SCNNode {
        build(palette: .player(man: gender == .man))
    }

    static func npc(_ personality: NPCPersonality) -> SCNNode {
        let node = build(palette: .npc(personality))
        if personality == .elder {
            let staffS = VoxelSculpture(sizeX: 3, sizeY: 28, sizeZ: 3,
                                        origin: SIMD3<Float>(-1.5, 0, -1.5) * uf)
            staffS.fillCylinder(c0: 1.5, c1: 1.5, a0: 0, a1: 27, radius: 0.9, type: .darkWood)
            staffS.fillSphere(cx: 1.5, cy: 27, cz: 1.5, r: 1.4, type: .wood)
            let staff = staffS.makeNode(name: "staff")
            staff.position = SCNVector3(0.55, 0.05, 0)
            node.addChildNode(staff)
        }
        return node
    }
}

// MARK: - Animations

enum VoxelAnim {
    static let idleKey = "voxel_idle"
    static let walkKey = "voxel_walk"
    static let talkKey = "voxel_talk"
    static let jumpKey = "voxel_jump"

    static func playIdle(on character: SCNNode) {
        stopAll(on: character)
        guard let torso = character.childNode(withName: "torso", recursively: false) else { return }
        let breathe = SCNAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.02, z: 0, duration: 1.1),
            .moveBy(x: 0, y: -0.02, z: 0, duration: 1.1)
        ]))
        torso.runAction(breathe, forKey: idleKey)
    }

    static func playWalk(on character: SCNNode) {
        stopAll(on: character)
        let swing: Float = 0.55
        let dur = 0.28
        if let legL = character.childNode(withName: "leg_L", recursively: false) {
            legL.runAction(.repeatForever(.sequence([
                .rotateTo(x: CGFloat(swing), y: 0, z: 0, duration: dur),
                .rotateTo(x: CGFloat(-swing), y: 0, z: 0, duration: dur)
            ])), forKey: walkKey)
        }
        if let legR = character.childNode(withName: "leg_R", recursively: false) {
            legR.runAction(.repeatForever(.sequence([
                .rotateTo(x: CGFloat(-swing), y: 0, z: 0, duration: dur),
                .rotateTo(x: CGFloat(swing), y: 0, z: 0, duration: dur)
            ])), forKey: walkKey)
        }
        if let armL = character.childNode(withName: "arm_L", recursively: false) {
            armL.runAction(.repeatForever(.sequence([
                .rotateTo(x: CGFloat(-swing), y: 0, z: 0, duration: dur),
                .rotateTo(x: CGFloat(swing), y: 0, z: 0, duration: dur)
            ])), forKey: walkKey)
        }
        if let armR = character.childNode(withName: "arm_R", recursively: false) {
            armR.runAction(.repeatForever(.sequence([
                .rotateTo(x: CGFloat(swing), y: 0, z: 0, duration: dur),
                .rotateTo(x: CGFloat(-swing), y: 0, z: 0, duration: dur)
            ])), forKey: walkKey)
        }
    }

    static func playJump(on character: SCNNode) {
        stopAll(on: character)
        let tuck = SCNAction.rotateTo(x: -0.85, y: 0, z: 0, duration: 0.08)
        tuck.timingMode = .easeOut
        let armsUp = SCNAction.rotateTo(x: -1.1, y: 0, z: 0.15, duration: 0.08)
        armsUp.timingMode = .easeOut

        character.childNode(withName: "leg_L", recursively: false)?.runAction(tuck, forKey: jumpKey)
        character.childNode(withName: "leg_R", recursively: false)?.runAction(tuck, forKey: jumpKey)
        character.childNode(withName: "arm_L", recursively: false)?.runAction(
            .rotateTo(x: -1.1, y: 0, z: -0.15, duration: 0.08), forKey: jumpKey)
        character.childNode(withName: "arm_R", recursively: false)?.runAction(armsUp, forKey: jumpKey)

        if let torso = character.childNode(withName: "torso", recursively: false) {
            torso.runAction(.rotateTo(x: 0.12, y: 0, z: 0, duration: 0.08), forKey: jumpKey)
        }
    }

    static func playTalk(on character: SCNNode) {
        stopAll(on: character)
        playIdle(on: character)
        if let head = character.childNode(withName: "head", recursively: false) {
            head.runAction(.repeatForever(.sequence([
                .rotateTo(x: 0.12, y: 0.08, z: 0, duration: 0.4),
                .rotateTo(x: 0, y: -0.08, z: 0, duration: 0.4),
                .rotateTo(x: 0.05, y: 0, z: 0, duration: 0.35)
            ])), forKey: talkKey)
        }
    }

    static func playGesture(on character: SCNNode) {
        if let armR = character.childNode(withName: "arm_R", recursively: false) {
            armR.runAction(.sequence([
                .rotateTo(x: -1.2, y: 0, z: 0.3, duration: 0.3),
                .rotateTo(x: -0.9, y: 0, z: 0.3, duration: 0.15),
                .rotateTo(x: -1.2, y: 0, z: 0.3, duration: 0.15),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.3)
            ]), forKey: "gesture")
        }
    }

    static func stopAll(on character: SCNNode) {
        character.enumerateChildNodes { node, _ in
            node.removeAction(forKey: idleKey)
            node.removeAction(forKey: walkKey)
            node.removeAction(forKey: talkKey)
            node.removeAction(forKey: jumpKey)
        }
        for name in ["leg_L", "leg_R", "arm_L", "arm_R", "head", "torso"] {
            if let n = character.childNode(withName: name, recursively: false) {
                n.eulerAngles = .init(0, 0, 0)
            }
        }
    }
}
