import SceneKit
import UIKit

// MARK: - Noise helpers

private func hash(_ x: Int, _ y: Int, seed: UInt64) -> Float {
    var n = UInt64(bitPattern: Int64(x &* 1619 &+ y &* 31337)) &+ seed &* 1000003
    n = n ^ (n >> 16)
    n = n &* 0x45d9f3b
    n = n ^ (n >> 16)
    return Float(n & 0xFFFFFF) / Float(0xFFFFFF)
}

private func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

private func valueNoise(_ x: Float, _ y: Float, seed: UInt64) -> Float {
    let xi = Int(floor(x)); let xf = x - floor(x)
    let yi = Int(floor(y)); let yf = y - floor(y)
    let v00 = hash(xi,     yi,     seed: seed)
    let v10 = hash(xi + 1, yi,     seed: seed)
    let v01 = hash(xi,     yi + 1, seed: seed)
    let v11 = hash(xi + 1, yi + 1, seed: seed)
    let ux = smoothstep(xf); let uy = smoothstep(yf)
    return (v00 * (1 - ux) + v10 * ux) * (1 - uy) + (v01 * (1 - ux) + v11 * ux) * uy
}

private func fbm(_ x: Float, _ y: Float, seed: UInt64, octaves: Int = 5) -> Float {
    var value: Float = 0; var amplitude: Float = 0.5; var frequency: Float = 1.0
    for o in 0..<octaves {
        value += valueNoise(x * frequency, y * frequency, seed: seed &+ UInt64(o * 7919)) * amplitude
        amplitude *= 0.5; frequency *= 2.0
    }
    return value
}

// MARK: - DesertGenerator

struct OasisInfo {
    let position: SCNVector3
    let radius: Float
}

struct DesertGenerator {
    let seed: UInt64
    let gridSize: Int        // number of vertices per side
    let cellSize: Float      // meters per cell
    let heightScale: Float   // max dune height
    let totalSize: Float     // gridSize * cellSize

    init(seed: UInt64, gridSize: Int = 120, cellSize: Float = 2.0, heightScale: Float = 6.0) {
        self.seed = seed
        self.gridSize = gridSize
        self.cellSize = cellSize
        self.heightScale = heightScale
        self.totalSize = Float(gridSize) * cellSize
    }

    func height(atWorldX wx: Float, worldZ wz: Float) -> Float {
        let nx = wx / totalSize * 4.0
        let nz = wz / totalSize * 4.0
        return fbm(nx, nz, seed: seed) * heightScale
    }

    // MARK: Build terrain node

    func buildTerrainNode() -> SCNNode {
        let n = gridSize
        var vertices   = [SCNVector3](repeating: .init(0, 0, 0), count: n * n)
        var normals    = [SCNVector3](repeating: .init(0, 1, 0), count: n * n)
        var texCoords  = [CGPoint](repeating: .zero, count: n * n)
        var indices    = [Int32]()
        indices.reserveCapacity((n - 1) * (n - 1) * 6)

        let offset = Float(n) * cellSize * 0.5

        for z in 0..<n {
            for x in 0..<n {
                let wx = Float(x) * cellSize - offset
                let wz = Float(z) * cellSize - offset
                let h  = height(atWorldX: wx, worldZ: wz)
                vertices[z * n + x] = SCNVector3(wx, h, wz)
                texCoords[z * n + x] = CGPoint(x: Double(x) / Double(n - 1),
                                               y: Double(z) / Double(n - 1))
            }
        }

        // Compute normals
        for z in 0..<n {
            for x in 0..<n {
                let hC = vertices[z * n + x].y
                let hR = x < n-1 ? vertices[z * n + x + 1].y : hC
                let hD = z < n-1 ? vertices[(z+1) * n + x].y : hC
                let nx_ = -(hR - hC) / cellSize
                let nz_ = -(hD - hC) / cellSize
                let len = sqrt(nx_ * nx_ + 1 + nz_ * nz_)
                normals[z * n + x] = SCNVector3(nx_ / len, 1 / len, nz_ / len)
            }
        }

        // Indices
        for z in 0..<(n - 1) {
            for x in 0..<(n - 1) {
                let tl = Int32(z * n + x)
                let tr = Int32(z * n + x + 1)
                let bl = Int32((z + 1) * n + x)
                let br = Int32((z + 1) * n + x + 1)
                indices.append(contentsOf: [tl, tr, br, tl, br, bl])
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let texSource    = SCNGeometrySource(textureCoordinates: texCoords)
        let element      = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry     = SCNGeometry(sources: [vertexSource, normalSource, texSource],
                                       elements: [element])
        geometry.firstMaterial = sandMaterial()

        let node = SCNNode(geometry: geometry)
        node.name = "terrain"
        return node
    }

    // MARK: Oasis placement

    func generateOases(count: Int = 5) -> [OasisInfo] {
        var oases: [OasisInfo] = []
        var rng = SeededRandom(seed: seed &+ 42)
        let half = totalSize * 0.5

        for i in 0..<count {
            var attempts = 0
            while attempts < 30 {
                let wx = rng.nextFloat() * totalSize - half
                let wz = rng.nextFloat() * totalSize - half
                let h = height(atWorldX: wx, worldZ: wz)
                // Prefer low areas for oases
                if h < heightScale * 0.35 {
                    let tooClose = oases.contains {
                        let dx = $0.position.x - wx
                        let dz = $0.position.z - wz
                        return sqrt(dx*dx + dz*dz) < 60
                    }
                    if !tooClose {
                        let radius = 6 + rng.nextFloat() * 8
                        oases.append(OasisInfo(position: SCNVector3(wx, h, wz), radius: radius))
                        break
                    }
                }
                attempts += 1
            }
            _ = i // suppress warning
        }
        return oases
    }

    // MARK: Build oasis node

    func buildOasisNode(info: OasisInfo) -> SCNNode {
        let container = SCNNode()
        container.position = info.position

        // Animated water disc (prop is 10 m diameter = 5 m radius; scale to match)
        let water = AssetLoader.loadProp("prop_oasis_water")
        let waterScale = info.radius / 5.0
        water.scale = SCNVector3(waterScale, 1, waterScale)
        water.position = SCNVector3(0, 0.05, 0)
        // Start ripple animation if present
        water.enumerateHierarchy { node, _ in
            for key in node.animationKeys { node.animationPlayer(forKey: key)?.play() }
        }
        container.addChildNode(water)

        // Palm trees around the oasis edge
        var rng = SeededRandom(seed: seed &+ UInt64(info.position.x.bitPattern))
        let palmCount = Int(3 + rng.nextFloat() * 4)
        for _ in 0..<palmCount {
            let angle = rng.nextFloat() * Float.pi * 2
            let dist  = info.radius * 0.72 + rng.nextFloat() * info.radius * 0.22
            let px = cos(angle) * dist
            let pz = sin(angle) * dist
            let palm = AssetLoader.loadProp("prop_palm_tree")
            palm.position = SCNVector3(px, 0, pz)
            palm.eulerAngles = SCNVector3(0, rng.nextFloat() * Float.pi * 2, 0)
            // Start sway animation
            palm.enumerateHierarchy { node, _ in
                for key in node.animationKeys { node.animationPlayer(forKey: key)?.play() }
            }
            container.addChildNode(palm)
        }
        return container
    }

    // MARK: Desert props (USDZ)

    private func buildCactus(rng: inout SeededRandom) -> SCNNode {
        let name = rng.nextFloat() > 0.4 ? "prop_cactus_saguaro" : "prop_cactus_barrel"
        let node = AssetLoader.loadProp(name)
        let s = 0.8 + rng.nextFloat() * 0.5
        node.scale = SCNVector3(s, s, s)
        return node
    }

    private func buildRock(rng: inout SeededRandom) -> SCNNode {
        let name = rng.nextFloat() > 0.5 ? "prop_rock_small" : "prop_rock_cluster"
        let node = AssetLoader.loadProp(name)
        let s = 0.5 + rng.nextFloat() * 1.4
        node.scale = SCNVector3(s, s * 0.7, s)
        return node
    }

    // MARK: Scatter props

    func scatterProps(around oases: [OasisInfo]) -> SCNNode {
        let container = SCNNode()
        var rng = SeededRandom(seed: seed &+ 999)
        let half = totalSize * 0.5

        func isNearOasis(_ wx: Float, _ wz: Float) -> Bool {
            oases.contains {
                let dx = $0.position.x - wx; let dz = $0.position.z - wz
                return sqrt(dx*dx + dz*dz) < $0.radius * 2.5
            }
        }

        // Tall saguaro and barrel cacti
        for _ in 0..<80 {
            let wx = rng.nextFloat() * totalSize - half
            let wz = rng.nextFloat() * totalSize - half
            if !isNearOasis(wx, wz) {
                let h = height(atWorldX: wx, worldZ: wz)
                let cactus = buildCactus(rng: &rng)
                cactus.position = SCNVector3(wx, h, wz)
                cactus.eulerAngles = SCNVector3(0, rng.nextFloat() * Float.pi * 2, 0)
                container.addChildNode(cactus)
            }
        }

        // Rocks (varied sizes)
        for _ in 0..<120 {
            let wx = rng.nextFloat() * totalSize - half
            let wz = rng.nextFloat() * totalSize - half
            let h = height(atWorldX: wx, worldZ: wz)
            let rock = buildRock(rng: &rng)
            rock.position = SCNVector3(wx, h, wz)
            rock.eulerAngles = SCNVector3(0, rng.nextFloat() * Float.pi * 2, 0)
            container.addChildNode(rock)
        }

        // Dead trees
        for _ in 0..<25 {
            let wx = rng.nextFloat() * totalSize - half
            let wz = rng.nextFloat() * totalSize - half
            if !isNearOasis(wx, wz) {
                let h = height(atWorldX: wx, worldZ: wz)
                let tree = AssetLoader.loadProp("prop_dead_tree")
                tree.position = SCNVector3(wx, h, wz)
                tree.eulerAngles = SCNVector3(0, rng.nextFloat() * Float.pi * 2, 0)
                container.addChildNode(tree)
            }
        }

        // Sand dunes (larger terrain features)
        for _ in 0..<30 {
            let wx = rng.nextFloat() * totalSize - half
            let wz = rng.nextFloat() * totalSize - half
            let h = height(atWorldX: wx, worldZ: wz)
            let dune = AssetLoader.loadProp("prop_sand_dune")
            let s = 0.7 + rng.nextFloat() * 0.8
            dune.scale = SCNVector3(s, s * 0.6, s)
            dune.position = SCNVector3(wx, h, wz)
            dune.eulerAngles = SCNVector3(0, rng.nextFloat() * Float.pi * 2, 0)
            container.addChildNode(dune)
        }

        // Tumbleweeds with roll animation
        for _ in 0..<15 {
            let wx = rng.nextFloat() * totalSize - half
            let wz = rng.nextFloat() * totalSize - half
            let h = height(atWorldX: wx, worldZ: wz)
            let weed = AssetLoader.loadProp("prop_tumbleweed")
            weed.position = SCNVector3(wx, h + 0.1, wz)
            // Play the roll animation, strip translation so it stays in place
            weed.enumerateHierarchy { node, _ in
                for key in node.animationKeys { node.animationPlayer(forKey: key)?.play() }
            }
            container.addChildNode(weed)
        }

        return container
    }

    // MARK: - Sand material (still used by terrain)

    private func sandMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.87, green: 0.78, blue: 0.57, alpha: 1)
        mat.specular.contents = UIColor.black
        mat.lightingModel = .lambert
        return mat
    }
}

// MARK: - Seeded Random

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextFloat() -> Float {
        Float(next() & 0xFFFFFF) / Float(0xFFFFFF)
    }
}
