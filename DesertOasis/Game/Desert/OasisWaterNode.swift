import SceneKit
import UIKit

/// Interactive oasis pool: height-field wave sim, footstep ripples, entry splash.
final class OasisWaterNode: SCNNode {

    let radius: Float

    private let gridSize: Int
    private let cellSize: Float
    private var heights: [Float]
    private var velocities: [Float]

    private let surfaceNode = SCNNode()
    private let surfaceMaterial = SCNMaterial()
    private var splashTemplate: SCNParticleSystem!

    private var time: Float = 0
    private var footstepTimer: Float = 0
    private var wasPlayerInside = false

    // MARK: - Init

    init(radius: Float, resolution: Int = 30) {
        self.radius = radius
        self.gridSize = resolution
        self.cellSize = (radius * 2) / Float(max(resolution - 1, 1))
        let count = resolution * resolution
        self.heights = [Float](repeating: 0, count: count)
        self.velocities = [Float](repeating: 0, count: count)
        super.init()
        name = "oasis_water"
        position = SCNVector3(0, 0.1, 0)
        buildDepthDisc()
        buildSurfaceMaterial()
        addChildNode(surfaceNode)
        rebuildMesh()
        splashTemplate = makeSplashSystem()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Public

    func contains(worldPosition: SCNVector3) -> Bool {
        let local = convertPosition(worldPosition, from: nil)
        return local.x * local.x + local.z * local.z <= radius * radius
    }

    /// Per-frame sim. Pass the player world position and horizontal speed (m/s).
    /// Returns `true` the frame the player first steps into the water.
    @discardableResult
    func update(deltaTime: Float, playerWorldPosition: SCNVector3, playerSpeed: Float) -> Bool {
        let dt = max(0, min(deltaTime, 1.0 / 20.0))
        time += dt
        footstepTimer = max(0, footstepTimer - dt)

        let local = convertPosition(playerWorldPosition, from: nil)
        let distSq = local.x * local.x + local.z * local.z
        let inside = distSq <= radius * radius
        var justEntered = false

        if inside {
            if !wasPlayerInside {
                justEntered = true
                // Entry splash — push water down, spray up
                disturb(localX: local.x, localZ: local.z, amount: -0.12, radius: 1.4)
                emitSplash(at: SCNVector3(local.x, 0.05, local.z), intensity: 1.2)
            } else if playerSpeed > 0.4, footstepTimer <= 0 {
                let force = min(playerSpeed, 6) * 0.018
                disturb(localX: local.x, localZ: local.z, amount: -force, radius: 0.85)
                if playerSpeed > 2.2 {
                    emitSplash(at: SCNVector3(local.x, 0.04, local.z), intensity: playerSpeed * 0.12)
                }
                footstepTimer = max(0.12, 0.45 - playerSpeed * 0.04)
            }
        }
        wasPlayerInside = inside

        addAmbientWaves(dt)
        simulate(dt)
        rebuildMesh()
        return justEntered
    }

    // MARK: - Visuals

    private func buildDepthDisc() {
        let geo = SCNCylinder(radius: CGFloat(radius * 0.98), height: 0.05)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.04, green: 0.18, blue: 0.28, alpha: 1)
        mat.lightingModel = .constant
        geo.firstMaterial = mat
        let depth = SCNNode(geometry: geo)
        depth.position = SCNVector3(0, -0.04, 0)
        addChildNode(depth)
    }

    private func buildSurfaceMaterial() {
        surfaceMaterial.diffuse.contents = UIColor(red: 0.16, green: 0.52, blue: 0.66, alpha: 1)
        surfaceMaterial.specular.contents = UIColor(white: 1, alpha: 0.95)
        surfaceMaterial.shininess = 1.0
        surfaceMaterial.transparency = 0.32
        surfaceMaterial.transparencyMode = .dualLayer
        surfaceMaterial.lightingModel = .blinn
        surfaceMaterial.isDoubleSided = true
        surfaceMaterial.writesToDepthBuffer = true
    }

    private func makeSplashSystem() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.particleSize = 0.06
        p.particleSizeVariation = 0.04
        p.particleLifeSpan = 0.55
        p.particleLifeSpanVariation = 0.2
        p.particleVelocity = 1.8
        p.particleVelocityVariation = 0.8
        p.spreadingAngle = 70
        p.emissionDuration = 0.1
        p.birthRate = 0
        p.loops = false
        p.particleColor = UIColor(red: 0.75, green: 0.92, blue: 1.0, alpha: 0.85)
        p.particleColorVariation = SCNVector4(0.05, 0.05, 0.05, 0.15)
        p.blendMode = .additive
        p.isAffectedByGravity = true
        p.acceleration = SCNVector3(0, -6, 0)
        p.emitterShape = SCNSphere(radius: 0.15)
        p.birthDirection = .random
        return p
    }

    private func emitSplash(at localPosition: SCNVector3, intensity: Float) {
        let node = SCNNode()
        node.position = localPosition
        let system = splashTemplate.copy() as! SCNParticleSystem
        system.birthRate = CGFloat(max(20, min(140, 90 * intensity)))
        system.particleVelocity = CGFloat(1.2 + intensity * 1.4)
        system.emissionDuration = 0.12
        system.loops = false
        node.addParticleSystem(system)
        addChildNode(node)
        node.runAction(.sequence([
            .wait(duration: 1.0),
            .removeFromParentNode()
        ]))
    }

    // MARK: - Simulation

    private func disturb(localX: Float, localZ: Float, amount: Float, radius r: Float) {
        let n = gridSize
        let half = Float(n - 1) * 0.5
        let r2 = r * r
        for z in 0..<n {
            for x in 0..<n {
                let lx = (Float(x) - half) * cellSize
                let lz = (Float(z) - half) * cellSize
                let dx = lx - localX
                let dz = lz - localZ
                let d2 = dx * dx + dz * dz
                guard d2 < r2 else { continue }
                let d = sqrt(d2)
                let w = 0.5 * (1 + cos(Float.pi * d / r))
                heights[z * n + x] += amount * w
            }
        }
    }

    private func addAmbientWaves(_ dt: Float) {
        // Soft wind ripples along the shore so the surface never goes fully still
        let n = gridSize
        let half = Float(n - 1) * 0.5
        let wind = 0.0018 * dt * 60
        for _ in 0..<2 {
            let angle = time * 0.7 + Float.random(in: 0...(2 * .pi))
            let dist = radius * (0.55 + Float.random(in: 0...0.35))
            let lx = cos(angle) * dist
            let lz = sin(angle) * dist
            let gx = Int((lx / cellSize) + half)
            let gz = Int((lz / cellSize) + half)
            guard gx > 1, gx < n - 2, gz > 1, gz < n - 2 else { continue }
            heights[gz * n + gx] += (Float.random(in: -1...1)) * wind
        }
        // Gentle global undulation
        let undulation = sin(time * 1.3) * 0.0004
        for z in 1..<(n - 1) {
            for x in 1..<(n - 1) {
                let lx = (Float(x) - half) * cellSize
                let lz = (Float(z) - half) * cellSize
                if lx * lx + lz * lz > radius * radius { continue }
                heights[z * n + x] += undulation * sin(lx * 0.8 + time) * cos(lz * 0.6 + time * 0.9)
            }
        }
    }

    private func simulate(_ dt: Float) {
        let n = gridSize
        let half = Float(n - 1) * 0.5
        let tension: Float = 32
        let damping: Float = pow(0.985, dt * 60)
        let steps = min(3, max(1, Int((dt * 60).rounded(.up))))
        let stepDt = dt / Float(steps)

        for _ in 0..<steps {
            for z in 1..<(n - 1) {
                for x in 1..<(n - 1) {
                    let i = z * n + x
                    let lx = (Float(x) - half) * cellSize
                    let lz = (Float(z) - half) * cellSize
                    if lx * lx + lz * lz > radius * radius {
                        heights[i] = 0
                        velocities[i] = 0
                        continue
                    }
                    let neighbors = heights[i - 1] + heights[i + 1] + heights[i - n] + heights[i + n]
                    let force = (neighbors * 0.25 - heights[i]) * tension
                    velocities[i] = (velocities[i] + force * stepDt) * damping
                }
            }
            for z in 1..<(n - 1) {
                for x in 1..<(n - 1) {
                    let i = z * n + x
                    heights[i] = max(-0.4, min(0.4, heights[i] + velocities[i] * stepDt))
                }
            }
            // Pin the rim so waves die at the shore
            for z in 0..<n {
                for x in 0..<n {
                    if z == 0 || x == 0 || z == n - 1 || x == n - 1 {
                        let i = z * n + x
                        heights[i] = 0
                        velocities[i] = 0
                    }
                }
            }
        }
    }

    // MARK: - Mesh

    private func rebuildMesh() {
        let n = gridSize
        let half = Float(n - 1) * 0.5
        let r2 = radius * radius

        var vertices = [SCNVector3](repeating: .init(0, 0, 0), count: n * n)
        var normals = [SCNVector3](repeating: .init(0, 1, 0), count: n * n)
        var indices = [Int32]()
        indices.reserveCapacity((n - 1) * (n - 1) * 6)

        for z in 0..<n {
            for x in 0..<n {
                let lx = (Float(x) - half) * cellSize
                let lz = (Float(z) - half) * cellSize
                let h = heights[z * n + x]
                // Slight bowl so the center reads as deeper
                let bowl = -0.05 * max(0, 1 - (lx * lx + lz * lz) / max(r2, 0.001))
                vertices[z * n + x] = SCNVector3(lx, h + bowl, lz)
            }
        }

        for z in 0..<n {
            for x in 0..<n {
                let hC = vertices[z * n + x].y
                let hL = x > 0 ? vertices[z * n + x - 1].y : hC
                let hR = x < n - 1 ? vertices[z * n + x + 1].y : hC
                let hD = z > 0 ? vertices[(z - 1) * n + x].y : hC
                let hU = z < n - 1 ? vertices[(z + 1) * n + x].y : hC
                let nx = (hL - hR) / (2 * cellSize)
                let nz = (hD - hU) / (2 * cellSize)
                let len = sqrt(nx * nx + 1 + nz * nz)
                normals[z * n + x] = SCNVector3(nx / len, 1 / len, nz / len)
            }
        }

        for z in 0..<(n - 1) {
            for x in 0..<(n - 1) {
                let i00 = z * n + x
                let i10 = z * n + x + 1
                let i01 = (z + 1) * n + x
                let i11 = (z + 1) * n + x + 1
                // Keep faces whose center lies inside the pool
                let cx = (vertices[i00].x + vertices[i11].x) * 0.5
                let cz = (vertices[i00].z + vertices[i11].z) * 0.5
                guard cx * cx + cz * cz <= r2 else { continue }
                let a = Int32(i00), b = Int32(i01), c = Int32(i11), d = Int32(i10)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        let vSource = SCNGeometrySource(vertices: vertices)
        let nSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vSource, nSource], elements: [element])
        geo.firstMaterial = surfaceMaterial
        surfaceNode.geometry = geo
    }
}
