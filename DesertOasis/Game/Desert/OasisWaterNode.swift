import SceneKit
import UIKit
import Accelerate
import Metal

/// Voxel-aligned interactive water body with an opaque depth plug.
/// Footprint matches carved water blocks on a single flat water plane.
final class OasisWaterNode: SCNNode {

    let radius: Float

    private let gridSize: Int
    private let cellSize: Float
    private let centerBlockX: Int
    private let centerBlockZ: Int
    private let oasisWorldX: Float
    private let oasisWorldZ: Float

    private var heights:    ContiguousArray<Float>
    private var velocities: ContiguousArray<Float>
    private var maskF:      ContiguousArray<Float>
    private var cellX:      ContiguousArray<Float>
    private var cellZ:      ContiguousArray<Float>
    private var lapBuf:     ContiguousArray<Float>

    private let surfaceNode = SCNNode()
    private let volumeNode = SCNNode()
    private let remnantNode = SCNNode()
    private let surfaceMaterial = SCNMaterial()
    private let volumeMaterial = SCNMaterial()
    private var splashTemplate: SCNParticleSystem!
    private var isDepleted = false
    /// How many buckets this pool can hold when full (1…3 from radius).
    let bucketCapacity: Int
    /// Buckets still available to collect.
    private(set) var remainingBuckets: Int
    var isExhausted: Bool { remainingBuckets <= 0 }

    private let mudMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 0.38, green: 0.28, blue: 0.18, alpha: 1)
        m.lightingModel = .lambert
        m.isDoubleSided = true
        m.writesToDepthBuffer = true
        return m
    }()

    private var time: Float = 0
    private var footstepTimer: Float = 0
    private var wasPlayerInside = false

    private var vertexBuffer: MTLBuffer?
    private var normalBuffer: MTLBuffer?
    private var cellIndices: [Int] = []
    private var quadCount = 0
    private var geometryReady = false

    // MARK: – Init

    init(radius: Float,
         oasisWorldX: Float,
         oasisWorldZ: Float) {
        self.radius = radius
        self.oasisWorldX = oasisWorldX
        self.oasisWorldZ = oasisWorldZ
        self.bucketCapacity = Self.bucketCapacity(forRadius: radius)
        self.remainingBuckets = self.bucketCapacity
        self.cellSize = VoxelMetrics.blockSize
        let bs = VoxelMetrics.blockSize
        self.centerBlockX = Int(floor(oasisWorldX / bs))
        self.centerBlockZ = Int(floor(oasisWorldZ / bs))
        let rBlocks = Int(ceil(radius / bs))
        self.gridSize = rBlocks * 2 + 3
        let count = gridSize * gridSize

        heights = ContiguousArray(repeating: 0, count: count)
        velocities = ContiguousArray(repeating: 0, count: count)
        maskF = ContiguousArray(repeating: 0, count: count)
        cellX = ContiguousArray(repeating: 0, count: count)
        cellZ = ContiguousArray(repeating: 0, count: count)
        lapBuf = ContiguousArray(repeating: 0, count: count)

        super.init()
        name = "oasis_water"
        // Sit just above the carved water-block tops.
        position = SCNVector3(0, 0.02, 0)

        buildCellPositionsAndMask(rBlocks: rBlocks)
        buildSurfaceMaterial()
        buildVolumeMaterial()
        buildVolume()
        buildRemnantPuddles()
        addChildNode(volumeNode)
        addChildNode(surfaceNode)
        addChildNode(remnantNode)
        remnantNode.isHidden = true
        buildStaticMesh()
        splashTemplate = makeSplashSystem()
    }

    convenience init(radius: Float) {
        self.init(radius: radius, oasisWorldX: 0, oasisWorldZ: 0)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: – Public

    func contains(worldPosition p: SCNVector3) -> Bool {
        guard let i = cellIndex(worldPosition: p) else { return false }
        return maskF[i] > 0.5
    }

    func isNear(worldPosition p: SCNVector3, margin: Float = 1.75) -> Bool {
        let l = convertPosition(p, from: nil)
        var best = Float.greatestFiniteMagnitude
        for i in cellIndices {
            let dx = l.x - cellX[i]
            let dz = l.z - cellZ[i]
            best = min(best, dx * dx + dz * dz)
        }
        let reach = margin + cellSize * 0.55
        return best <= reach * reach
    }

    /// Small pools hold 1 bucket; medium 2; large 3.
    static func bucketCapacity(forRadius radius: Float) -> Int {
        if radius < 3.0 { return 1 }
        if radius < 3.8 { return 2 }
        return 3
    }

    /// Draw up to `count` buckets. Returns how many were actually taken.
    @discardableResult
    func takeBuckets(_ count: Int) -> Int {
        let taken = max(0, min(count, remainingBuckets))
        remainingBuckets -= taken
        if remainingBuckets <= 0 {
            setDepleted(true)
        }
        return taken
    }

    func refillBuckets() {
        remainingBuckets = bucketCapacity
        setDepleted(false)
    }

    func setDepleted(_ depleted: Bool) {
        isDepleted = depleted
        surfaceNode.isHidden = depleted
        volumeNode.isHidden = false  // always visible; material swaps to mud when dry
        volumeNode.geometry?.firstMaterial = depleted ? mudMaterial : volumeMaterial
        remnantNode.isHidden = true  // volume covers the dried bed
        if !depleted {
            let n = vDSP_Length(gridSize * gridSize)
            heights.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                vDSP_vclr(base, 1, n)
            }
            velocities.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                vDSP_vclr(base, 1, n)
            }
        }
    }

    @discardableResult
    func update(deltaTime: Float,
                playerWorldPosition: SCNVector3,
                playerSpeed: Float) -> Bool {
        let dt = max(0, min(deltaTime, 1.0 / 20.0))
        time += dt
        footstepTimer = max(0, footstepTimer - dt)

        let local = convertPosition(playerWorldPosition, from: nil)
        let inside = contains(worldPosition: playerWorldPosition)
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
                    emitSplash(at: SCNVector3(local.x, 0.04, local.z), intensity: playerSpeed * 0.12)
                }
                footstepTimer = max(0.12, 0.45 - playerSpeed * 0.04)
            }
        }
        wasPlayerInside = inside

        if !isDepleted {
            addAmbientWaves(dt)
            simulate(dt)
            updateMeshHeights()
        }
        return justEntered
    }

    // MARK: – Footprint

    private func buildCellPositionsAndMask(rBlocks: Int) {
        let n = gridSize
        let bs = cellSize
        let pad = rBlocks + 1
        // Match carveOasis: any block whose center is within pool radius is water.
        for gz in 0..<n {
            for gx in 0..<n {
                let i = gz * n + gx
                let dx = gx - pad
                let dz = gz - pad
                let wx = (Float(centerBlockX + dx) + 0.5) * bs
                let wz = (Float(centerBlockZ + dz) + 0.5) * bs
                cellX[i] = wx - oasisWorldX
                cellZ[i] = wz - oasisWorldZ

                let dist = sqrt(Float(dx * dx + dz * dz)) * bs
                let onBorder = gx == 0 || gx == n - 1 || gz == 0 || gz == n - 1
                if onBorder || dist > radius {
                    maskF[i] = 0
                } else {
                    maskF[i] = 1
                }
            }
        }
    }

    private func cellIndex(worldPosition p: SCNVector3) -> Int? {
        let n = gridSize
        let pad = (n - 1) / 2
        let bx = Int(floor(p.x / cellSize))
        let bz = Int(floor(p.z / cellSize))
        let gx = (bx - centerBlockX) + pad
        let gz = (bz - centerBlockZ) + pad
        guard gx >= 0, gx < n, gz >= 0, gz < n else { return nil }
        return gz * n + gx
    }

    // MARK: – Depth volume

    private func buildVolumeMaterial() {
        // Opaque deep-water fill — plugs the hole left by skipping water in the terrain mesh.
        volumeMaterial.diffuse.contents = UIColor(red: 0.08, green: 0.28, blue: 0.46, alpha: 1)
        volumeMaterial.lightingModel = .lambert
        volumeMaterial.isDoubleSided = true
        volumeMaterial.writesToDepthBuffer = true
    }

    private func buildVolume() {
        let n = gridSize
        let hs = cellSize * 0.5
        // Full block depth so looking into the pool never shows void under the surface.
        let depth: Float = cellSize * 1.05

        var vVerts: [SCNVector3] = []
        var vNorms: [SCNVector3] = []
        var vIdx: [Int32] = []

        func addQuad(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3, _ d: SCNVector3,
                     normal: SCNVector3) {
            let base = Int32(vVerts.count)
            vVerts.append(contentsOf: [a, b, c, d])
            vNorms.append(contentsOf: [normal, normal, normal, normal])
            vIdx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        for z in 0..<n {
            for x in 0..<n {
                let i = z * n + x
                guard maskF[i] > 0.5 else { continue }
                let lx = cellX[i], lz = cellZ[i]
                let topY: Float = 0
                let botY = topY - depth

                addQuad(
                    SCNVector3(lx - hs, botY, lz - hs),
                    SCNVector3(lx - hs, botY, lz + hs),
                    SCNVector3(lx + hs, botY, lz + hs),
                    SCNVector3(lx + hs, botY, lz - hs),
                    normal: SCNVector3(0, 1, 0)
                )

                let neighbors: [(Int, Int, SCNVector3, Float, Float, Float, Float)] = [
                    (-1, 0, SCNVector3(-1, 0, 0), lx - hs, lz - hs, lx - hs, lz + hs),
                    ( 1, 0, SCNVector3( 1, 0, 0), lx + hs, lz + hs, lx + hs, lz - hs),
                    ( 0,-1, SCNVector3( 0, 0,-1), lx + hs, lz - hs, lx - hs, lz - hs),
                    ( 0, 1, SCNVector3( 0, 0, 1), lx - hs, lz + hs, lx + hs, lz + hs),
                ]
                for nb in neighbors {
                    let nx = x + nb.0, nz = z + nb.1
                    let missing: Bool
                    if nx < 0 || nx >= n || nz < 0 || nz >= n {
                        missing = true
                    } else {
                        missing = maskF[nz * n + nx] < 0.5
                    }
                    guard missing else { continue }
                    addQuad(
                        SCNVector3(nb.3, botY, nb.4),
                        SCNVector3(nb.5, botY, nb.6),
                        SCNVector3(nb.5, topY, nb.6),
                        SCNVector3(nb.3, topY, nb.4),
                        normal: nb.2
                    )
                }
            }
        }

        guard !vIdx.isEmpty else { return }
        let geo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vVerts), SCNGeometrySource(normals: vNorms)],
            elements: [SCNGeometryElement(indices: vIdx, primitiveType: .triangles)]
        )
        geo.firstMaterial = volumeMaterial
        volumeNode.geometry = geo
        volumeNode.renderingOrder = -1
    }

    private func buildRemnantPuddles() {
        let n = gridSize
        let hs = cellSize * 0.48
        var mudVerts: [SCNVector3] = []
        var mudIdx: [Int32] = []
        for z in 0..<n {
            for x in 0..<n {
                let i = z * n + x
                guard maskF[i] > 0.5 else { continue }
                let lx = cellX[i], lz = cellZ[i]
                let y: Float = -0.04
                let base = Int32(mudVerts.count)
                mudVerts.append(SCNVector3(lx - hs, y, lz - hs))
                mudVerts.append(SCNVector3(lx - hs, y, lz + hs))
                mudVerts.append(SCNVector3(lx + hs, y, lz + hs))
                mudVerts.append(SCNVector3(lx + hs, y, lz - hs))
                mudIdx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }
        guard !mudIdx.isEmpty else { return }
        let up = SCNVector3(0, 1, 0)
        let norms = Array(repeating: up, count: mudVerts.count)
        let geo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: mudVerts), SCNGeometrySource(normals: norms)],
            elements: [SCNGeometryElement(indices: mudIdx, primitiveType: .triangles)]
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.42, green: 0.32, blue: 0.22, alpha: 1)
        mat.lightingModel = .lambert
        geo.firstMaterial = mat
        remnantNode.addChildNode(SCNNode(geometry: geo))
    }

    private func buildSurfaceMaterial() {
        surfaceMaterial.diffuse.contents = UIColor(red: 0.16, green: 0.52, blue: 0.72, alpha: 1)
        surfaceMaterial.specular.contents = UIColor(white: 1, alpha: 0.95)
        surfaceMaterial.shininess = 1.0
        surfaceMaterial.transparency = 0.28
        surfaceMaterial.transparencyMode = .dualLayer
        surfaceMaterial.lightingModel = .blinn
        surfaceMaterial.isDoubleSided = false
        surfaceMaterial.writesToDepthBuffer = true
        surfaceMaterial.shaderModifiers = [.surface: MetalMaterialShaders.waterSurface]
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

    private func emitSplash(at local: SCNVector3, intensity: Float) {
        let node = SCNNode()
        node.position = local
        guard let system = splashTemplate?.copy() as? SCNParticleSystem else { return }
        system.birthRate = CGFloat(max(20, min(140, 90 * intensity)))
        system.particleVelocity = CGFloat(1.2 + intensity * 1.4)
        system.emissionDuration = 0.12
        system.loops = false
        node.addParticleSystem(system)
        addChildNode(node)
        node.runAction(.sequence([.wait(duration: 1.0), .removeFromParentNode()]))
    }

    // MARK: – Simulation

    private func disturb(lx: Float, lz: Float, amount: Float, r: Float) {
        let N = gridSize * gridSize
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

    private func addAmbientWaves(_ dt: Float) {
        let ws = Float(0.0018 * dt * 60)
        for _ in 0..<2 {
            guard !cellIndices.isEmpty else { break }
            let pick = cellIndices[Int.random(in: 0..<cellIndices.count)]
            heights[pick] += Float.random(in: -1...1) * ws
        }
        let undulation = sin(time * 1.3) * 0.0004
        for i in cellIndices {
            heights[i] += undulation * sin(cellX[i] * 0.8 + time) * cos(cellZ[i] * 0.6 + time * 0.9)
        }
    }

    private func simulate(_ dt: Float) {
        let n = gridSize
        let N = vDSP_Length(n * n)
        let stepCount = min(3, max(1, Int((dt * 60).rounded(.up))))
        let stepDt = dt / Float(stepCount)

        var lapScale: Float = 28.0 * stepDt * 0.25
        var damping: Float = pow(0.985, dt * 60)
        var sdt: Float = stepDt
        var lo: Float = -0.35
        var hi: Float = 0.35

        heights.withUnsafeMutableBufferPointer { hBuf in
            velocities.withUnsafeMutableBufferPointer { vBuf in
                maskF.withUnsafeBufferPointer { mBuf in
                    lapBuf.withUnsafeMutableBufferPointer { lBuf in
                        guard let h = hBuf.baseAddress,
                              let v = vBuf.baseAddress,
                              let m = mBuf.baseAddress,
                              let l = lBuf.baseAddress else { return }
                        for _ in 0..<stepCount {
                            vDSP_vclr(l, 1, N)
                            for z in 1..<(n - 1) {
                                let rs = z * n + 1
                                let cnt = vDSP_Length(n - 2)
                                vDSP_vadd(h + rs - 1, 1, h + rs + 1, 1, l + rs, 1, cnt)
                                vDSP_vadd(l + rs, 1, h + rs - n, 1, l + rs, 1, cnt)
                                vDSP_vadd(l + rs, 1, h + rs + n, 1, l + rs, 1, cnt)
                                var neg4: Float = -4
                                vDSP_vsma(h + rs, 1, &neg4, l + rs, 1, l + rs, 1, cnt)
                            }
                            vDSP_vmul(l, 1, m, 1, l, 1, N)
                            vDSP_vsmul(v, 1, &damping, v, 1, N)
                            vDSP_vsma(l, 1, &lapScale, v, 1, v, 1, N)
                            vDSP_vsma(v, 1, &sdt, h, 1, h, 1, N)
                            vDSP_vclip(h, 1, &lo, &hi, h, 1, N)
                            vDSP_vmul(h, 1, m, 1, h, 1, N)
                            vDSP_vmul(v, 1, m, 1, v, 1, N)
                        }
                    }
                }
            }
        }
    }

    // MARK: – Surface mesh

    private func buildStaticMesh() {
        let n = gridSize
        cellIndices.removeAll(keepingCapacity: true)
        for z in 0..<n {
            for x in 0..<n {
                let i = z * n + x
                if maskF[i] > 0.5 { cellIndices.append(i) }
            }
        }
        quadCount = cellIndices.count
        guard quadCount > 0, let device = MTLCreateSystemDefaultDevice() else {
            surfaceNode.geometry = nil
            return
        }

        let vertexCount = quadCount * 4
        let indexCount = quadCount * 6
        guard let vBuf = device.makeBuffer(length: vertexCount * MemoryLayout<SIMD3<Float>>.stride,
                                           options: .storageModeShared),
              let nBuf = device.makeBuffer(length: vertexCount * MemoryLayout<SIMD3<Float>>.stride,
                                           options: .storageModeShared),
              let iBuf = device.makeBuffer(length: indexCount * MemoryLayout<Int32>.stride,
                                           options: .storageModeShared)
        else { return }

        vertexBuffer = vBuf
        normalBuffer = nBuf
        let ip = iBuf.contents().bindMemory(to: Int32.self, capacity: indexCount)
        for q in 0..<quadCount {
            let base = Int32(q * 4)
            let o = q * 6
            ip[o] = base; ip[o + 1] = base + 1; ip[o + 2] = base + 2
            ip[o + 3] = base; ip[o + 4] = base + 2; ip[o + 5] = base + 3
        }

        updateMeshHeights()

        let vSrc = SCNGeometrySource(
            buffer: vBuf, vertexFormat: .float3, semantic: .vertex,
            vertexCount: vertexCount, dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let nSrc = SCNGeometrySource(
            buffer: nBuf, vertexFormat: .float3, semantic: .normal,
            vertexCount: vertexCount, dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let elem = SCNGeometryElement(
            data: Data(bytes: iBuf.contents(), count: indexCount * 4),
            primitiveType: .triangles, primitiveCount: quadCount * 2, bytesPerIndex: 4
        )
        let geo = SCNGeometry(sources: [vSrc, nSrc], elements: [elem])
        geo.firstMaterial = surfaceMaterial
        surfaceNode.geometry = geo
        geometryReady = true
    }

    private func updateMeshHeights() {
        guard geometryReady,
              let vBuf = vertexBuffer,
              let nBuf = normalBuffer,
              quadCount > 0
        else { return }

        let n = gridSize
        let cs = cellSize
        let hs = cs * 0.5
        let vp = vBuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: quadCount * 4)
        let np = nBuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: quadCount * 4)

        for q in 0..<quadCount {
            let i = cellIndices[q]
            let gx = i % n
            let gz = i / n
            let lx = cellX[i]
            let lz = cellZ[i]
            let y = heights[i]

            let hL = (gx > 0) ? heights[gz * n + gx - 1] : y
            let hR = (gx < n - 1) ? heights[gz * n + gx + 1] : y
            let hD = (gz > 0) ? heights[(gz - 1) * n + gx] : y
            let hU = (gz < n - 1) ? heights[(gz + 1) * n + gx] : y
            let nx = (hL - hR) / (2 * cs)
            let nz = (hD - hU) / (2 * cs)
            let nl = sqrt(nx * nx + 1 + nz * nz)
            let normal = SIMD3<Float>(nx / nl, 1 / nl, nz / nl)

            let base = q * 4
            vp[base]     = SIMD3(lx - hs, y, lz - hs)
            vp[base + 1] = SIMD3(lx - hs, y, lz + hs)
            vp[base + 2] = SIMD3(lx + hs, y, lz + hs)
            vp[base + 3] = SIMD3(lx + hs, y, lz - hs)
            np[base] = normal; np[base + 1] = normal
            np[base + 2] = normal; np[base + 3] = normal
        }
    }
}
