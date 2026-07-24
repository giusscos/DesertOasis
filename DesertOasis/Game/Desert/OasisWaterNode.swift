import SceneKit
import UIKit
import Accelerate

/// Voxel-aligned interactive water body.
/// Each simulation cell is one voxel block column (cellSize = VoxelMetrics.blockSize = 0.5 m).
/// The wave equation runs entirely via Accelerate vDSP on ContiguousArrays.
final class OasisWaterNode: SCNNode {

    let radius: Float

    private let gridSize: Int
    private let cellSize: Float
    private let halfGrid: Float         // (n-1)/2 * cellSize

    // Flat n×n simulation state (row-major: index = z*n + x)
    private var heights:    ContiguousArray<Float>
    private var velocities: ContiguousArray<Float>
    // 1.0 inside pool circle (inner cells only), 0.0 elsewhere — used for vDSP mask ops
    private var maskF:      ContiguousArray<Float>
    // Pre-computed local-space centre of each cell (avoids recomputing in hot paths)
    private var cellX:      ContiguousArray<Float>
    private var cellZ:      ContiguousArray<Float>
    // Reused Laplacian scratch buffer — allocated once to avoid per-frame heap pressure
    private var lapBuf:     ContiguousArray<Float>

    private let surfaceNode    = SCNNode()
    private let surfaceMaterial = SCNMaterial()
    private var splashTemplate: SCNParticleSystem!
    private var depthDisc: SCNNode!
    private var isDepleted = false

    private var time:           Float = 0
    private var footstepTimer:  Float = 0
    private var wasPlayerInside       = false

    // MARK: – Init

    init(radius: Float) {
        self.radius   = radius
        self.cellSize = VoxelMetrics.blockSize          // 0.5 m = 1 voxel block per cell
        let cells     = Int((radius * 2.0 / cellSize).rounded(.up)) + 2
        self.gridSize = cells
        self.halfGrid = Float(cells - 1) * 0.5 * cellSize
        let count     = cells * cells

        heights    = ContiguousArray(repeating: 0, count: count)
        velocities = ContiguousArray(repeating: 0, count: count)
        maskF      = ContiguousArray(repeating: 0, count: count)
        cellX      = ContiguousArray(repeating: 0, count: count)
        cellZ      = ContiguousArray(repeating: 0, count: count)
        lapBuf     = ContiguousArray(repeating: 0, count: count)

        super.init()
        name     = "oasis_water"
        position = SCNVector3(0, 0.05, 0)

        buildCellPositions()
        buildMask()
        buildDepthDisc()
        buildSurfaceMaterial()
        addChildNode(surfaceNode)
        rebuildMesh()
        splashTemplate = makeSplashSystem()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: – Public interface

    func contains(worldPosition p: SCNVector3) -> Bool {
        let l = convertPosition(p, from: nil)
        return l.x * l.x + l.z * l.z <= radius * radius
    }

    func setDepleted(_ depleted: Bool) {
        isDepleted = depleted
        surfaceNode.isHidden = depleted
        depthDisc.geometry?.firstMaterial?.diffuse.contents = depleted
            ? UIColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1)
            : UIColor(red: 0.04, green: 0.18, blue: 0.28, alpha: 1)
        if !depleted {
            let n = vDSP_Length(gridSize * gridSize)
            heights.withUnsafeMutableBufferPointer    { vDSP_vclr($0.baseAddress!, 1, n) }
            velocities.withUnsafeMutableBufferPointer { vDSP_vclr($0.baseAddress!, 1, n) }
        }
    }

    /// Call every frame. Returns `true` the frame the player first steps into the water.
    @discardableResult
    func update(deltaTime: Float,
                playerWorldPosition: SCNVector3,
                playerSpeed: Float) -> Bool {
        let dt = max(0, min(deltaTime, 1.0 / 20.0))
        time         += dt
        footstepTimer = max(0, footstepTimer - dt)

        let local  = convertPosition(playerWorldPosition, from: nil)
        let distSq = local.x * local.x + local.z * local.z
        let inside = distSq <= radius * radius
        var justEntered = false

        if inside {
            if !wasPlayerInside {
                justEntered = true
                disturb(lx: local.x, lz: local.z, amount: -0.14, r: 1.6)
                emitSplash(at: SCNVector3(local.x, 0.05, local.z), intensity: 1.2)
            } else if playerSpeed > 0.4, footstepTimer <= 0 {
                let force = min(playerSpeed, 6) * 0.018
                disturb(lx: local.x, lz: local.z, amount: -force, r: 0.9)
                if playerSpeed > 2.2 {
                    emitSplash(at: SCNVector3(local.x, 0.04, local.z),
                               intensity: playerSpeed * 0.12)
                }
                footstepTimer = max(0.12, 0.45 - playerSpeed * 0.04)
            }
        }
        wasPlayerInside = inside

        if !isDepleted {
            addAmbientWaves(dt)
            simulate(dt)
            rebuildMesh()
        }
        return justEntered
    }

    // MARK: – One-time setup

    private func buildCellPositions() {
        let n = gridSize
        for z in 0..<n {
            for x in 0..<n {
                let i = z * n + x
                cellX[i] = Float(x) * cellSize - halfGrid
                cellZ[i] = Float(z) * cellSize - halfGrid
            }
        }
    }

    private func buildMask() {
        let n  = gridSize
        let r2 = radius * radius
        for z in 0..<n {
            for x in 0..<n {
                let i  = z * n + x
                let lx = cellX[i], lz = cellZ[i]
                let inCircle = lx * lx + lz * lz <= r2
                let inInner  = x > 0 && x < n-1 && z > 0 && z < n-1
                maskF[i] = (inCircle && inInner) ? 1.0 : 0.0
            }
        }
    }

    private func buildDepthDisc() {
        let geo = SCNCylinder(radius: CGFloat(radius * 0.98), height: 0.06)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.04, green: 0.18, blue: 0.28, alpha: 1)
        mat.lightingModel    = .constant
        geo.firstMaterial    = mat
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(0, -0.04, 0)
        depthDisc = node
        addChildNode(node)
    }

    private func buildSurfaceMaterial() {
        surfaceMaterial.diffuse.contents    = UIColor(red: 0.16, green: 0.52, blue: 0.72, alpha: 1)
        surfaceMaterial.specular.contents   = UIColor(white: 1, alpha: 0.95)
        surfaceMaterial.shininess           = 1.0
        surfaceMaterial.transparency        = 0.30
        surfaceMaterial.transparencyMode    = .dualLayer
        surfaceMaterial.lightingModel       = .blinn
        surfaceMaterial.isDoubleSided       = false
        surfaceMaterial.writesToDepthBuffer = true
    }

    private func makeSplashSystem() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.particleSize              = 0.06
        p.particleSizeVariation     = 0.04
        p.particleLifeSpan          = 0.55
        p.particleLifeSpanVariation = 0.2
        p.particleVelocity          = 1.8
        p.particleVelocityVariation = 0.8
        p.spreadingAngle            = 70
        p.emissionDuration          = 0.1
        p.birthRate                 = 0
        p.loops                     = false
        p.particleColor             = UIColor(red: 0.75, green: 0.92, blue: 1.0, alpha: 0.85)
        p.particleColorVariation    = SCNVector4(0.05, 0.05, 0.05, 0.15)
        p.blendMode                 = .additive
        p.isAffectedByGravity       = true
        p.acceleration              = SCNVector3(0, -6, 0)
        p.emitterShape              = SCNSphere(radius: 0.15)
        p.birthDirection            = .random
        return p
    }

    private func emitSplash(at local: SCNVector3, intensity: Float) {
        let node = SCNNode()
        node.position = local
        let system = splashTemplate.copy() as! SCNParticleSystem
        system.birthRate        = CGFloat(max(20, min(140, 90 * intensity)))
        system.particleVelocity = CGFloat(1.2 + intensity * 1.4)
        system.emissionDuration = 0.12
        system.loops            = false
        node.addParticleSystem(system)
        addChildNode(node)
        node.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
    }

    // MARK: – Simulation

    /// Cosine-weighted height disturbance centred at (lx, lz) in local space.
    private func disturb(lx: Float, lz: Float, amount: Float, r: Float) {
        let N  = gridSize * gridSize
        let r2 = r * r
        for i in 0..<N {
            guard maskF[i] > 0.5 else { continue }
            let dx = cellX[i] - lx
            let dz = cellZ[i] - lz
            let d2 = dx * dx + dz * dz
            guard d2 < r2 else { continue }
            let w = 0.5 * (1 + cos(Float.pi * sqrt(d2) / r))
            heights[i] += amount * w
        }
    }

    /// Low-level stochastic ripples so the surface never goes fully still.
    private func addAmbientWaves(_ dt: Float) {
        let n  = gridSize
        let ws = Float(0.0018 * dt * 60)
        for _ in 0..<2 {
            let angle = time * 0.7 + Float.random(in: 0...(2 * .pi))
            let dist  = radius * (0.55 + Float.random(in: 0...0.35))
            let lx    = cos(angle) * dist
            let lz    = sin(angle) * dist
            let gx    = Int(((lx + halfGrid) / cellSize).rounded())
            let gz    = Int(((lz + halfGrid) / cellSize).rounded())
            guard gx > 1, gx < n-2, gz > 1, gz < n-2 else { continue }
            heights[gz * n + gx] += Float.random(in: -1...1) * ws
        }
        let undulation = sin(time * 1.3) * 0.0004
        let N = gridSize * gridSize
        for i in 0..<N {
            guard maskF[i] > 0.5 else { continue }
            heights[i] += undulation * sin(cellX[i] * 0.8 + time) * cos(cellZ[i] * 0.6 + time * 0.9)
        }
    }

    /// Wave-equation simulation using Accelerate vDSP — zero heap allocation per frame.
    private func simulate(_ dt: Float) {
        let n         = gridSize
        let N         = vDSP_Length(n * n)
        let stepCount = min(3, max(1, Int((dt * 60).rounded(.up))))
        let stepDt    = dt / Float(stepCount)

        // tension=28; divided by 4 because lapBuf = Σ4_neighbors − 4·h (not normalised)
        var lapScale: Float = 28.0 * stepDt * 0.25
        var damping:  Float = pow(0.985, dt * 60)
        var sdt:      Float = stepDt
        var lo:       Float = -0.4
        var hi:       Float =  0.4

        heights.withUnsafeMutableBufferPointer { hBuf in
          velocities.withUnsafeMutableBufferPointer { vBuf in
            maskF.withUnsafeBufferPointer { mBuf in
              lapBuf.withUnsafeMutableBufferPointer { lBuf in
                let h = hBuf.baseAddress!
                let v = vBuf.baseAddress!
                let m = mBuf.baseAddress!
                let l = lBuf.baseAddress!

                for _ in 0..<stepCount {

                    // --- Laplacian: l[i] = h[i-1]+h[i+1]+h[i-n]+h[i+n] − 4·h[i] ---
                    vDSP_vclr(l, 1, N)
                    for z in 1..<(n-1) {
                        let rs  = z * n + 1
                        let cnt = vDSP_Length(n - 2)
                        vDSP_vadd(h + rs - 1, 1, h + rs + 1, 1, l + rs, 1, cnt)  // left + right
                        vDSP_vadd(l + rs, 1,  h + rs - n,   1, l + rs, 1, cnt)   // + up
                        vDSP_vadd(l + rs, 1,  h + rs + n,   1, l + rs, 1, cnt)   // + down
                        var neg4: Float = -4
                        vDSP_vsma(h + rs, 1, &neg4, l + rs, 1, l + rs, 1, cnt)   // − 4·center
                    }

                    // Mask laplacian to pool circle
                    vDSP_vmul(l, 1, m, 1, l, 1, N)

                    // v = v·damping + l·lapScale
                    vDSP_vsmul(v, 1, &damping,  v, 1, N)
                    vDSP_vsma (l, 1, &lapScale, v, 1, v, 1, N)

                    // h += v·stepDt
                    vDSP_vsma(v, 1, &sdt, h, 1, h, 1, N)

                    // Clamp and re-apply mask
                    vDSP_vclip(h, 1, &lo, &hi, h, 1, N)
                    vDSP_vmul(h, 1, m, 1, h, 1, N)
                    vDSP_vmul(v, 1, m, 1, v, 1, N)
                }
              }
            }
          }
        }
    }

    // MARK: – Mesh

    /// Emits one flat quad per voxel-aligned water cell — produces the blocky voxel-water look
    /// while each cell's Y height is driven by the wave simulation.
    private func rebuildMesh() {
        let n  = gridSize
        let cs = cellSize
        let hs = cs * 0.5
        let r2 = radius * radius

        var vertices: [SCNVector3] = []
        var normals:  [SCNVector3] = []
        var indices:  [Int32]      = []

        for z in 1..<(n-1) {
            for x in 1..<(n-1) {
                let i = z * n + x
                guard maskF[i] > 0.5 else { continue }

                let lx = cellX[i]
                let lz = cellZ[i]
                let h  = heights[i]

                // Slight centre-bowl so the pool reads as deeper
                let bowl = -0.04 * max(0, 1 - (lx * lx + lz * lz) / max(r2, 0.001))
                let y = h + bowl

                // Per-cell normal from height gradient
                let hL = heights[z * n + x - 1]
                let hR = heights[z * n + x + 1]
                let hD = heights[(z-1) * n + x]
                let hU = heights[(z+1) * n + x]
                let nx = (hL - hR) / (2 * cs)
                let nz = (hD - hU) / (2 * cs)
                let nl = sqrt(nx * nx + 1 + nz * nz)
                let normal = SCNVector3(nx / nl, 1 / nl, nz / nl)

                let base = Int32(vertices.count)
                vertices.append(SCNVector3(lx - hs, y, lz - hs))
                vertices.append(SCNVector3(lx - hs, y, lz + hs))
                vertices.append(SCNVector3(lx + hs, y, lz + hs))
                vertices.append(SCNVector3(lx + hs, y, lz - hs))
                normals.append(contentsOf: [normal, normal, normal, normal])
                indices.append(contentsOf: [base, base+1, base+2, base, base+2, base+3])
            }
        }

        guard !indices.isEmpty else { surfaceNode.geometry = nil; return }

        let vSrc = SCNGeometrySource(vertices: vertices)
        let nSrc = SCNGeometrySource(normals: normals)
        let elem = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo  = SCNGeometry(sources: [vSrc, nSrc], elements: [elem])
        geo.firstMaterial  = surfaceMaterial
        surfaceNode.geometry = geo
    }
}
