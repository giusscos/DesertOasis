import SceneKit
import UIKit

/// MagicaVoxel-style desert animals. Pivot at feet; +Z forward.
enum VoxelAnimalBuilder {

    private static var uf: Float { VoxelMetrics.unit }

    private static func sculptNode(_ sculpture: VoxelSculpture,
                                   name: String,
                                   colors: [VoxelType: UIColor] = [:]) -> SCNNode {
        sculpture.makeNode(name: name) { type in colors[type] ?? type.color }
    }

    static func build(_ kind: AnimalKind) -> SCNNode {
        switch kind {
        case .camel:  return camel()
        case .goat:   return goat()
        case .lizard: return lizard()
        case .bird:   return bird()
        }
    }

    // MARK: - Camel (~1.8 m)

    private static func camel() -> SCNNode {
        let root = SCNNode()
        root.name = "voxel_animal_camel"
        let u = uf

        let hide = UIColor(red: 0.72, green: 0.58, blue: 0.38, alpha: 1)
        let dark = UIColor(red: 0.45, green: 0.32, blue: 0.20, alpha: 1)
        let colors: [VoxelType: UIColor] = [
            .sand: hide,
            .canvas: hide,
            .darkWood: dark,
            .hair: UIColor(red: 0.35, green: 0.25, blue: 0.15, alpha: 1),
        ]

        // Body + hump
        let body = SCNNode()
        body.name = "body"
        body.position = SCNVector3(0, 14 * u, 0)
        let bodyS = VoxelSculpture(sizeX: 14, sizeY: 14, sizeZ: 22,
                                   origin: SIMD3<Float>(-7, -5, -11) * u)
        bodyS.fillEllipsoid(cx: 7, cy: 5, cz: 11, rx: 5.5, ry: 4.5, rz: 9.5, type: .sand)
        bodyS.fillEllipsoid(cx: 7, cy: 10, cz: 10, rx: 4.0, ry: 4.5, rz: 5.0, type: .canvas)
        body.addChildNode(sculptNode(bodyS, name: "body_mesh", colors: colors))
        root.addChildNode(body)

        // Neck (pivot at shoulders)
        let neck = SCNNode()
        neck.name = "neck"
        neck.position = SCNVector3(0, 16 * u, 8 * u)
        let neckS = VoxelSculpture(sizeX: 6, sizeY: 14, sizeZ: 8,
                                   origin: SIMD3<Float>(-3, 0, -2) * u)
        neckS.fillEllipsoid(cx: 3, cy: 7, cz: 3, rx: 2.2, ry: 6.5, rz: 2.8, type: .sand)
        neck.addChildNode(sculptNode(neckS, name: "neck_mesh", colors: colors))

        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 13 * u, 4 * u)
        let headS = VoxelSculpture(sizeX: 8, sizeY: 7, sizeZ: 10,
                                   origin: SIMD3<Float>(-4, -2, -3) * u)
        headS.fillEllipsoid(cx: 4, cy: 3, cz: 4, rx: 3.2, ry: 2.8, rz: 4.5, type: .sand)
        headS.fillBox(x0: 2, y0: 2, z0: 7, x1: 5, y1: 3, z1: 9, type: .darkWood) // snout tip
        headS.set(1, 5, 3, .hair)
        headS.set(6, 5, 3, .hair)
        head.addChildNode(sculptNode(headS, name: "head_mesh", colors: colors))
        neck.addChildNode(head)
        root.addChildNode(neck)

        addQuadrupedLegs(to: root, height: 14, spanX: 4.5, spanZ: 7,
                         legSize: (4, 15, 4), radius: 1.5, colors: colors, type: .darkWood)

        let tail = SCNNode()
        tail.name = "tail"
        tail.position = SCNVector3(0, 14 * u, -10 * u)
        let tailS = VoxelSculpture(sizeX: 3, sizeY: 8, sizeZ: 3,
                                   origin: SIMD3<Float>(-1.5, -7, -1.5) * u)
        tailS.fillCylinder(c0: 1.5, c1: 1.5, a0: 1, a1: 7, radius: 0.9, type: .hair)
        tail.addChildNode(sculptNode(tailS, name: "tail_mesh", colors: colors))
        root.addChildNode(tail)

        return root
    }

    // MARK: - Goat (~0.9 m)

    private static func goat() -> SCNNode {
        let root = SCNNode()
        root.name = "voxel_animal_goat"
        let u = uf

        let fleece = UIColor(red: 0.82, green: 0.76, blue: 0.62, alpha: 1)
        let colors: [VoxelType: UIColor] = [
            .canvas: fleece,
            .sand: fleece,
            .darkWood: UIColor(red: 0.35, green: 0.28, blue: 0.18, alpha: 1),
            .hair: UIColor(red: 0.55, green: 0.48, blue: 0.35, alpha: 1),
            .brass: UIColor(red: 0.70, green: 0.60, blue: 0.40, alpha: 1),
        ]

        let body = SCNNode()
        body.name = "body"
        body.position = SCNVector3(0, 8 * u, 0)
        let bodyS = VoxelSculpture(sizeX: 10, sizeY: 10, sizeZ: 14,
                                   origin: SIMD3<Float>(-5, -4, -7) * u)
        bodyS.fillEllipsoid(cx: 5, cy: 4.5, cz: 7, rx: 4.0, ry: 3.8, rz: 6.0, type: .canvas)
        body.addChildNode(sculptNode(bodyS, name: "body_mesh", colors: colors))
        root.addChildNode(body)

        let neck = SCNNode()
        neck.name = "neck"
        neck.position = SCNVector3(0, 10 * u, 5 * u)
        let neckS = VoxelSculpture(sizeX: 5, sizeY: 6, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, 0, -2) * u)
        neckS.fillEllipsoid(cx: 2.5, cy: 2.5, cz: 2, rx: 1.8, ry: 2.5, rz: 1.8, type: .sand)
        neck.addChildNode(sculptNode(neckS, name: "neck_mesh", colors: colors))

        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 5 * u, 2 * u)
        let headS = VoxelSculpture(sizeX: 7, sizeY: 7, sizeZ: 8,
                                   origin: SIMD3<Float>(-3.5, -2, -3) * u)
        headS.fillEllipsoid(cx: 3.5, cy: 3, cz: 3.5, rx: 2.8, ry: 2.5, rz: 3.2, type: .sand)
        // Horns
        headS.fillBox(x0: 1, y0: 5, z0: 2, x1: 1, y1: 6, z1: 3, type: .brass)
        headS.fillBox(x0: 5, y0: 5, z0: 2, x1: 5, y1: 6, z1: 3, type: .brass)
        headS.fillBox(x0: 2, y0: 2, z0: 6, x1: 4, y1: 3, z1: 7, type: .darkWood)
        head.addChildNode(sculptNode(headS, name: "head_mesh", colors: colors))
        neck.addChildNode(head)
        root.addChildNode(neck)

        addQuadrupedLegs(to: root, height: 8, spanX: 3.0, spanZ: 4.5,
                         legSize: (3, 9, 3), radius: 1.1, colors: colors, type: .darkWood)

        let tail = SCNNode()
        tail.name = "tail"
        tail.position = SCNVector3(0, 9 * u, -6 * u)
        let tailS = VoxelSculpture(sizeX: 3, sizeY: 4, sizeZ: 3,
                                   origin: SIMD3<Float>(-1.5, -3, -1.5) * u)
        tailS.fillSphere(cx: 1.5, cy: 1.5, cz: 1.5, r: 1.3, type: .hair)
        tail.addChildNode(sculptNode(tailS, name: "tail_mesh", colors: colors))
        root.addChildNode(tail)

        return root
    }

    // MARK: - Lizard (~0.35 m)

    private static func lizard() -> SCNNode {
        let root = SCNNode()
        root.name = "voxel_animal_lizard"
        let u = uf

        let skin = UIColor(red: 0.42, green: 0.58, blue: 0.32, alpha: 1)
        let belly = UIColor(red: 0.55, green: 0.65, blue: 0.40, alpha: 1)
        let colors: [VoxelType: UIColor] = [
            .cactus: skin,
            .leaf: belly,
            .darkWood: UIColor(red: 0.30, green: 0.40, blue: 0.22, alpha: 1),
        ]

        let body = SCNNode()
        body.name = "body"
        body.position = SCNVector3(0, 2.5 * u, 0)
        let bodyS = VoxelSculpture(sizeX: 6, sizeY: 4, sizeZ: 10,
                                   origin: SIMD3<Float>(-3, -1, -5) * u)
        bodyS.fillEllipsoid(cx: 3, cy: 1.5, cz: 5, rx: 2.2, ry: 1.4, rz: 4.2, type: .cactus)
        body.addChildNode(sculptNode(bodyS, name: "body_mesh", colors: colors))
        root.addChildNode(body)

        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 3 * u, 4.5 * u)
        let headS = VoxelSculpture(sizeX: 5, sizeY: 4, sizeZ: 5,
                                   origin: SIMD3<Float>(-2.5, -1, -1) * u)
        headS.fillEllipsoid(cx: 2.5, cy: 1.5, cz: 2, rx: 1.8, ry: 1.3, rz: 2.2, type: .cactus)
        headS.set(1, 2, 1, .darkWood)
        headS.set(3, 2, 1, .darkWood)
        head.addChildNode(sculptNode(headS, name: "head_mesh", colors: colors))
        root.addChildNode(head)

        // Stubby legs
        let legOffsets: [(String, Float, Float)] = [
            ("leg_FL", -2.2, 2.5), ("leg_FR", 2.2, 2.5),
            ("leg_BL", -2.2, -2.5), ("leg_BR", 2.2, -2.5),
        ]
        for (name, x, z) in legOffsets {
            let leg = SCNNode()
            leg.name = name
            leg.position = SCNVector3(x * u, 2.2 * u, z * u)
            let legS = VoxelSculpture(sizeX: 3, sizeY: 3, sizeZ: 3,
                                      origin: SIMD3<Float>(-1.5, -2.5, -1.5) * u)
            legS.fillEllipsoid(cx: 1.5, cy: 1.2, cz: 1.5, rx: 1.0, ry: 1.2, rz: 1.0, type: .darkWood)
            leg.addChildNode(sculptNode(legS, name: "\(name)_mesh", colors: colors))
            root.addChildNode(leg)
        }

        let tail = SCNNode()
        tail.name = "tail"
        tail.position = SCNVector3(0, 2.5 * u, -4.5 * u)
        let tailS = VoxelSculpture(sizeX: 3, sizeY: 3, sizeZ: 10,
                                   origin: SIMD3<Float>(-1.5, -1, -9) * u)
        for zi in 0..<9 {
            let r = 1.2 - Float(zi) * 0.1
            tailS.fillSphere(cx: 1.5, cy: 1.2, cz: Float(9 - zi), r: r, type: .cactus)
        }
        tail.addChildNode(sculptNode(tailS, name: "tail_mesh", colors: colors))
        root.addChildNode(tail)

        return root
    }

    // MARK: - Bird (~0.25 m)

    private static func bird() -> SCNNode {
        let root = SCNNode()
        root.name = "voxel_animal_bird"
        let u = uf

        let feather = UIColor(red: 0.55, green: 0.42, blue: 0.28, alpha: 1)
        let wing = UIColor(red: 0.40, green: 0.32, blue: 0.22, alpha: 1)
        let colors: [VoxelType: UIColor] = [
            .cloth: feather,
            .canvas: wing,
            .brass: UIColor(red: 0.85, green: 0.55, blue: 0.15, alpha: 1),
            .darkWood: UIColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1),
            .hair: UIColor(white: 0.15, alpha: 1),
        ]

        let body = SCNNode()
        body.name = "body"
        body.position = SCNVector3(0, 4 * u, 0)
        let bodyS = VoxelSculpture(sizeX: 5, sizeY: 5, sizeZ: 6,
                                   origin: SIMD3<Float>(-2.5, -2, -3) * u)
        bodyS.fillEllipsoid(cx: 2.5, cy: 2, cz: 3, rx: 2.0, ry: 1.8, rz: 2.5, type: .cloth)
        body.addChildNode(sculptNode(bodyS, name: "body_mesh", colors: colors))
        root.addChildNode(body)

        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 6 * u, 2.5 * u)
        let headS = VoxelSculpture(sizeX: 4, sizeY: 4, sizeZ: 5,
                                   origin: SIMD3<Float>(-2, -1.5, -1.5) * u)
        headS.fillSphere(cx: 2, cy: 1.8, cz: 2, r: 1.6, type: .cloth)
        headS.fillBox(x0: 1, y0: 1, z0: 3, x1: 2, y1: 1, z1: 4, type: .brass) // beak
        headS.set(1, 2, 1, .hair)
        headS.set(2, 2, 1, .hair)
        head.addChildNode(sculptNode(headS, name: "head_mesh", colors: colors))
        root.addChildNode(head)

        for (name, xSign) in [("wing_L", Float(-1)), ("wing_R", Float(1))] {
            let wingNode = SCNNode()
            wingNode.name = name
            wingNode.position = SCNVector3(xSign * 2 * u, 4.5 * u, 0)
            let wingS = VoxelSculpture(sizeX: 5, sizeY: 2, sizeZ: 6,
                                       origin: SIMD3<Float>(xSign < 0 ? -4 : -1, -1, -3) * u)
            wingS.fillEllipsoid(cx: xSign < 0 ? 2.5 : 2.5, cy: 1, cz: 3,
                                rx: 2.0, ry: 0.7, rz: 2.5, type: .canvas)
            wingNode.addChildNode(sculptNode(wingS, name: "\(name)_mesh", colors: colors))
            root.addChildNode(wingNode)
        }

        // Tiny perch legs
        for (name, x) in [("leg_L", Float(-1)), ("leg_R", Float(1))] {
            let leg = SCNNode()
            leg.name = name
            leg.position = SCNVector3(x * u, 2.5 * u, 0)
            let legS = VoxelSculpture(sizeX: 2, sizeY: 4, sizeZ: 2,
                                      origin: SIMD3<Float>(-1, -3.5, -1) * u)
            legS.fillBox(x0: 0, y0: 0, z0: 0, x1: 1, y1: 3, z1: 1, type: .darkWood)
            leg.addChildNode(sculptNode(legS, name: "\(name)_mesh", colors: colors))
            root.addChildNode(leg)
        }

        let tail = SCNNode()
        tail.name = "tail"
        tail.position = SCNVector3(0, 4 * u, -3 * u)
        let tailS = VoxelSculpture(sizeX: 3, sizeY: 2, sizeZ: 4,
                                   origin: SIMD3<Float>(-1.5, -1, -3) * u)
        tailS.fillEllipsoid(cx: 1.5, cy: 1, cz: 1.5, rx: 1.2, ry: 0.6, rz: 1.8, type: .canvas)
        tail.addChildNode(sculptNode(tailS, name: "tail_mesh", colors: colors))
        root.addChildNode(tail)

        return root
    }

    // MARK: - Shared legs

    private static func addQuadrupedLegs(to root: SCNNode,
                                         height: Float,
                                         spanX: Float,
                                         spanZ: Float,
                                         legSize: (Int, Int, Int),
                                         radius: Float,
                                         colors: [VoxelType: UIColor],
                                         type: VoxelType) {
        let u = uf
        let specs: [(String, Float, Float)] = [
            ("leg_FL", -spanX, spanZ),
            ("leg_FR", spanX, spanZ),
            ("leg_BL", -spanX, -spanZ),
            ("leg_BR", spanX, -spanZ),
        ]
        let (sx, sy, sz) = legSize
        for (name, x, z) in specs {
            let leg = SCNNode()
            leg.name = name
            leg.position = SCNVector3(x * u, height * u, z * u)
            let origin = SIMD3<Float>(-Float(sx) * 0.5, -Float(sy), -Float(sz) * 0.5) * u
            let legS = VoxelSculpture(sizeX: sx, sizeY: sy, sizeZ: sz, origin: origin)
            legS.fillCylinder(c0: Float(sx) * 0.5, c1: Float(sz) * 0.5,
                              a0: 1, a1: Float(sy) - 1, radius: radius, type: type)
            legS.fillEllipsoid(cx: Float(sx) * 0.5, cy: 1.0, cz: Float(sz) * 0.5,
                               rx: radius + 0.3, ry: 1.0, rz: radius + 0.4, type: type)
            leg.addChildNode(sculptNode(legS, name: "\(name)_mesh", colors: colors))
            root.addChildNode(leg)
        }
    }
}

// MARK: - Animal animations

enum AnimalAnim {
    static let idleKey = "animal_idle"
    static let walkKey = "animal_walk"
    static let reactKey = "animal_react"

    static func playIdle(on animal: SCNNode, kind: AnimalKind) {
        stopLocomotion(on: animal)
        switch kind {
        case .camel, .goat:
            if let neck = animal.childNode(withName: "neck", recursively: false) {
                neck.runAction(.repeatForever(.sequence([
                    .rotateTo(x: 0.08, y: 0, z: 0, duration: 1.4),
                    .rotateTo(x: -0.05, y: 0, z: 0, duration: 1.4)
                ])), forKey: idleKey)
            }
            if let body = animal.childNode(withName: "body", recursively: false) {
                body.runAction(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 0.015, z: 0, duration: 1.2),
                    .moveBy(x: 0, y: -0.015, z: 0, duration: 1.2)
                ])), forKey: idleKey)
            }
        case .lizard:
            if let tail = animal.childNode(withName: "tail", recursively: false) {
                tail.runAction(.repeatForever(.sequence([
                    .rotateTo(x: 0, y: 0.35, z: 0, duration: 0.55),
                    .rotateTo(x: 0, y: -0.35, z: 0, duration: 0.55)
                ])), forKey: idleKey)
            }
        case .bird:
            if let body = animal.childNode(withName: "body", recursively: false) {
                body.runAction(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 0.02, z: 0, duration: 0.45),
                    .moveBy(x: 0, y: -0.02, z: 0, duration: 0.45)
                ])), forKey: idleKey)
            }
            if let head = animal.childNode(withName: "head", recursively: false) {
                head.runAction(.repeatForever(.sequence([
                    .rotateTo(x: 0.15, y: 0, z: 0, duration: 0.7),
                    .rotateTo(x: 0, y: 0, z: 0, duration: 0.7)
                ])), forKey: idleKey)
            }
        }
    }

    static func playWalk(on animal: SCNNode, kind: AnimalKind) {
        stopLocomotion(on: animal)
        switch kind {
        case .camel, .goat, .lizard:
            let swing: Float = kind == .lizard ? 0.45 : (kind == .goat ? 0.50 : 0.40)
            let dur: Double = kind == .lizard ? 0.14 : (kind == .goat ? 0.20 : 0.30)
            let pairs: [(String, Float)] = [
                ("leg_FL", swing), ("leg_BR", swing),
                ("leg_FR", -swing), ("leg_BL", -swing),
            ]
            for (name, start) in pairs {
                guard let leg = animal.childNode(withName: name, recursively: false) else { continue }
                leg.runAction(.repeatForever(.sequence([
                    .rotateTo(x: CGFloat(start), y: 0, z: 0, duration: dur),
                    .rotateTo(x: CGFloat(-start), y: 0, z: 0, duration: dur)
                ])), forKey: walkKey)
            }
            if kind == .lizard, let tail = animal.childNode(withName: "tail", recursively: false) {
                tail.runAction(.repeatForever(.sequence([
                    .rotateTo(x: 0, y: 0.5, z: 0, duration: dur),
                    .rotateTo(x: 0, y: -0.5, z: 0, duration: dur)
                ])), forKey: walkKey)
            }
        case .bird:
            flapWings(on: animal, duration: 0.12, amplitude: 0.7, forever: true)
            for name in ["leg_L", "leg_R"] {
                guard let leg = animal.childNode(withName: name, recursively: false) else { continue }
                let sign: Float = name == "leg_L" ? 0.4 : -0.4
                leg.runAction(.repeatForever(.sequence([
                    .rotateTo(x: CGFloat(sign), y: 0, z: 0, duration: 0.12),
                    .rotateTo(x: CGFloat(-sign), y: 0, z: 0, duration: 0.12)
                ])), forKey: walkKey)
            }
        }
    }

    static func playReact(on animal: SCNNode, kind: AnimalKind, completion: (() -> Void)? = nil) {
        animal.removeAction(forKey: reactKey)
        let finish = SCNAction.run { _ in completion?() }

        switch kind {
        case .camel:
            let bob = SCNAction.sequence([
                .rotateTo(x: -0.2, y: 0.15, z: 0, duration: 0.25),
                .rotateTo(x: 0.1, y: -0.1, z: 0, duration: 0.3),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.25),
                finish
            ])
            if let neck = animal.childNode(withName: "neck", recursively: false) {
                neck.runAction(bob, forKey: reactKey)
            } else {
                animal.runAction(bob, forKey: reactKey)
            }

        case .goat:
            let hop = SCNAction.sequence([
                .moveBy(x: 0, y: 0.25, z: 0, duration: 0.15),
                .moveBy(x: 0, y: -0.25, z: 0, duration: 0.18),
                finish
            ])
            hop.timingMode = .easeOut
            animal.runAction(hop, forKey: reactKey)
            if let neck = animal.childNode(withName: "neck", recursively: false) {
                neck.runAction(.sequence([
                    .rotateTo(x: -0.4, y: 0, z: 0, duration: 0.12),
                    .rotateTo(x: 0.2, y: 0, z: 0, duration: 0.15),
                    .rotateTo(x: 0, y: 0, z: 0, duration: 0.12)
                ]), forKey: reactKey)
            }

        case .lizard:
            // Dart sideways briefly (caller may also nudge position).
            let dart = SCNAction.sequence([
                .moveBy(x: 0.35, y: 0, z: 0.1, duration: 0.12),
                .moveBy(x: -0.35, y: 0, z: -0.1, duration: 0.18),
                finish
            ])
            animal.runAction(dart, forKey: reactKey)
            if let tail = animal.childNode(withName: "tail", recursively: false) {
                tail.runAction(.sequence([
                    .rotateTo(x: 0, y: 0.8, z: 0, duration: 0.1),
                    .rotateTo(x: 0, y: -0.8, z: 0, duration: 0.12),
                    .rotateTo(x: 0, y: 0, z: 0, duration: 0.12)
                ]), forKey: reactKey)
            }

        case .bird:
            flapWings(on: animal, duration: 0.08, amplitude: 1.1, forever: false, key: reactKey)
            let hop = SCNAction.sequence([
                .moveBy(x: 0, y: 0.35, z: 0, duration: 0.12),
                .moveBy(x: 0, y: -0.35, z: 0, duration: 0.16),
                finish
            ])
            animal.runAction(hop, forKey: reactKey)
        }
    }

    private static func flapWings(on animal: SCNNode,
                                  duration: Double,
                                  amplitude: Float,
                                  forever: Bool,
                                  key: String = walkKey) {
        for (name, sign) in [("wing_L", Float(-1)), ("wing_R", Float(1))] {
            guard let wing = animal.childNode(withName: name, recursively: false) else { continue }
            let seq = SCNAction.sequence([
                .rotateTo(x: 0, y: 0, z: CGFloat(sign * amplitude), duration: duration),
                .rotateTo(x: 0, y: 0, z: CGFloat(sign * -0.15), duration: duration)
            ])
            wing.runAction(forever ? .repeatForever(seq) : .repeat(seq, count: 4), forKey: key)
        }
    }

    static func stopLocomotion(on animal: SCNNode) {
        let names = ["body", "neck", "head", "tail",
                     "leg_FL", "leg_FR", "leg_BL", "leg_BR", "leg_L", "leg_R",
                     "wing_L", "wing_R"]
        for name in names {
            if let n = animal.childNode(withName: name, recursively: false) {
                n.removeAction(forKey: idleKey)
                n.removeAction(forKey: walkKey)
                n.removeAction(forKey: reactKey)
                // Reset mild rotations so idle/walk don't stack crooked
                if name.hasPrefix("leg") || name.hasPrefix("wing") {
                    n.eulerAngles = SCNVector3Zero
                }
            }
        }
        animal.removeAction(forKey: idleKey)
        animal.removeAction(forKey: walkKey)
        animal.removeAction(forKey: reactKey)
    }
}
