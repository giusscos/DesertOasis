import SceneKit
import UIKit

final class DesertScene: SCNScene, SCNPhysicsContactDelegate {

    private(set) var playerNode: PlayerNode!
    private(set) var toolRig: PlayerToolRig!
    /// Home camp (always present after build).
    private(set) var camp: CampNode!
    private(set) var camps: [CampNode] = []
    private(set) var npcs: [NPCNode] = []
    private(set) var animals: [AnimalNode] = []
    private(set) var oases: [OasisInfo] = []
    private(set) var waterBodies: [OasisWaterNode] = []
    private var voxelWorld: VoxelWorld!
    private var worldSeed: UInt64 = 0
    private var campSites: [CampSite] = []
    private var spawnedCampIDs: Set<String> = []
    private var placedOasisKeys: Set<String> = []
    private var slotCampProgress: [String: CampProgress] = [:]

    let cameraNode = SCNNode()
    let cameraArmNode = SCNNode()
    private let cameraPitchNode = SCNNode()
    private let cameraLookTarget = SCNNode()
    private var cameraPitch: Float = -0.32
    private let cameraDistance: Float = 8.2
    private let cameraMinDistance: Float = 1.15
    private let cameraRadius: Float = 0.4
    private let cameraOrbitSpeed: Float = 18
    private let cameraDistanceSpeed: Float = 14
    private var cameraWorldPosition: SCNVector3?
    private let cameraPitchMin: Float = -1.05
    private let cameraPitchMax: Float = 0.40
    private let playerCollisionRadius: Float = 0.32

    let dayNight = DayNightCycle()
    private var sunNode: SCNNode!
    private var ambientLightNode: SCNNode!
    private var skyNode: SCNNode!
    private(set) var isSleeping = false
    private var sleepCameraNode: SCNNode?

    var onNPCProximity: ((NPCNode) -> Void)?
    var onOasisReached: ((OasisInfo) -> Void)?
    var onWaterCollected: (() -> Void)?
    /// level, unlockedCompass, unlockedDetector, campId
    var onWaterDelivered: ((Float, Bool, Bool, String) -> Void)?
    var onNearBarrel: ((Bool) -> Void)?
    var onCampDrained: ((Float, String) -> Void)?
    var onWaterGivenToNPC: ((NPCNode) -> Void)?
    var onNearWater: ((Bool) -> Void)?
    var onNearBed: ((Bool) -> Void)?
    var onNearSettingsTable: ((Bool) -> Void)?
    var onOasisGrown: ((String, OasisGrowthStage, Float, Bool) -> Void)?
    var onCampDiscovered: ((CampSite) -> Void)?
    var onTimeOfDayChanged: ((Float) -> Void)?
    var onSleepFinished: (() -> Void)?

    private var playerHorizontalSpeed: Float = 0
    private var isInWater = false
    private var toolTime: Float = 0
    private var wasNearBarrel = false
    private var wasNearBed = false
    private var wasNearSettings = false
    private var deliveryCount = 0
    private var timePersistAccumulator: Float = 0

    // Oasis depletion
    private var wasNearCollectableWater = false
    private var depletedWaterBodies: Set<ObjectIdentifier> = []
    private var oasisRefillTimers: [ObjectIdentifier: Float] = [:]
    private let oasisRefillTime: Float = 90.0

    // Camp drain (evaporation — separate from NPC irrigation)
    private var campDrainAccumulator: Float = 0
    private let campDrainInterval: Float = 22.0
    private let campDrainAmount: Float = 0.004

    // Streaming
    private let streamLoadRadius = 11
    private let streamUnloadRadius = 15
    private var streamPending: [(cx: Int, cz: Int)] = []
    private let streamChunksPerFrame = 2

    /// Remote camps are heavy (lobby tents + remesh). Spawn across frames to avoid hitch/jetsam.
    private enum CampSpawnPhase {
        case prepareChunks(site: CampSite, coords: [(cx: Int, cz: Int)], index: Int)
        case buildShell(site: CampSite)
        case buildNeighbours(site: CampSite, node: CampNode)
        case finish(site: CampSite, node: CampNode)
    }
    private var campSpawnPhase: CampSpawnPhase?
    private var queuedCampSites: [CampSite] = []
    private let campPrepChunksPerFrame = 3
    private let campDiscoverRadius: Float = 52

    // Progressive world build
    private(set) var isBuildingWorld = false
    private var buildSlot: SaveSlot?
    private var buildGenerator: VoxelWorldGenerator?
    private var pendingChunkCoords: [(cx: Int, cz: Int)] = []
    private var buildChunkIndex = 0
    private let chunksPerFrame = 8

    var onBuildProgress: ((Float) -> Void)?
    var onBuildComplete: (() -> Void)?

    // MARK: - Build

    /// Streams terrain chunks outward from camp so the player can watch the desert form.
    func build(from slot: SaveSlot) {
        guard !isBuildingWorld else { return }
        isBuildingWorld = true
        buildSlot = slot
        worldSeed = slot.desertSeed
        deliveryCount = slot.waterDeliveries
        campSites = CampSiteGenerator.sites(seed: slot.desertSeed)
        slotCampProgress = Dictionary(slot.campProgress.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        dayNight.setTimeOfDay(slot.timeOfDay)

        setupLighting()
        setupSky()
        setupSandHaze()
        dayNight.attach(scene: self, sun: sunNode, ambient: ambientLightNode, sky: skyNode)

        voxelWorld = VoxelWorld(seed: slot.desertSeed)
        rootNode.addChildNode(voxelWorld.rootNode)

        buildGenerator = VoxelWorldGenerator(seed: slot.desertSeed, campSites: campSites)
        // Initial ring around home — rest streams as the player explores.
        pendingChunkCoords = voxelWorld.chunkCoordinatesFromCenter(radiusChunks: 10)
        buildChunkIndex = 0

        setupOverviewCamera()
        onBuildProgress?(0)
        scheduleNextBuildBatch()
    }

    private func scheduleNextBuildBatch() {
        DispatchQueue.main.async { [weak self] in
            self?.processBuildBatch()
        }
    }

    private func processBuildBatch() {
        guard isBuildingWorld, let generator = buildGenerator, voxelWorld != nil else { return }

        let total = pendingChunkCoords.count
        guard total > 0 else {
            finalizeBuild()
            return
        }

        let end = min(buildChunkIndex + chunksPerFrame, total)
        for i in buildChunkIndex..<end {
            let coord = pendingChunkCoords[i]
            generator.generateChunk(into: voxelWorld, cx: coord.cx, cz: coord.cz)
            voxelWorld.remeshChunk(cx: coord.cx, cz: coord.cz, animated: true)
        }
        buildChunkIndex = end

        // Terrain fill is ~0–0.92 of the progress bar; finalize fills the rest.
        let terrainProgress = Float(end) / Float(total)
        onBuildProgress?(terrainProgress * 0.92)

        if end < total {
            scheduleNextBuildBatch()
        } else {
            finalizeBuild()
        }
    }

    private func finalizeBuild() {
        guard let slot = buildSlot, let generator = buildGenerator else { return }

        let homeSites = campSites.filter(\.isHome)
        let ring1 = campSites.filter { !$0.isHome }.prefix(4)
        let initialSites = homeSites + Array(ring1)
        oases = generator.placeAndCarveOases(into: voxelWorld, nearSites: initialSites, oasisCount: 6)
        for oasis in oases {
            placedOasisKeys.insert(oasisKey(oasis))
        }
        voxelWorld.remeshDirtyChunks()
        onBuildProgress?(0.96)

        spawnCamp(site: campSites.first(where: \.isHome)!, progress: slot.progress(forCampId: "home"))
        camp = camps.first(where: { $0.site.isHome })

        waterBodies.removeAll()
        for oasis in oases {
            addWaterBody(for: oasis)
        }

        let props = VoxelPropBuilder.scatterProps(
            world: voxelWorld, oases: oases, seed: slot.desertSeed, campClearRadius: 26
        )
        rootNode.addChildNode(props)

        spawnNPCs(for: camp)
        spawnAnimals(for: camp)
        spawnWildAnimals()
        setupPlayer(slot: slot)
        tearDownOverviewCamera()
        setupCamera()
        setupPhysics()

        buildSlot = nil
        // Keep generator for streaming / remote oasis carving.
        pendingChunkCoords = []
        isBuildingWorld = false
        onBuildProgress?(1)
        onBuildComplete?()
    }

    private func oasisKey(_ oasis: OasisInfo) -> String {
        String(format: "%.0f_%.0f", oasis.position.x, oasis.position.z)
    }

    private func addWaterBody(for oasis: OasisInfo) {
        let container = SCNNode()
        container.position = SCNVector3(oasis.position.x, oasis.position.y, oasis.position.z)
        let water = OasisWaterNode(radius: oasis.radius, resolution: 18)
        container.addChildNode(water)
        rootNode.addChildNode(container)
        waterBodies.append(water)
    }

    @discardableResult
    private func spawnCamp(site: CampSite, progress: CampProgress) -> CampNode {
        let ground = voxelWorld.surfaceY(atWorldX: site.worldX, worldZ: site.worldZ)
        let node = CampNode(site: site, groundHeight: ground, world: voxelWorld)
        node.setFillLevel(progress.waterLevel)
        let stage = OasisGrowthStage(rawValue: progress.oasisStage) ?? .barren
        node.restoreOasis(stage: stage, progress: progress.oasisProgress)
        node.onIrrigated = { [weak self] level, oasisStage, oasisProg, advanced in
            guard let self else { return }
            self.onOasisGrown?(site.id, oasisStage, oasisProg, advanced)
            self.onCampDrained?(level, site.id)
        }
        rootNode.addChildNode(node)
        camps.append(node)
        spawnedCampIDs.insert(site.id)
        return node
    }

    private func setupOverviewCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 62
        camera.zNear = 0.5
        camera.zFar = 600
        cameraNode.camera = camera
        cameraNode.constraints = nil
        cameraNode.eulerAngles = SCNVector3(-0.92, 0.15, 0)
        cameraNode.position = SCNVector3(18, 110, 95)
        if cameraNode.parent == nil {
            rootNode.addChildNode(cameraNode)
        }
    }

    private func tearDownOverviewCamera() {
        cameraNode.removeFromParentNode()
        cameraNode.constraints = nil
        cameraNode.eulerAngles = SCNVector3Zero
    }

    private func groundY(x: Float, z: Float) -> Float {
        voxelWorld.surfaceY(atWorldX: x, worldZ: z)
    }

    // MARK: - Lighting

    private func setupLighting() {
        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(red: 1.0, green: 0.93, blue: 0.75, alpha: 1)
        sun.intensity = 1200
        sun.castsShadow = true
        sun.shadowRadius = 4
        sun.shadowColor = UIColor(white: 0, alpha: 0.4)
        sunNode = SCNNode()
        sunNode.name = "sun"
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi * 0.45, Float.pi * 0.25, 0)
        rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.62, green: 0.72, blue: 0.85, alpha: 1)
        ambient.intensity = 420
        ambientLightNode = SCNNode()
        ambientLightNode.name = "ambient"
        ambientLightNode.light = ambient
        rootNode.addChildNode(ambientLightNode)
    }

    // MARK: - Sky

    private func setupSky() {
        skyNode = SCNNode(geometry: SCNSphere(radius: 800))
        skyNode.name = "sky"
        let mat = SCNMaterial()
        mat.diffuse.contents = skyboxGradient()
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        skyNode.geometry?.firstMaterial = mat
        skyNode.geometry?.firstMaterial?.cullMode = .front
        rootNode.addChildNode(skyNode)
    }

    private func skyboxGradient() -> UIColor {
        UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)
    }

    /// Soft sand haze at the stream rim — hides chunk pop-in without muddying camp scale.
    private func setupSandHaze() {
        let chunkMeters = CGFloat(VoxelChunk.sizeX) * CGFloat(VoxelMetrics.blockSize)
        let loadEdge = chunkMeters * CGFloat(streamLoadRadius)
        // Clear through camp-discover range; fully opaque just past the loaded ring.
        fogStartDistance = loadEdge * 0.68
        fogEndDistance = loadEdge * 1.08

        // SceneKit fogs all geometry; a sky dome would become solid haze when looking up.
        // `background.contents` (driven by DayNightCycle) stays unfogged.
        skyNode?.isHidden = true
    }

    // MARK: - Player

    private func setupPlayer(slot: SaveSlot) {
        let gender = slot.characterGender ?? .man
        playerNode = PlayerNode(gender: gender)

        let spawnX = slot.playerPositionX
        let spawnZ = slot.playerPositionZ
        let nearOrigin = abs(spawnX) < 0.5 && abs(spawnZ) < 0.5
        let x = nearOrigin ? 1.5 : spawnX
        let z = nearOrigin ? 0.5 : spawnZ
        let groundH = groundY(x: x, z: z)
        playerNode.position = SCNVector3(x, groundH + 0.01, z)
        rootNode.addChildNode(playerNode)

        toolRig = PlayerToolRig()
        toolRig.setCarryingWater(slot.isCarryingWater)
        toolRig.setCompassUnlocked(slot.hasWaterCompass)
        toolRig.setDetectorUnlocked(slot.hasWaterDetector)
        playerNode.addChildNode(toolRig)
    }

    // MARK: - Camera

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 65
        camera.zNear = 0.2
        camera.zFar = 500
        cameraNode.camera = camera
        cameraNode.eulerAngles = SCNVector3Zero
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        cameraWorldPosition = nil
        cameraNode.constraints = nil

        // Look target rides on the yaw arm (player height), not the pitch boom
        cameraLookTarget.position = SCNVector3(0, 1.25, 0)
        if cameraLookTarget.parent == nil {
            cameraArmNode.addChildNode(cameraLookTarget)
        }

        if cameraPitchNode.parent == nil {
            cameraArmNode.addChildNode(cameraPitchNode)
        }
        if cameraNode.parent != cameraPitchNode {
            cameraPitchNode.addChildNode(cameraNode)
        }

        let lookAt = SCNLookAtConstraint(target: cameraLookTarget)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        cameraPitchNode.eulerAngles.x = cameraPitch
        if cameraArmNode.parent == nil {
            rootNode.addChildNode(cameraArmNode)
        }
        syncCameraFollow()
        resolveCameraCollision(deltaTime: 1)
    }

    private func syncCameraFollow() {
        guard let playerNode else { return }
        cameraArmNode.position = playerNode.position
    }

    /// Orbit the camera around obstacles: rotate the view ray fluidly and ride the
    /// contact silhouette instead of stopping with friction when blocked.
    private func resolveCameraCollision(deltaTime: Float) {
        let lookWorld = cameraLookTarget.convertPosition(SCNVector3Zero, to: nil)
        let desiredWorld = cameraPitchNode.convertPosition(SCNVector3(0, 0, cameraDistance), to: nil)

        let desiredVec = simd_float3(
            desiredWorld.x - lookWorld.x,
            desiredWorld.y - lookWorld.y,
            desiredWorld.z - lookWorld.z
        )
        let desiredLen = simd_length(desiredVec)
        guard desiredLen > 1e-4 else { return }
        let desiredDir = desiredVec / desiredLen

        let previous = cameraWorldPosition ?? desiredWorld
        var prevVec = simd_float3(
            previous.x - lookWorld.x,
            previous.y - lookWorld.y,
            previous.z - lookWorld.z
        )
        var prevLen = simd_length(prevVec)
        if prevLen < 1e-4 {
            prevVec = desiredVec
            prevLen = desiredLen
        }
        let prevDir = prevVec / prevLen

        let dt = max(0, deltaTime)
        let orbitBlend = 1 - exp(-cameraOrbitSpeed * dt)
        let dir = slerpCameraDir(prevDir, desiredDir, orbitBlend)

        // Clear length along this orbit ray — follows the object perimeter as you pan.
        let probeEnd = SCNVector3(
            lookWorld.x + dir.x * cameraDistance,
            lookWorld.y + dir.y * cameraDistance,
            lookWorld.z + dir.z * cameraDistance
        )
        let clearDist = clearCameraDistance(from: lookWorld, toward: probeEnd)

        let distBlend = 1 - exp(-cameraDistanceSpeed * dt)
        var dist = prevLen + (clearDist - prevLen) * distBlend
        dist = max(cameraMinDistance, min(cameraDistance, dist))

        var pos = SCNVector3(
            lookWorld.x + dir.x * dist,
            lookWorld.y + dir.y * dist,
            lookWorld.z + dir.z * dist
        )

        // If the sphere clips while sliding around a surface, glide along the tangent.
        pos = slideCameraAlongSurfaces(from: previous, to: pos)

        pos = depenetrateCamera(at: pos)
        pos = projectCameraOntoLookRay(pos, look: lookWorld, direction: dir, distance: dist)

        if let voxelWorld {
            let ground = voxelWorld.surfaceY(atWorldX: pos.x, worldZ: pos.z)
            if pos.y < ground + cameraRadius {
                pos.y = ground + cameraRadius
                // Keep framing: push back onto the orbit ray at a safe distance.
                let toCam = simd_float3(pos.x - lookWorld.x, pos.y - lookWorld.y, pos.z - lookWorld.z)
                let len = simd_length(toCam)
                if len > 1e-4 {
                    let nd = toCam / len
                    let d = max(cameraMinDistance, min(cameraDistance, len))
                    pos = SCNVector3(
                        lookWorld.x + nd.x * d,
                        lookWorld.y + nd.y * d,
                        lookWorld.z + nd.z * d
                    )
                }
            }
        }

        cameraWorldPosition = pos
        cameraNode.position = cameraPitchNode.convertPosition(pos, from: nil)
    }

    private func slerpCameraDir(_ from: simd_float3, _ to: simd_float3, _ t: Float) -> simd_float3 {
        let clampedT = max(0, min(1, t))
        let dot = max(-1, min(1, simd_dot(from, to)))
        if dot > 0.9995 {
            return simd_normalize(from * (1 - clampedT) + to * clampedT)
        }
        if dot < -0.9995 {
            // Opposite directions — pick a perpendicular axis and rotate.
            var axis = simd_cross(from, simd_float3(0, 1, 0))
            if simd_length(axis) < 1e-4 {
                axis = simd_cross(from, simd_float3(1, 0, 0))
            }
            axis = simd_normalize(axis)
            let half = simd_quatf(angle: .pi * clampedT, axis: axis)
            return simd_normalize(half.act(from))
        }
        let theta = acos(dot)
        let sinTheta = sin(theta)
        let w1 = sin((1 - clampedT) * theta) / sinTheta
        let w2 = sin(clampedT * theta) / sinTheta
        return simd_normalize(from * w1 + to * w2)
    }

    private func clearCameraDistance(from: SCNVector3, toward: SCNVector3) -> Float {
        let move = simd_float3(toward.x - from.x, toward.y - from.y, toward.z - from.z)
        let moveLen = simd_length(move)
        guard moveLen > cameraMinDistance else { return cameraMinDistance }

        var best = moveLen
        let hits = rootNode.hitTestWithSegment(from: from, to: toward, options: cameraHitOptions())
        for hit in hits {
            guard !shouldIgnoreCameraHit(hit.node) else { continue }
            let hx = Float(hit.worldCoordinates.x - from.x)
            let hy = Float(hit.worldCoordinates.y - from.y)
            let hz = Float(hit.worldCoordinates.z - from.z)
            let hitDist = sqrt(hx * hx + hy * hy + hz * hz)
            best = min(best, max(cameraMinDistance, hitDist - cameraRadius))
        }
        return min(cameraDistance, best)
    }

    /// Collide-and-slide so orbiting around an obstacle follows its perimeter.
    private func slideCameraAlongSurfaces(from: SCNVector3, to: SCNVector3) -> SCNVector3 {
        var pos = from
        var remaining = simd_float3(to.x - from.x, to.y - from.y, to.z - from.z)

        for _ in 0..<4 {
            let remLen = simd_length(remaining)
            if remLen < 1e-5 { break }

            let candidate = SCNVector3(pos.x + remaining.x, pos.y + remaining.y, pos.z + remaining.z)
            let hits = rootNode.hitTestWithSegment(from: pos, to: candidate, options: cameraHitOptions())
            var closestHit: SCNHitTestResult?
            var closestDist = remLen
            for hit in hits {
                guard !shouldIgnoreCameraHit(hit.node) else { continue }
                let hx = Float(hit.worldCoordinates.x - pos.x)
                let hy = Float(hit.worldCoordinates.y - pos.y)
                let hz = Float(hit.worldCoordinates.z - pos.z)
                let hitDist = sqrt(hx * hx + hy * hy + hz * hz)
                if hitDist < closestDist {
                    closestDist = hitDist
                    closestHit = hit
                }
            }

            guard let hit = closestHit else {
                pos = candidate
                break
            }

            let travel = max(0, closestDist - cameraRadius * 0.98)
            let step = remaining / remLen
            pos = SCNVector3(
                pos.x + step.x * travel,
                pos.y + step.y * travel,
                pos.z + step.z * travel
            )

            var normal = simd_float3(
                Float(hit.worldNormal.x),
                Float(hit.worldNormal.y),
                Float(hit.worldNormal.z)
            )
            let nLen = simd_length(normal)
            if nLen > 1e-4 {
                normal /= nLen
            } else {
                normal = -step
            }
            // Outward from the surface (against the approach).
            if simd_dot(normal, step) > 0 {
                normal = -normal
            }

            // Keep only the tangential part → glide around the perimeter.
            let into = simd_dot(remaining, normal)
            if into < 0 {
                remaining -= normal * into
            } else {
                remaining = simd_float3(0, 0, 0)
            }

            pos = SCNVector3(
                pos.x + normal.x * 0.02,
                pos.y + normal.y * 0.02,
                pos.z + normal.z * 0.02
            )
        }
        return pos
    }

    private func projectCameraOntoLookRay(_ position: SCNVector3,
                                          look: SCNVector3,
                                          direction: simd_float3,
                                          distance: Float) -> SCNVector3 {
        // Prefer staying on the intended orbit ray after sliding/depenetration.
        let onRay = SCNVector3(
            look.x + direction.x * distance,
            look.y + direction.y * distance,
            look.z + direction.z * distance
        )
        // If on-ray is clear of fresh penetration, use it; otherwise keep slid position
        // projected to the same distance from the look target.
        let clear = clearCameraDistance(from: look, toward: onRay)
        if clear >= distance - 0.05 {
            return onRay
        }
        let offset = simd_float3(position.x - look.x, position.y - look.y, position.z - look.z)
        let len = simd_length(offset)
        guard len > 1e-4 else { return onRay }
        let d = max(cameraMinDistance, min(distance, len))
        let nd = offset / len
        return SCNVector3(look.x + nd.x * d, look.y + nd.y * d, look.z + nd.z * d)
    }

    private func depenetrateCamera(at position: SCNVector3) -> SCNVector3 {
        var pos = position
        let axes: [simd_float3] = [
            simd_float3(1, 0, 0), simd_float3(-1, 0, 0),
            simd_float3(0, 1, 0), simd_float3(0, -1, 0),
            simd_float3(0, 0, 1), simd_float3(0, 0, -1),
            simd_normalize(simd_float3(1, 0, 1)),
            simd_normalize(simd_float3(-1, 0, 1)),
            simd_normalize(simd_float3(1, 0, -1)),
            simd_normalize(simd_float3(-1, 0, -1)),
        ]
        for dir in axes {
            let end = SCNVector3(
                pos.x + dir.x * cameraRadius,
                pos.y + dir.y * cameraRadius,
                pos.z + dir.z * cameraRadius
            )
            let hits = rootNode.hitTestWithSegment(from: pos, to: end, options: cameraHitOptions())
            for hit in hits {
                guard !shouldIgnoreCameraHit(hit.node) else { continue }
                let hx = Float(hit.worldCoordinates.x - pos.x)
                let hy = Float(hit.worldCoordinates.y - pos.y)
                let hz = Float(hit.worldCoordinates.z - pos.z)
                let hitDist = sqrt(hx * hx + hy * hy + hz * hz)
                let penetration = cameraRadius - hitDist
                if penetration > 0 {
                    let n = hit.worldNormal
                    var nx = Float(n.x), ny = Float(n.y), nz = Float(n.z)
                    let nLen = sqrt(nx * nx + ny * ny + nz * nz)
                    if nLen > 1e-4 {
                        nx /= nLen; ny /= nLen; nz /= nLen
                    } else {
                        nx = dir.x; ny = dir.y; nz = dir.z
                    }
                    pos.x += nx * penetration
                    pos.y += ny * penetration
                    pos.z += nz * penetration
                }
            }
        }
        return pos
    }

    private func cameraHitOptions() -> [String: Any] {
        [
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.ignoreHiddenNodes.rawValue: true,
        ]
    }

    private func shouldIgnoreCameraHit(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let n = current {
            if n === playerNode || n === cameraArmNode || n === cameraPitchNode
                || n === cameraNode || n === cameraLookTarget {
                return true
            }
            if let name = n.name, name == "sky" || name == "tool_rig" {
                return true
            }
            current = n.parent
        }
        return false
    }

    // MARK: - NPCs

    private func spawnNPCs(for campNode: CampNode?) {
        guard let campNode else { return }
        var rng = SeededRandom(seed: worldSeed &+ 12345 &+ Self.stableSeed(campNode.site.id))
        let footprints = campNode.tentFootprints
        let cx = campNode.position.x
        let cz = campNode.position.z

        func blocked(_ wx: Float, _ wz: Float) -> Bool {
            footprints.contains { $0.contains(x: wx, z: wz) }
        }

        let campPersonalities: [NPCPersonality] = campNode.site.isHome
            ? [.elder, .child, .merchant]
            : [.elder, .merchant]

        for personality in campPersonalities {
            let spot = randomCampSpot(aroundX: cx, aroundZ: cz, rng: &rng, isBlocked: blocked)
                ?? (cx + 4, cz + 2)
            let h = groundY(x: spot.0, z: spot.1)
            let npc = NPCNode(personality: personality, position: SCNVector3(spot.0, h, spot.1))
            let padLimit = campNode.site.padRadius - 1
            npc.configureWander(radius: 5.5, groundY: { [weak self] x, z in
                self?.groundY(x: x, z: z) ?? 0
            }, isBlocked: { [weak self] x, z in
                guard let self else { return true }
                let dx = x - cx
                let dz = z - cz
                if sqrt(dx * dx + dz * dz) > padLimit { return true }
                return self.camps.contains { $0.isInsideTent(worldX: x, worldZ: z) }
            })
            rootNode.addChildNode(npc)
            npcs.append(npc)
        }

        // Wild travellers only from the home camp spawn.
        guard campNode.site.isHome else { return }
        for personality: NPCPersonality in [.wanderer, .lost] {
            var pos = SCNVector3(40, 0, 40)
            for _ in 0..<40 {
                let angle = rng.nextFloat() * Float.pi * 2
                let dist = 40 + rng.nextFloat() * 50
                let wx = cos(angle) * dist
                let wz = sin(angle) * dist
                if blocked(wx, wz) { continue }
                let h = groundY(x: wx, z: wz)
                if h < VoxelWorldGenerator(seed: worldSeed).campSurfaceMeters + 3 {
                    pos = SCNVector3(wx, h, wz)
                    break
                }
            }
            let npc = NPCNode(personality: personality, position: pos)
            npc.configureWander(radius: 9, groundY: { [weak self] x, z in
                self?.groundY(x: x, z: z) ?? 0
            }, isBlocked: { [weak self] x, z in
                self?.camps.contains { $0.isInsideTent(worldX: x, worldZ: z) } ?? false
            })
            rootNode.addChildNode(npc)
            npcs.append(npc)
        }
    }

    // MARK: - Animals

    private func spawnAnimals(for campNode: CampNode?) {
        guard let campNode else { return }
        var rng = SeededRandom(seed: worldSeed &+ 55_321 &+ Self.stableSeed(campNode.site.id))
        let cx = campNode.position.x
        let cz = campNode.position.z

        let kinds: [AnimalKind]
        if campNode.site.isHome {
            kinds = [.camel, .goat, .goat, .lizard, .bird]
        } else {
            kinds = [.goat, .lizard]
        }

        for kind in kinds {
            let spot = randomCampSpot(aroundX: cx, aroundZ: cz, rng: &rng) { wx, wz in
                campNode.isInsideTent(worldX: wx, worldZ: wz)
            } ?? (cx + 5 + rng.nextFloat() * 2, cz - 3)
            placeAnimal(kind: kind, x: spot.0, z: spot.1, campNode: campNode)
        }
    }

    private func spawnWildAnimals() {
        var rng = SeededRandom(seed: worldSeed &+ 77_777)
        let half = voxelWorld.totalSize * 0.5

        // Camels — open sand, away from home
        for _ in 0..<4 {
            guard let (wx, wz) = randomWildSpot(rng: &rng, half: half, minDistFromHome: 35) else { continue }
            placeAnimal(kind: .camel, x: wx, z: wz, campNode: nil, wanderOverride: 12)
        }

        // Goats — mid desert
        for _ in 0..<5 {
            guard let (wx, wz) = randomWildSpot(rng: &rng, half: half, minDistFromHome: 28) else { continue }
            placeAnimal(kind: .goat, x: wx, z: wz, campNode: nil, wanderOverride: 8)
        }

        // Lizards — scattered sand
        for _ in 0..<6 {
            guard let (wx, wz) = randomWildSpot(rng: &rng, half: half, minDistFromHome: 18) else { continue }
            placeAnimal(kind: .lizard, x: wx, z: wz, campNode: nil, wanderOverride: 4)
        }

        // Birds — prefer oasis rings
        if oases.isEmpty {
            for _ in 0..<3 {
                guard let (wx, wz) = randomWildSpot(rng: &rng, half: half, minDistFromHome: 20) else { continue }
                placeAnimal(kind: .bird, x: wx, z: wz, campNode: nil, wanderOverride: 12)
            }
        } else {
            for oasis in oases {
                let count = 1 + Int(rng.nextFloat() * 2)
                for _ in 0..<count {
                    let angle = rng.nextFloat() * Float.pi * 2
                    let dist = oasis.radius * 0.85 + rng.nextFloat() * oasis.radius * 0.6
                    let wx = oasis.position.x + cos(angle) * dist
                    let wz = oasis.position.z + sin(angle) * dist
                    placeAnimal(kind: .bird, x: wx, z: wz, campNode: nil, wanderOverride: 11)
                }
            }
        }
    }

    private func randomWildSpot(rng: inout SeededRandom,
                                half: Float,
                                minDistFromHome: Float) -> (Float, Float)? {
        for _ in 0..<40 {
            let wx = rng.nextFloat() * voxelWorld.totalSize - half
            let wz = rng.nextFloat() * voxelWorld.totalSize - half
            let distHome = sqrt(wx * wx + wz * wz)
            if distHome < minDistFromHome { continue }
            if camps.contains(where: {
                let dx = $0.position.x - wx
                let dz = $0.position.z - wz
                return dx * dx + dz * dz < ($0.site.padRadius + 4) * ($0.site.padRadius + 4)
            }) { continue }
            return (wx, wz)
        }
        return nil
    }

    private func placeAnimal(kind: AnimalKind,
                             x: Float,
                             z: Float,
                             campNode: CampNode?,
                             wanderOverride: Float? = nil) {
        let h = groundY(x: x, z: z)
        let animal = AnimalNode(kind: kind, position: SCNVector3(x, h, z))
        let padLimit = (campNode?.site.padRadius ?? 999) - 1
        let cx = campNode?.position.x ?? x
        let cz = campNode?.position.z ?? z

        animal.configureWander(radius: wanderOverride, groundY: { [weak self] wx, wz in
            self?.groundY(x: wx, z: wz) ?? 0
        }, isBlocked: { [weak self] wx, wz in
            guard let self else { return true }
            if self.camps.contains(where: { $0.isInsideTent(worldX: wx, worldZ: wz) }) {
                return true
            }
            if campNode != nil {
                let dx = wx - cx
                let dz = wz - cz
                if sqrt(dx * dx + dz * dz) > padLimit { return true }
            }
            return false
        })
        rootNode.addChildNode(animal)
        animals.append(animal)
    }

    /// Deterministic non-trapping seed from a string (hashValue can be negative → UInt64() traps).
    private static func stableSeed(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return hash
    }

    private func randomCampSpot(aroundX: Float,
                                aroundZ: Float,
                                rng: inout SeededRandom,
                                isBlocked: (Float, Float) -> Bool) -> (Float, Float)? {
        for _ in 0..<50 {
            let angle = rng.nextFloat() * Float.pi * 2
            let dist = 3.5 + rng.nextFloat() * 6.5
            let wx = aroundX + cos(angle) * dist
            let wz = aroundZ + sin(angle) * dist
            if isBlocked(wx, wz) { continue }
            let tooCloseNPC = npcs.contains {
                let dx = $0.position.x - wx
                let dz = $0.position.z - wz
                return dx * dx + dz * dz < 2.8 * 2.8
            }
            if tooCloseNPC { continue }
            let tooCloseAnimal = animals.contains {
                let dx = $0.position.x - wx
                let dz = $0.position.z - wz
                return dx * dx + dz * dz < 2.2 * 2.2
            }
            if tooCloseAnimal { continue }
            return (wx, wz)
        }
        return nil
    }

    // MARK: - Physics

    private func setupPhysics() {
        physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        physicsWorld.contactDelegate = self
    }

    // MARK: - Player movement

    private var moveInput: SIMD2<Float> = .zero
    private var isRunning = false
    private var verticalVelocity: Float = 0
    private var isGrounded = true
    private let moveSpeed: Float = 5.5
    private let runMultiplier: Float = 1.7
    private let jumpSpeed: Float = 7.2
    private let gravity: Float = 22
    private let turnSpeed: Float = 10.0
    private let moveDeadzone: Float = 0.08
    /// Auto-hop onto ledges up to this height (≈1 block).
    private let maxAutoStepUp: Float = 1.15
    /// Ignore tiny height noise.
    private let heightEpsilon: Float = 0.12

    func setMoveInput(dx: Float, dy: Float) {
        guard !isSleeping else {
            moveInput = .zero
            return
        }
        var input = SIMD2<Float>(dx, dy)
        let mag = simd_length(input)
        if mag > 1 {
            input /= mag
        }
        moveInput = input
    }

    func setRunning(_ running: Bool) {
        guard !isSleeping else { return }
        isRunning = running
    }

    func jump() {
        guard !isSleeping, isGrounded, !isInWater else { return }
        beginAirborne(velocity: jumpSpeed)
    }

    private func beginAirborne(velocity: Float) {
        verticalVelocity = velocity
        isGrounded = false
        playerNode?.playJumpAnimation()
    }

    func update(deltaTime: Float) {
        guard !isBuildingWorld, playerNode != nil else { return }
        let dt = max(0, min(deltaTime, 1.0 / 20.0))

        if isSleeping {
            // Sleep sequence drives its own time; still refresh sky via dayNight.apply.
            return
        }

        toolTime += dt
        dayNight.update(deltaTime: dt)
        timePersistAccumulator += dt
        if timePersistAccumulator >= 4 {
            timePersistAccumulator = 0
            onTimeOfDayChanged?(dayNight.timeOfDay)
        }

        campDrainAccumulator += dt
        if campDrainAccumulator >= campDrainInterval {
            campDrainAccumulator -= campDrainInterval
            for c in camps {
                let level = c.drainWater(amount: campDrainAmount)
                onCampDrained?(level, c.site.id)
            }
        }

        for c in camps {
            let hasNPCs = npcs.contains {
                let dx = $0.position.x - c.position.x
                let dz = $0.position.z - c.position.z
                return dx * dx + dz * dz < (c.site.padRadius + 2) * (c.site.padRadius + 2)
                    && !$0.personality.canReceiveWater
            }
            c.updateIrrigation(deltaTime: dt, hasCampNPCs: hasNPCs || c.site.isHome)
        }

        applyMovement(deltaTime: dt)
        updateNPCs(deltaTime: dt)
        updateAnimals(deltaTime: dt)
        updateWater(deltaTime: dt)
        updateTools()
        checkProximity()
        checkBarrelProximity()
        checkBedProximity()
        updateStreaming()
        discoverNearbyCamps()
        syncCameraFollow()
        resolveCameraCollision(deltaTime: dt)

        // Keep sky dome centered on player so it never clips at the horizon.
        if let playerNode {
            skyNode?.position = SCNVector3(playerNode.position.x, 0, playerNode.position.z)
        }
    }

    private func updateNPCs(deltaTime: Float) {
        for npc in npcs {
            npc.updateWander(deltaTime: deltaTime)
        }
    }

    private func updateAnimals(deltaTime: Float) {
        for animal in animals {
            animal.updateWander(deltaTime: deltaTime)
        }
    }

    private func applyMovement(deltaTime: Float) {
        guard let playerNode else { return }

        let inputLen = simd_length(moveInput)
        var nextX = playerNode.position.x
        var nextZ = playerNode.position.z
        let prevX = nextX
        let prevZ = nextZ

        if inputLen > moveDeadzone {
            let yaw = cameraArmNode.eulerAngles.y
            let sinY = sin(yaw)
            let cosY = cos(yaw)
            let forward = SIMD2<Float>(-sinY, -cosY)
            let right   = SIMD2<Float>( cosY, -sinY)

            let desired = right * moveInput.x + forward * moveInput.y
            let desiredLen = simd_length(desired)
            if desiredLen > 0.0001 {
                let dir = desired / desiredLen

                let waterMul: Float = isInWater ? 0.52 : 1.0
                let carryMul: Float = toolRig?.isCarryingWater == true ? 0.85 : 1.0
                let runMul: Float = (isRunning && !isInWater) ? runMultiplier : 1.0
                let speed = moveSpeed * min(inputLen, 1) * waterMul * carryMul * runMul
                playerHorizontalSpeed = speed
                let step = dir * speed * deltaTime
                nextX += step.x
                nextZ += step.y

                let targetYaw = atan2(dir.x, dir.y)
                let delta = shortestAngle(from: playerNode.eulerAngles.y, to: targetYaw)
                let maxTurn = turnSpeed * deltaTime
                playerNode.eulerAngles.y += max(-maxTurn, min(maxTurn, delta))
                playerNode.setWalking(true)
            } else {
                playerHorizontalSpeed = 0
                playerNode.setWalking(false)
            }
        } else {
            playerHorizontalSpeed = 0
            playerNode.setWalking(false)
        }

        if !camps.isEmpty {
            let bodyY = playerNode.position.y + 0.7
            var resolved = SIMD2(nextX, nextZ)
            let prev = SIMD2(prevX, prevZ)
            for c in camps {
                resolved = c.resolvePlayerXZ(
                    from: prev,
                    to: resolved,
                    worldY: bodyY,
                    radius: playerCollisionRadius
                )
            }
            nextX = resolved.x
            nextZ = resolved.y
        }

        let yOff: Float = isInWater ? -0.08 : 0.01
        let groundAtNext = groundY(x: nextX, z: nextZ) + yOff
        let groundAtPrev = groundY(x: prevX, z: prevZ) + yOff
        var nextY = playerNode.position.y

        if isInWater {
            verticalVelocity = 0
            if !isGrounded {
                isGrounded = true
                playerNode.landFromJump()
            }
            nextY = groundAtNext
            playerNode.position = SCNVector3(nextX, nextY, nextZ)
            return
        }

        // Auto step-up / walk-off while grounded
        if isGrounded {
            let rise = groundAtNext - nextY
            let drop = nextY - groundAtNext

            if rise > heightEpsilon {
                if rise <= maxAutoStepUp {
                    // Hop onto the higher block
                    let hop = sqrt(max(0, 2 * gravity * rise)) + 1.2
                    beginAirborne(velocity: hop)
                } else {
                    // Wall — cancel horizontal move
                    nextX = prevX
                    nextZ = prevZ
                    nextY = groundAtPrev
                    playerNode.position = SCNVector3(nextX, nextY, nextZ)
                    return
                }
            } else if drop > heightEpsilon {
                // Step / fall down — leave ground and play jump pose
                beginAirborne(velocity: 0)
            } else {
                nextY = groundAtNext
                playerNode.position = SCNVector3(nextX, nextY, nextZ)
                return
            }
        }

        // Airborne integration
        verticalVelocity -= gravity * deltaTime
        nextY += verticalVelocity * deltaTime

        let landY = groundY(x: nextX, z: nextZ) + yOff
        if nextY <= landY, verticalVelocity <= 0 {
            nextY = landY
            verticalVelocity = 0
            isGrounded = true
            playerNode.landFromJump()
        }

        playerNode.position = SCNVector3(nextX, nextY, nextZ)
    }

    private func updateWater(deltaTime: Float) {
        guard let playerNode else { return }
        var inside = false
        var canCollect = false
        for water in waterBodies {
            let id = ObjectIdentifier(water)
            if var timer = oasisRefillTimers[id] {
                timer -= deltaTime
                if timer <= 0 {
                    oasisRefillTimers.removeValue(forKey: id)
                    depletedWaterBodies.remove(id)
                    water.setDepleted(false)
                } else {
                    oasisRefillTimers[id] = timer
                }
            }
            let isDepleted = depletedWaterBodies.contains(id)
            water.update(
                deltaTime: deltaTime,
                playerWorldPosition: playerNode.position,
                playerSpeed: playerHorizontalSpeed
            )
            if water.contains(worldPosition: playerNode.position) {
                inside = true
                if !isDepleted && !(toolRig?.isCarryingWater == true) { canCollect = true }
            }
        }
        isInWater = inside
        if canCollect != wasNearCollectableWater {
            wasNearCollectableWater = canCollect
            onNearWater?(canCollect)
        }
    }

    private func updateTools() {
        guard let playerNode, let toolRig else { return }

        if toolRig.hasCompass, let nearest = nearestOasisDirection() {
            toolRig.updateCompass(playerYaw: playerNode.eulerAngles.y, directionXZ: nearest)
        }

        if toolRig.hasDetector {
            toolRig.updateDetector(signal: nearestWaterSignal(), time: toolTime)
        }
    }

    private func nearestOasisDirection() -> SIMD2<Float>? {
        guard let playerNode, !oases.isEmpty else { return nil }
        var best: OasisInfo?
        var bestDist = Float.greatestFiniteMagnitude
        for oasis in oases {
            let dx = oasis.position.x - playerNode.position.x
            let dz = oasis.position.z - playerNode.position.z
            let d = dx * dx + dz * dz
            if d < bestDist {
                bestDist = d
                best = oasis
            }
        }
        guard let best else { return nil }
        let dx = best.position.x - playerNode.position.x
        let dz = best.position.z - playerNode.position.z
        let len = sqrt(dx * dx + dz * dz)
        guard len > 0.001 else { return nil }
        return SIMD2<Float>(dx / len, dz / len)
    }

    private func nearestWaterSignal() -> Float {
        guard let playerNode else { return 0 }
        var best = Float.greatestFiniteMagnitude
        for oasis in oases {
            let dx = oasis.position.x - playerNode.position.x
            let dz = oasis.position.z - playerNode.position.z
            let dist = max(0, sqrt(dx * dx + dz * dz) - oasis.radius)
            best = min(best, dist)
        }
        if best >= 90 { return 0 }
        if best <= 5 { return 1 }
        return 1 - (best - 5) / 85
    }

    private func shortestAngle(from a: Float, to b: Float) -> Float {
        var diff = b - a
        while diff > .pi  { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return diff
    }

    func rotateCamera(yawDelta: Float, pitchDelta: Float = 0) {
        guard !isSleeping else { return }
        cameraArmNode.eulerAngles.y -= yawDelta
        cameraPitch = max(cameraPitchMin, min(cameraPitchMax, cameraPitch + pitchDelta))
        cameraPitchNode.eulerAngles.x = cameraPitch
        resolveCameraCollision(deltaTime: 1.0 / 60.0)
    }

    /// Backward-compatible yaw-only helper.
    /// Active POV — orbit camera, or cinematic sleep camera during timelapse.
    var activeCameraNode: SCNNode {
        sleepCameraNode ?? cameraNode
    }

    // MARK: - Water carry / deliver

    @discardableResult
    func tryCollectWater(enteredBody: OasisWaterNode? = nil) -> Bool {
        guard let toolRig, !toolRig.isCarryingWater, let playerNode else { return false }
        let body = enteredBody ?? waterBodies.first {
            $0.contains(worldPosition: playerNode.position) &&
            !depletedWaterBodies.contains(ObjectIdentifier($0))
        }
        guard let body, !depletedWaterBodies.contains(ObjectIdentifier(body)) else { return false }

        toolRig.setCarryingWater(true)
        let id = ObjectIdentifier(body)
        depletedWaterBodies.insert(id)
        oasisRefillTimers[id] = oasisRefillTime
        body.setDepleted(true)
        onWaterCollected?()
        return true
    }

    func giveWaterToNPC(_ npc: NPCNode) {
        guard let toolRig, toolRig.isCarryingWater else { return }
        toolRig.setCarryingWater(false)
        npcs.removeAll { $0.npcID == npc.npcID }
        npc.completeTask()
        onWaterGivenToNPC?(npc)
    }

    @discardableResult
    func tryDeliverWater() -> Bool {
        guard let toolRig, let playerNode else { return false }
        guard toolRig.isCarryingWater else { return false }
        guard let target = camps.first(where: { $0.canDeliver(at: playerNode.position) }) else {
            return false
        }

        toolRig.setCarryingWater(false)
        let level = target.deliverWater()
        deliveryCount += 1

        var unlockedCompass = false
        var unlockedDetector = false
        if !toolRig.hasCompass {
            toolRig.setCompassUnlocked(true)
            unlockedCompass = true
        }
        if !toolRig.hasDetector, deliveryCount >= 3 {
            toolRig.setDetectorUnlocked(true)
            unlockedDetector = true
        }

        onWaterDelivered?(level, unlockedCompass, unlockedDetector, target.site.id)
        return true
    }

    var canDeliverNow: Bool {
        guard let toolRig, let playerNode else { return false }
        return toolRig.isCarryingWater && camps.contains { $0.canDeliver(at: playerNode.position) }
    }

    var isCarryingWater: Bool { toolRig?.isCarryingWater == true }

    var nearestCampWithBed: CampNode? {
        guard let playerNode else { return nil }
        return camps.first { $0.isNearBed(worldPosition: playerNode.position) }
    }

    // MARK: - Sleep / skip night

    /// Timelapse: camera looks at sunset over the camping zone, then wakes at morning.
    func beginSleep(completion: (() -> Void)? = nil) {
        guard !isSleeping, let playerNode, let sleepCamp = nearestCampWithBed ?? camp else { return }
        isSleeping = true
        moveInput = .zero
        playerNode.setWalking(false)

        // Elevated cinematic camera looking west toward sunset + down at camp.
        let cam = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 58
        camera.zNear = 0.3
        camera.zFar = 900
        cam.camera = camera
        let campPos = sleepCamp.position
        cam.position = SCNVector3(campPos.x + 14, campPos.y + 11, campPos.z + 18)
        let look = SCNNode()
        look.position = SCNVector3(campPos.x - 8, campPos.y + 1.5, campPos.z - 4)
        rootNode.addChildNode(look)
        let constraint = SCNLookAtConstraint(target: look)
        constraint.isGimbalLockEnabled = true
        cam.constraints = [constraint]
        rootNode.addChildNode(cam)
        sleepCameraNode = cam
        cameraArmNode.isHidden = true

        // Start near dusk if daytime, otherwise keep current evening/night.
        if dayNight.timeOfDay > 0.28 && dayNight.timeOfDay < 0.68 {
            dayNight.setTimeOfDay(0.70)
        }

        let totalAdvance = dayNight.fractionUntilMorning()
        let duration: TimeInterval = 5.2
        let steps = 48
        let stepDt = duration / Double(steps)
        let advancePerStep = totalAdvance / Float(steps)
        // Simulate ~one night of irrigation work during the skip.
        let irrigateSeconds = 90 + totalAdvance * dayNight.dayLengthSeconds * 0.15

        for c in camps {
            c.simulateIrrigation(seconds: irrigateSeconds, hasCampNPCs: true)
            onOasisGrown?(c.site.id, c.oasisStage, c.oasisProgress, false)
            onCampDrained?(c.fillLevel, c.site.id)
        }

        var step = 0
        Timer.scheduledTimer(withTimeInterval: stepDt, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            self.dayNight.advance(by: advancePerStep)
            // Gentle camera drift during timelapse
            if let sleepCam = self.sleepCameraNode {
                sleepCam.position.x -= 0.04
                sleepCam.position.y += 0.01
            }
            if step >= steps {
                timer.invalidate()
                self.finishSleep(lookNode: look, completion: completion)
            }
        }
    }

    private func finishSleep(lookNode: SCNNode, completion: (() -> Void)?) {
        dayNight.setTimeOfDay(dayNight.nextMorning)
        sleepCameraNode?.removeFromParentNode()
        sleepCameraNode = nil
        lookNode.removeFromParentNode()
        cameraArmNode.isHidden = false
        cameraWorldPosition = nil
        isSleeping = false
        onTimeOfDayChanged?(dayNight.timeOfDay)
        onSleepFinished?()
        completion?()
    }

    // MARK: - Streaming / discovery

    private func updateStreaming() {
        guard let playerNode, let generator = buildGenerator, voxelWorld != nil else { return }
        let px = playerNode.position.x
        let pz = playerNode.position.z

        let needed = voxelWorld.chunkCoordinatesAround(
            worldX: px, worldZ: pz, radiusChunks: streamLoadRadius
        )
        for coord in needed where !voxelWorld.hasChunk(cx: coord.cx, cz: coord.cz) {
            if !streamPending.contains(where: { $0.cx == coord.cx && $0.cz == coord.cz }) {
                streamPending.append(coord)
            }
        }

        // Generate a few chunks per frame.
        var generated = 0
        while generated < streamChunksPerFrame, !streamPending.isEmpty {
            let coord = streamPending.removeFirst()
            if voxelWorld.hasChunk(cx: coord.cx, cz: coord.cz) { continue }
            generator.generateChunk(into: voxelWorld, cx: coord.cx, cz: coord.cz)
            voxelWorld.remeshChunk(cx: coord.cx, cz: coord.cz, animated: true)
            generated += 1
        }

        // Unload far chunks.
        let (bx, _, bz) = voxelWorld.blockCoord(worldX: px, worldY: 0, worldZ: pz)
        let (pcx, pcz) = voxelWorld.chunkCoord(blockX: bx, blockZ: bz)
        for chunk in voxelWorld.allChunks() {
            let dx = chunk.cx - pcx
            let dz = chunk.cz - pcz
            if max(abs(dx), abs(dz)) > streamUnloadRadius {
                voxelWorld.unloadChunk(cx: chunk.cx, cz: chunk.cz)
            }
        }
    }

    private func discoverNearbyCamps() {
        guard let playerNode, buildGenerator != nil, voxelWorld != nil else { return }
        let px = playerNode.position.x
        let pz = playerNode.position.z

        // Queue newly visible camps (do not spawn them in the same breath).
        for site in campSites where !spawnedCampIDs.contains(site.id) {
            if queuedCampSites.contains(where: { $0.id == site.id }) { continue }
            if case .prepareChunks(let s, _, _)? = campSpawnPhase, s.id == site.id { continue }
            if case .buildShell(let s)? = campSpawnPhase, s.id == site.id { continue }
            if case .buildNeighbours(let s, _)? = campSpawnPhase, s.id == site.id { continue }
            if case .finish(let s, _)? = campSpawnPhase, s.id == site.id { continue }
            let dx = site.worldX - px
            let dz = site.worldZ - pz
            guard sqrt(dx * dx + dz * dz) < campDiscoverRadius else { continue }
            queuedCampSites.append(site)
        }

        advanceCampSpawn()
    }

    private func advanceCampSpawn() {
        guard let generator = buildGenerator, voxelWorld != nil else { return }

        if campSpawnPhase == nil, let next = queuedCampSites.first {
            queuedCampSites.removeFirst()
            // Reserve the id immediately so we never double-queue on hitch frames.
            spawnedCampIDs.insert(next.id)
            let coords = voxelWorld.chunkCoordinatesAround(
                worldX: next.worldX, worldZ: next.worldZ, radiusChunks: 3
            )
            campSpawnPhase = .prepareChunks(site: next, coords: coords, index: 0)
        }

        switch campSpawnPhase {
        case .prepareChunks(let site, let coords, var index):
            var generated = 0
            while index < coords.count, generated < campPrepChunksPerFrame {
                let c = coords[index]
                index += 1
                if voxelWorld.hasChunk(cx: c.cx, cz: c.cz) { continue }
                generator.generateChunk(into: voxelWorld, cx: c.cx, cz: c.cz)
                voxelWorld.remeshChunk(cx: c.cx, cz: c.cz, animated: false)
                generated += 1
            }
            if index >= coords.count {
                campSpawnPhase = .buildShell(site: site)
            } else {
                campSpawnPhase = .prepareChunks(site: site, coords: coords, index: index)
            }

        case .buildShell(let site):
            let progress = slotCampProgress[site.id] ?? CampProgress(id: site.id)
            // spawnCamp inserts the id again — already reserved above.
            let node = spawnCamp(site: site, progress: progress)
            if node.hasPendingNeighbours {
                campSpawnPhase = .buildNeighbours(site: site, node: node)
            } else {
                campSpawnPhase = .finish(site: site, node: node)
            }

        case .buildNeighbours(let site, let node):
            // One lobby tent per frame — these meshes are huge.
            let more = node.buildNextPendingNeighbour()
            if !more {
                campSpawnPhase = .finish(site: site, node: node)
            }

        case .finish(let site, let node):
            spawnNPCs(for: node)
            spawnAnimals(for: node)

            let newOases = generator.placeAndCarveOases(
                into: voxelWorld, nearSites: [site], oasisCount: 1
            )
            for oasis in newOases {
                let key = oasisKey(oasis)
                guard !placedOasisKeys.contains(key) else { continue }
                placedOasisKeys.insert(key)
                oases.append(oasis)
                addWaterBody(for: oasis)
            }
            voxelWorld.remeshDirtyChunks()

            campSpawnPhase = nil
            slotCampProgress[site.id] = slotCampProgress[site.id] ?? CampProgress(id: site.id)
            let discovered = site
            DispatchQueue.main.async { [weak self] in
                self?.onCampDiscovered?(discovered)
            }

        case nil:
            break
        }
    }

    // MARK: - Proximity

    private func checkProximity() {
        guard let playerPos = playerNode?.position else { return }

        for oasis in oases {
            let dx = oasis.position.x - playerPos.x
            let dz = oasis.position.z - playerPos.z
            let dist = sqrt(dx*dx + dz*dz)
            if dist < oasis.radius + 1.0 {
                onOasisReached?(oasis)
            }
        }
    }

    private func checkBarrelProximity() {
        let near = canDeliverNow
        if near != wasNearBarrel {
            wasNearBarrel = near
            onNearBarrel?(near)
        }
    }

    private func checkBedProximity() {
        guard let playerNode else { return }
        let nearBed = camps.contains { $0.isNearBed(worldPosition: playerNode.position) }
        if nearBed != wasNearBed {
            wasNearBed = nearBed
            onNearBed?(nearBed)
        }
        let nearSettings = camps.contains { $0.isNearSettingsTable(worldPosition: playerNode.position) }
        if nearSettings != wasNearSettings {
            wasNearSettings = nearSettings
            onNearSettingsTable?(nearSettings)
        }
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
    }
}
