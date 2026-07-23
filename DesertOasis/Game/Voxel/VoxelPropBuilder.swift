import SceneKit
import UIKit

/// Desert props as MagicaVoxel-style sculptures: many small unit cubes forming
/// organic shapes (cylinders, spheres, ellipsoids) — never one stretched box.
enum VoxelPropBuilder {

    private static var uf: Float { VoxelMetrics.unit }

    // MARK: - Lantern

    static func hangingLantern(intensity: CGFloat = 420, range: CGFloat = 8) -> SCNNode {
        let root = SCNNode()
        root.name = "hanging_lantern"

        let s = VoxelSculpture(sizeX: 6, sizeY: 8, sizeZ: 6,
                               origin: SIMD3<Float>(-3, -4, -3) * uf)
        // Glass body
        s.fillEllipsoid(cx: 2.5, cy: 3.5, cz: 2.5, rx: 2.2, ry: 2.8, rz: 2.2, type: .brass)
        // Clear center for glow look — overwrite mid with brass shell only via tube-ish
        for y in 2...5 {
            for z in 1...4 {
                for x in 1...4 {
                    let dx = Float(x) + 0.5 - 2.5
                    let dz = Float(z) + 0.5 - 2.5
                    if dx * dx + dz * dz < 1.2 { s.set(x, y, z, .air) }
                }
            }
        }
        // Flame voxel
        s.fillSphere(cx: 2.5, cy: 3.5, cz: 2.5, r: 1.2, type: .brass)
        s.fillBox(x0: 1, y0: 6, z0: 1, x1: 4, y1: 6, z1: 4, type: .iron)
        s.fillBox(x0: 2, y0: 7, z0: 2, x1: 3, y1: 7, z1: 3, type: .darkWood)

        let mesh = s.makeNode(name: "lantern_mesh") { type in
            if type == .brass {
                return UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1)
            }
            return type.color
        }
        mesh.geometry?.firstMaterial?.emission.contents = UIColor(red: 1.0, green: 0.55, blue: 0.18, alpha: 1)
        mesh.geometry?.firstMaterial?.emission.intensity = 0.85
        mesh.geometry?.firstMaterial?.lightingModel = .constant
        root.addChildNode(mesh)

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.72, blue: 0.38, alpha: 1)
        light.intensity = intensity
        light.attenuationStartDistance = 0.4
        light.attenuationEndDistance = range
        light.castsShadow = false
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position.y = -0.05
        root.addChildNode(lightNode)

        return root
    }

    // MARK: - Cactus

    static func saguaroCactus() -> SCNNode {
        // ~0.5 × 2.5 × 0.5 trunk with arms — stair-stepped cylinders
        let s = VoxelSculpture(sizeX: 20, sizeY: 42, sizeZ: 12,
                               origin: SIMD3<Float>(-10, 0, -6) * uf)

        s.fillCylinder(c0: 10, c1: 6, a0: 0, a1: 40, radius: 3.2, type: .cactus)
        // Vertical ridges (studs)
        for y in stride(from: 4, to: 38, by: 3) {
            s.set(6, y, 6, .cactus)
            s.set(13, y, 6, .cactus)
            s.set(10, y, 2, .cactus)
            s.set(10, y, 9, .cactus)
        }

        // Left arm: out then up
        s.fillCylinder(axis: .x, c0: 18, c1: 6, a0: 4, a1: 10, radius: 2.2, type: .cactus)
        s.fillCylinder(c0: 4, c1: 6, a0: 18, a1: 30, radius: 2.2, type: .cactus)
        // Right arm
        s.fillCylinder(axis: .x, c0: 14, c1: 6, a0: 10, a1: 16, radius: 2.0, type: .cactus)
        s.fillCylinder(c0: 16, c1: 6, a0: 14, a1: 24, radius: 2.0, type: .cactus)

        // Rounded tops
        s.fillSphere(cx: 10, cy: 40, cz: 6, r: 2.8, type: .cactus)
        s.fillSphere(cx: 4, cy: 30, cz: 6, r: 2.0, type: .cactus)
        s.fillSphere(cx: 16, cy: 24, cz: 6, r: 1.8, type: .cactus)

        let node = s.makeNode(name: "prop_cactus_saguaro")
        return node
    }

    static func barrelCactus() -> SCNNode {
        let s = VoxelSculpture(sizeX: 14, sizeY: 12, sizeZ: 14,
                               origin: SIMD3<Float>(-7, 0, -7) * uf)
        s.fillEllipsoid(cx: 7, cy: 5, cz: 7, rx: 5.5, ry: 5.0, rz: 5.5, type: .cactus)
        // Ribs
        for i in 0..<8 {
            let a = Float(i) / 8.0 * Float.pi * 2
            let x = 7 + cos(a) * 5.2
            let z = 7 + sin(a) * 5.2
            for y in 1...9 {
                s.set(Int(round(x)), y, Int(round(z)), .cactus)
            }
        }
        s.fillSphere(cx: 7, cy: 9.5, cz: 7, r: 2.5, type: .cactus)
        return s.makeNode(name: "prop_cactus_barrel")
    }

    // MARK: - Rocks

    static func smallRock() -> SCNNode {
        let s = VoxelSculpture(sizeX: 10, sizeY: 6, sizeZ: 10,
                               origin: SIMD3<Float>(-5, 0, -5) * uf)
        s.fillEllipsoid(cx: 5, cy: 2.5, cz: 5, rx: 4.0, ry: 2.5, rz: 3.5, type: .rock)
        s.fillEllipsoid(cx: 6.5, cy: 3.5, cz: 4.5, rx: 2.0, ry: 1.5, rz: 2.0, type: .rock)
        return s.makeNode(name: "prop_rock_small")
    }

    static func rockCluster() -> SCNNode {
        let s = VoxelSculpture(sizeX: 18, sizeY: 8, sizeZ: 16,
                               origin: SIMD3<Float>(-9, 0, -8) * uf)
        s.fillEllipsoid(cx: 8, cy: 2.5, cz: 8, rx: 5, ry: 2.8, rz: 4, type: .rock)
        s.fillEllipsoid(cx: 13, cy: 1.8, cz: 10, rx: 3, ry: 2, rz: 2.5, type: .rock)
        s.fillEllipsoid(cx: 4, cy: 2.2, cz: 6, rx: 3.5, ry: 2.4, rz: 3, type: .rock)
        s.fillEllipsoid(cx: 10, cy: 1.2, cz: 4, rx: 2.2, ry: 1.4, rz: 2.2, type: .rock)
        s.fillEllipsoid(cx: 7, cy: 4.5, cz: 8, rx: 2, ry: 1.5, rz: 1.8, type: .rock)
        return s.makeNode(name: "prop_rock_cluster")
    }

    // MARK: - Trees

    static func palmTree() -> SCNNode {
        let root = SCNNode()
        root.name = "prop_palm"

        let trunk = VoxelSculpture(sizeX: 10, sizeY: 70, sizeZ: 10,
                                   origin: SIMD3<Float>(-3, 0, -5) * uf)
        // Slightly leaning trunk via stacked offset spheres
        for y in 0..<68 {
            let lean = Float(y) * 0.04
            trunk.fillSphere(cx: 5 + lean, cy: Float(y), cz: 5, r: 2.2 - Float(y) * 0.005, type: .wood)
        }
        root.addChildNode(trunk.makeNode(name: "trunk"))

        let crown = SCNNode()
        crown.position = SCNVector3(0.45, 4.25, 0)
        root.addChildNode(crown)

        let nub = VoxelSculpture(sizeX: 10, sizeY: 6, sizeZ: 10,
                                 origin: SIMD3<Float>(-5, -2, -5) * uf)
        nub.fillSphere(cx: 5, cy: 2, cz: 5, r: 3.5, type: .leaf)
        crown.addChildNode(nub.makeNode(name: "crown_nub"))

        for i in 0..<8 {
            let angle = Float(i) / 8.0 * Float.pi * 2
            let frond = VoxelSculpture(sizeX: 4, sizeY: 4, sizeZ: 22,
                                       origin: SIMD3<Float>(-2, -1, 0) * uf)
            // Tapered frond as chain of spheres
            for z in 0..<20 {
                let t = Float(z) / 20
                let r = 1.6 * (1 - t * 0.85)
                frond.fillSphere(cx: 2, cy: 1.5 - t * 0.8, cz: Float(z), r: r, type: .leaf)
            }
            let node = frond.makeNode(name: "frond_\(i)")
            node.eulerAngles = SCNVector3(0.35, angle, 0)
            crown.addChildNode(node)
        }

        crown.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0, z: 0.08, duration: 2.2),
            .rotateBy(x: 0, y: 0, z: -0.08, duration: 2.2)
        ])))
        return root
    }

    static func deadTree() -> SCNNode {
        let s = VoxelSculpture(sizeX: 24, sizeY: 52, sizeZ: 16,
                               origin: SIMD3<Float>(-12, 0, -8) * uf)
        // Trunk
        for y in 0..<42 {
            s.fillSphere(cx: 12, cy: Float(y), cz: 8, r: 1.8, type: .darkWood)
        }
        // Branches as arcs of spheres
        for i in 0..<14 {
            let t = Float(i) / 13
            s.fillSphere(cx: 12 + t * 10, cy: 34 + t * 4, cz: 8, r: 1.4 - t * 0.5, type: .darkWood)
        }
        for i in 0..<12 {
            let t = Float(i) / 11
            s.fillSphere(cx: 12 - t * 8, cy: 28 + t * 3, cz: 8 + t * 2, r: 1.2 - t * 0.4, type: .darkWood)
        }
        for i in 0..<8 {
            let t = Float(i) / 7
            s.fillSphere(cx: 12 + t * 3, cy: 22 + t * 2, cz: 8 + t * 5, r: 1.0, type: .darkWood)
        }
        return s.makeNode(name: "prop_dead_tree")
    }

    static func tumbleweed() -> SCNNode {
        let s = VoxelSculpture(sizeX: 12, sizeY: 12, sizeZ: 12,
                               origin: SIMD3<Float>(-6, 0, -6) * uf)
        s.fillSphere(cx: 6, cy: 5.5, cz: 6, r: 4.5, type: .wood)
        // Deterministic pockmarks for a lacy tumbleweed look
        let holes: [(Int, Int, Int)] = [
            (3, 4, 3), (8, 6, 4), (5, 8, 7), (4, 3, 8), (7, 5, 2),
            (2, 6, 6), (9, 4, 5), (6, 7, 9), (4, 5, 5), (7, 3, 7),
        ]
        for h in holes { s.set(h.0, h.1, h.2, .air) }
        let node = s.makeNode(name: "prop_tumbleweed") { _ in
            UIColor(red: 0.55, green: 0.45, blue: 0.28, alpha: 1)
        }
        node.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 2.5)))
        return node
    }

    // MARK: - Camp

    static func tent(scale: Float = 1.0) -> SCNNode {
        let root = SCNNode()
        root.name = "voxel_tent"
        root.scale = SCNVector3(scale, scale, scale)

        // A-frame from many cubes along two slanted planes
        let s = VoxelSculpture(sizeX: 36, sizeY: 38, sizeZ: 50,
                               origin: SIMD3<Float>(-18, 0, -25) * uf)

        // Left / right canvas walls — stepped roof
        for z in 0..<50 {
            for y in 0..<36 {
                let halfWidth = 16 - Int(Float(y) * 0.42)
                guard halfWidth > 1 else { continue }
                // Left wall thickness
                s.set(18 - halfWidth, y, z, .canvas)
                s.set(18 - halfWidth + 1, y, z, .canvas)
                // Right wall
                s.set(18 + halfWidth - 1, y, z, .canvas)
                s.set(18 + halfWidth - 2, y, z, .canvas)
            }
        }
        // Ridge beam
        for z in 0..<50 {
            s.fillBox(x0: 17, y0: 35, z0: z, x1: 18, y1: 36, z1: z, type: .darkWood)
        }
        // Back wall
        for y in 0..<22 {
            let halfWidth = 16 - Int(Float(y) * 0.42)
            for x in (18 - halfWidth)...(18 + halfWidth) {
                s.set(x, y, 2, .canvas)
                s.set(x, y, 3, .canvas)
            }
        }
        // Poles
        s.fillCylinder(c0: 4, c1: 46, a0: 0, a1: 30, radius: 0.9, type: .darkWood)
        s.fillCylinder(c0: 32, c1: 46, a0: 0, a1: 30, radius: 0.9, type: .darkWood)
        // Pegs
        s.fillSphere(cx: 2, cy: 1, cz: 48, r: 1.2, type: .rock)
        s.fillSphere(cx: 34, cy: 1, cz: 48, r: 1.2, type: .rock)

        root.addChildNode(s.makeNode(name: "tent_mesh"))

        let lantern = hangingLantern(intensity: 380, range: 6)
        lantern.position = SCNVector3(0, 1.9, 0)
        root.addChildNode(lantern)

        return root
    }

    static func waterBarrel() -> SCNNode {
        let root = SCNNode()
        root.name = "water_barrel"

        let s = VoxelSculpture(sizeX: 18, sizeY: 20, sizeZ: 18,
                               origin: SIMD3<Float>(-9, 0, -9) * uf)
        // Barrel body — slightly bulged cylinder
        for y in 0..<18 {
            let bulge = 1.0 - abs(Float(y) - 8.5) / 12
            let r = 6.5 + bulge * 1.2
            s.fillTube(c0: 9, c1: 9, a0: Float(y), a1: Float(y), outerR: r, innerR: r - 1.4, type: .wood)
        }
        // Iron bands
        for y in [3, 8, 13] {
            s.fillTube(c0: 9, c1: 9, a0: Float(y), a1: Float(y) + 0.9, outerR: 8.0, innerR: 6.8, type: .iron)
        }
        // Rim
        s.fillTube(c0: 9, c1: 9, a0: 17, a1: 18, outerR: 7.2, innerR: 5.5, type: .darkWood)
        // Interior floor
        s.fillCylinder(c0: 9, c1: 9, a0: 0, a1: 1, radius: 6.0, type: .wood)

        root.addChildNode(s.makeNode(name: "barrel_mesh"))

        let water = VoxelSculpture(sizeX: 14, sizeY: 2, sizeZ: 14, origin: SIMD3<Float>(-7, 0, -7) * uf)
        water.fillCylinder(c0: 7, c1: 7, a0: 0, a1: 1, radius: 5.5, type: .water)
        let waterNode = water.makeNode(name: "water_surface")
        waterNode.position.y = 0.08
        waterNode.scale.y = 0.15
        waterNode.isHidden = true
        root.addChildNode(waterNode)

        let fillPoint = SCNNode()
        fillPoint.name = "fill_point"
        fillPoint.position.y = 1.2
        root.addChildNode(fillPoint)

        return root
    }

    static func campfire() -> SCNNode {
        let fire = SCNNode()
        fire.name = "campfire"

        // ~1.4 m wide ring, ~1.0 m tall flame stack — sits flush on camp sand.
        let s = VoxelSculpture(sizeX: 28, sizeY: 22, sizeZ: 28,
                               origin: SIMD3<Float>(-14, 0, -14) * uf)

        // Multi-layer stone ring (base flush with ground, stacked up)
        for layer in 0..<3 {
            let cy = Float(layer) * 1.6 + 1.0
            let ringR: Float = 9.5 - Float(layer) * 0.6
            for i in 0..<14 {
                let a = Float(i) / 14.0 * Float.pi * 2 + Float(layer) * 0.22
                let x = 14 + cos(a) * ringR
                let z = 14 + sin(a) * ringR
                s.fillEllipsoid(cx: x, cy: cy, cz: z,
                                rx: 2.0 - Float(layer) * 0.2,
                                ry: 1.4,
                                rz: 2.0 - Float(layer) * 0.2,
                                type: .rock)
            }
        }
        // Ash / charcoal pad inside the ring
        s.fillCylinder(c0: 14, c1: 14, a0: 0, a1: 1.2, radius: 6.5, type: .darkWood)

        // Crossed log layers
        for i in 0..<12 {
            let t = Float(i) / 11
            s.fillSphere(cx: 6 + t * 16, cy: 3.2, cz: 14, r: 1.35, type: .darkWood)
        }
        for i in 0..<12 {
            let t = Float(i) / 11
            s.fillSphere(cx: 14, cy: 4.4, cz: 6 + t * 16, r: 1.25, type: .darkWood)
        }
        for i in 0..<10 {
            let t = Float(i) / 9
            s.fillSphere(cx: 8 + t * 12, cy: 5.8, cz: 9 + t * 8, r: 1.15, type: .wood)
        }
        for i in 0..<8 {
            let t = Float(i) / 7
            s.fillSphere(cx: 9 + t * 8, cy: 7.2, cz: 16 - t * 6, r: 1.0, type: .wood)
        }

        // Layered flame / ember stack
        s.fillSphere(cx: 14, cy: 5.5, cz: 14, r: 3.2, type: .brass)
        s.fillSphere(cx: 14, cy: 8.5, cz: 14, r: 2.4, type: .brass)
        s.fillSphere(cx: 14, cy: 11.0, cz: 14, r: 1.7, type: .brass)
        s.fillSphere(cx: 13.2, cy: 13.5, cz: 14.4, r: 1.1, type: .brass)
        s.fillSphere(cx: 14.6, cy: 15.5, cz: 13.6, r: 0.8, type: .brass)

        let mesh = s.makeNode(name: "campfire_mesh") { type in
            if type == .brass {
                return UIColor(red: 1.0, green: 0.35, blue: 0.05, alpha: 1)
            }
            return type.color
        }
        mesh.geometry?.firstMaterial?.emission.contents = UIColor(red: 1.0, green: 0.4, blue: 0.08, alpha: 1)
        mesh.geometry?.firstMaterial?.emission.intensity = 0.9
        fire.addChildNode(mesh)

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.55, blue: 0.22, alpha: 1)
        light.intensity = 900
        light.attenuationStartDistance = 0.5
        light.attenuationEndDistance = 18
        light.castsShadow = false
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position.y = 0.85
        fire.addChildNode(lightNode)

        let bounce = SCNLight()
        bounce.type = .omni
        bounce.color = UIColor(red: 1.0, green: 0.45, blue: 0.15, alpha: 1)
        bounce.intensity = 220
        bounce.attenuationStartDistance = 0.2
        bounce.attenuationEndDistance = 8
        let bounceNode = SCNNode()
        bounceNode.light = bounce
        bounceNode.position = SCNVector3(0, 0.35, 0)
        fire.addChildNode(bounceNode)

        return fire
    }

    // MARK: - Lobby furniture

    static func lobbyTentShell() -> SCNNode {
        let root = SCNNode()
        root.name = "lobby_tent"

        // Coarser unit for the large lobby shell (still stair-stepped cubes, fewer cells).
        let lu = uf * 2.5
        let s = VoxelSculpture(sizeX: 56, sizeY: 40, sizeZ: 88,
                               origin: SIMD3<Float>(-28, 0, -44) * lu)
        for z in 0..<88 {
            for y in 0..<36 {
                let halfWidth = 24 - Int(Float(y) * 0.55)
                guard halfWidth > 2 else { continue }
                s.set(28 - halfWidth, y, z, .canvas)
                s.set(28 - halfWidth + 1, y, z, .canvas)
                s.set(28 + halfWidth - 1, y, z, .canvas)
                s.set(28 + halfWidth - 2, y, z, .canvas)
            }
        }
        for y in 0..<24 {
            let halfWidth = 24 - Int(Float(y) * 0.55)
            for x in (28 - halfWidth)...(28 + halfWidth) {
                s.set(x, y, 1, .canvas)
                s.set(x, y, 2, .canvas)
            }
        }
        root.addChildNode(s.makeNode(name: "lobby_tent_mesh", unit: lu))

        let lantern = hangingLantern(intensity: 650, range: 11)
        lantern.position = SCNVector3(0, 3.8, 0)
        lantern.name = "lantern"
        root.addChildNode(lantern)

        let signS = VoxelSculpture(sizeX: 18, sizeY: 4, sizeZ: 2, origin: SIMD3<Float>(-9, 0, -1) * lu)
        signS.fillBox(x0: 0, y0: 0, z0: 0, x1: 17, y1: 3, z1: 1, type: .wood)
        let sign = signS.makeNode(name: "sign_text", unit: lu)
        sign.position = SCNVector3(0, 3.0, 5.2)
        root.addChildNode(sign)

        return root
    }

    static func lobbyBed() -> SCNNode {
        let root = SCNNode()
        root.name = "lobby_bed"

        let s = VoxelSculpture(sizeX: 32, sizeY: 14, sizeZ: 38,
                               origin: SIMD3<Float>(-16, 0, -19) * uf)
        // Frame
        s.fillBox(x0: 1, y0: 2, z0: 1, x1: 30, y1: 5, z1: 36, type: .wood)
        // Legs
        for (x, z) in [(1, 1), (29, 1), (1, 35), (29, 35)] {
            s.fillBox(x0: x, y0: 0, z0: z, x1: x + 1, y1: 2, z1: z + 1, type: .darkWood)
        }
        // Mattress
        s.fillBox(x0: 2, y0: 5, z0: 2, x1: 29, y1: 8, z1: 35, type: .canvas)
        // Pillow
        s.fillEllipsoid(cx: 16, cy: 9.5, cz: 6, rx: 9, ry: 1.8, rz: 3.5, type: .cloth)

        root.addChildNode(s.makeNode(name: "bed_mesh"))

        let diaryColors: [UIColor] = [
            UIColor(red: 0.65, green: 0.15, blue: 0.12, alpha: 1),
            UIColor(red: 0.18, green: 0.45, blue: 0.25, alpha: 1),
            UIColor(red: 0.20, green: 0.30, blue: 0.55, alpha: 1),
        ]
        // Two on the near row, one centered on the far row.
        let diaryPositions: [SCNVector3] = [
            SCNVector3(-0.38, 0.72, 0.32),
            SCNVector3( 0.38, 0.72, 0.32),
            SCNVector3( 0.00, 0.72, -0.18),
        ]
        // Solid book footprint — no empty padding voxels.
        let bw = 8, bh = 2, bd = 6
        let halfW = Float(bw) * 0.5
        let halfD = Float(bd) * 0.5
        for i in 0..<3 {
            let ds = VoxelSculpture(
                sizeX: bw, sizeY: bh, sizeZ: bd,
                origin: SIMD3<Float>(-halfW, 0, -halfD) * uf
            )
            ds.fillBox(x0: 0, y0: 0, z0: 0, x1: bw - 1, y1: bh - 1, z1: bd - 1, type: .cloth)
            let diary = ds.makeNode(name: "diary_\(i)") { _ in diaryColors[i] }
            diary.position = diaryPositions[i]

            // Spine on the right; cover sits flush over the body and opens R→L.
            let hinge = SCNNode()
            hinge.name = "hinge"
            hinge.position = SCNVector3(halfW * uf, Float(bh) * uf, 0)

            let coverS = VoxelSculpture(
                sizeX: bw, sizeY: 1, sizeZ: bd,
                origin: SIMD3<Float>(-Float(bw), 0, -halfD) * uf
            )
            coverS.fillBox(x0: 0, y0: 0, z0: 0, x1: bw - 1, y1: 0, z1: bd - 1, type: .cloth)
            let cover = coverS.makeNode(name: "cover") { _ in diaryColors[i] }
            cover.position = SCNVector3(0, 0, 0)
            hinge.addChildNode(cover)
            diary.addChildNode(hinge)

            root.addChildNode(diary)
        }

        return root
    }

    static func lobbyTable() -> SCNNode {
        let root = SCNNode()
        root.name = "settings_zone"

        let s = VoxelSculpture(sizeX: 28, sizeY: 16, sizeZ: 20,
                               origin: SIMD3<Float>(-14, 0, -10) * uf)
        // Top
        s.fillBox(x0: 1, y0: 13, z0: 1, x1: 26, y1: 14, z1: 18, type: .wood)
        // Legs
        for (x, z) in [(2, 2), (24, 2), (2, 16), (24, 16)] {
            s.fillCylinder(c0: Float(x), c1: Float(z), a0: 0, a1: 13, radius: 0.9, type: .darkWood)
        }
        root.addChildNode(s.makeNode(name: "table_mesh"))

        // Compass
        let compassS = VoxelSculpture(sizeX: 5, sizeY: 2, sizeZ: 5, origin: SIMD3<Float>(-2, 0, -2) * uf)
        compassS.fillCylinder(c0: 2, c1: 2, a0: 0, a1: 1, radius: 2.0, type: .brass)
        let compass = compassS.makeNode(name: "node_compass")
        compass.position = SCNVector3(-0.4, 1.0, 0.2)
        root.addChildNode(compass)

        // Map
        let mapS = VoxelSculpture(sizeX: 9, sizeY: 1, sizeZ: 6, origin: SIMD3<Float>(-4, 0, -3) * uf)
        mapS.fillBox(x0: 0, y0: 0, z0: 0, x1: 8, y1: 0, z1: 5, type: .canvas)
        let map = mapS.makeNode(name: "node_map")
        map.position = SCNVector3(0.35, 0.98, -0.15)
        root.addChildNode(map)

        let lantern = hangingLantern(intensity: 320, range: 5)
        lantern.name = "node_lantern"
        lantern.position = SCNVector3(0.5, 1.15, 0.25)
        root.addChildNode(lantern)

        let quillS = VoxelSculpture(sizeX: 2, sizeY: 2, sizeZ: 7, origin: SIMD3<Float>(-1, 0, -1) * uf)
        for z in 0..<6 {
            quillS.fillSphere(cx: 1, cy: 0.8, cz: Float(z), r: 0.6, type: .darkWood)
        }
        let quill = quillS.makeNode(name: "node_quill")
        quill.position = SCNVector3(-0.15, 0.98, 0.3)
        root.addChildNode(quill)

        let hg = VoxelSculpture(sizeX: 4, sizeY: 7, sizeZ: 4, origin: SIMD3<Float>(-2, 0, -2) * uf)
        hg.fillSphere(cx: 2, cy: 1.5, cz: 2, r: 1.5, type: .brass)
        hg.fillSphere(cx: 2, cy: 4.5, cz: 2, r: 1.5, type: .brass)
        hg.fillBox(x0: 1, y0: 2, z0: 1, x1: 2, y1: 4, z1: 2, type: .brass)
        let hourglass = hg.makeNode(name: "node_hourglass")
        hourglass.position = SCNVector3(0.1, 1.15, -0.3)
        hourglass.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 8)))
        root.addChildNode(hourglass)

        return root
    }

    // MARK: - Scatter into desert

    static func scatterProps(world: VoxelWorld, oases: [OasisInfo], seed: UInt64,
                             campClearRadius: Float = 22) -> SCNNode {
        let container = SCNNode()
        container.name = "voxel_props"
        var rng = SeededRandom(seed: seed &+ 999)
        let half = world.totalSize * 0.5

        func nearOasis(_ wx: Float, _ wz: Float) -> Bool {
            oases.contains {
                let dx = $0.position.x - wx; let dz = $0.position.z - wz
                return sqrt(dx * dx + dz * dz) < $0.radius * 2.5
            }
        }
        func nearCamp(_ wx: Float, _ wz: Float) -> Bool {
            sqrt(wx * wx + wz * wz) < campClearRadius
        }

        for _ in 0..<80 {
            let wx = rng.nextFloat() * world.totalSize - half
            let wz = rng.nextFloat() * world.totalSize - half
            if nearOasis(wx, wz) || nearCamp(wx, wz) { continue }
            let h = world.surfaceY(atWorldX: wx, worldZ: wz)
            let cactus = rng.nextFloat() > 0.4 ? saguaroCactus() : barrelCactus()
            let s = 0.8 + rng.nextFloat() * 0.5
            cactus.scale = SCNVector3(s, s, s)
            cactus.position = SCNVector3(wx, h, wz)
            cactus.eulerAngles.y = rng.nextFloat() * Float.pi * 2
            container.addChildNode(cactus)
        }

        for _ in 0..<120 {
            let wx = rng.nextFloat() * world.totalSize - half
            let wz = rng.nextFloat() * world.totalSize - half
            if nearCamp(wx, wz) { continue }
            let h = world.surfaceY(atWorldX: wx, worldZ: wz)
            let rock = rng.nextFloat() > 0.5 ? smallRock() : rockCluster()
            let s = 0.5 + rng.nextFloat() * 1.4
            rock.scale = SCNVector3(s, s * 0.7, s)
            rock.position = SCNVector3(wx, h, wz)
            rock.eulerAngles.y = rng.nextFloat() * Float.pi * 2
            container.addChildNode(rock)
        }

        for _ in 0..<25 {
            let wx = rng.nextFloat() * world.totalSize - half
            let wz = rng.nextFloat() * world.totalSize - half
            if nearOasis(wx, wz) || nearCamp(wx, wz) { continue }
            let h = world.surfaceY(atWorldX: wx, worldZ: wz)
            let tree = deadTree()
            tree.position = SCNVector3(wx, h, wz)
            tree.eulerAngles.y = rng.nextFloat() * Float.pi * 2
            container.addChildNode(tree)
        }

        for _ in 0..<15 {
            let wx = rng.nextFloat() * world.totalSize - half
            let wz = rng.nextFloat() * world.totalSize - half
            if nearCamp(wx, wz) { continue }
            let h = world.surfaceY(atWorldX: wx, worldZ: wz)
            let weed = tumbleweed()
            weed.position = SCNVector3(wx, h + 0.1, wz)
            container.addChildNode(weed)
        }

        for oasis in oases {
            let palmCount = 3 + Int(rng.nextFloat() * 4)
            for _ in 0..<palmCount {
                let angle = rng.nextFloat() * Float.pi * 2
                let dist = oasis.radius * 0.72 + rng.nextFloat() * oasis.radius * 0.22
                let px = oasis.position.x + cos(angle) * dist
                let pz = oasis.position.z + sin(angle) * dist
                let h = world.surfaceY(atWorldX: px, worldZ: pz)
                let palm = palmTree()
                palm.position = SCNVector3(px, h, pz)
                palm.eulerAngles.y = rng.nextFloat() * Float.pi * 2
                container.addChildNode(palm)
            }
        }

        return container
    }
}
