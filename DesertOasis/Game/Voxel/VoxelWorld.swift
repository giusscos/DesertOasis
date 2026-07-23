import SceneKit
import UIKit

/// Sparse chunked voxel world with signed chunk coords — streams infinitely around the player.
final class VoxelWorld {
    let blockSize: Float
    let seed: UInt64
    /// Soft half-extent used only for legacy noise scaling / oasis placement helpers.
    let halfExtent: Int
    /// Kept for compatibility; streaming worlds ignore these as hard limits.
    let chunksX: Int
    let chunksZ: Int

    private var chunks: [Int: VoxelChunk] = [:]
    private(set) var rootNode = SCNNode()

    init(seed: UInt64,
         blockSize: Float = VoxelMetrics.blockSize,
         worldSizeBlocks: Int = VoxelMetrics.worldSizeBlocks) {
        self.seed = seed
        self.blockSize = blockSize
        self.halfExtent = worldSizeBlocks / 2
        self.chunksX = (worldSizeBlocks + VoxelChunk.sizeX - 1) / VoxelChunk.sizeX
        self.chunksZ = chunksX
        rootNode.name = "voxel_world"
    }

    /// Noise scale reference (meters) — keeps dune frequency stable in infinite worlds.
    var totalSize: Float { VoxelMetrics.worldSizeMeters }

    // MARK: - Coords

    func chunkKey(_ cx: Int, _ cz: Int) -> Int {
        // Pack signed 16-bit-ish coords into one Int key.
        ((cx & 0xFFFF) << 16) | (cz & 0xFFFF)
    }

    /// Floor-division chunk index (works for negative block coords).
    func chunkCoord(blockX: Int, blockZ: Int) -> (Int, Int) {
        (Self.floorDiv(blockX, VoxelChunk.sizeX), Self.floorDiv(blockZ, VoxelChunk.sizeZ))
    }

    func localCoord(blockX: Int, blockY: Int, blockZ: Int) -> (Int, Int, Int) {
        (
            Self.floorMod(blockX, VoxelChunk.sizeX),
            blockY,
            Self.floorMod(blockZ, VoxelChunk.sizeZ)
        )
    }

    func worldPosition(blockX: Int, blockY: Int, blockZ: Int) -> SCNVector3 {
        SCNVector3(
            Float(blockX) * blockSize,
            Float(blockY) * blockSize,
            Float(blockZ) * blockSize
        )
    }

    func blockCoord(worldX: Float, worldY: Float, worldZ: Float) -> (Int, Int, Int) {
        (
            Int(floor(worldX / blockSize)),
            Int(floor(worldY / blockSize)),
            Int(floor(worldZ / blockSize))
        )
    }

    func chunkOriginBlock(cx: Int, cz: Int) -> (Int, Int) {
        (cx * VoxelChunk.sizeX, cz * VoxelChunk.sizeZ)
    }

    // MARK: - Access

    func chunk(cx: Int, cz: Int, create: Bool = false) -> VoxelChunk? {
        let key = chunkKey(cx, cz)
        if let c = chunks[key] { return c }
        guard create else { return nil }
        let c = VoxelChunk(cx: cx, cz: cz)
        chunks[key] = c
        return c
    }

    func allChunks() -> [VoxelChunk] { Array(chunks.values) }

    func hasChunk(cx: Int, cz: Int) -> Bool {
        chunks[chunkKey(cx, cz)] != nil
    }

    func unloadChunk(cx: Int, cz: Int) {
        let key = chunkKey(cx, cz)
        guard chunks.removeValue(forKey: key) != nil else { return }
        let name = "chunk_\(cx)_\(cz)"
        rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode()
    }

    func block(at bx: Int, by: Int, bz: Int) -> VoxelType {
        guard by >= 0, by < VoxelChunk.sizeY else { return .air }
        let (cx, cz) = chunkCoord(blockX: bx, blockZ: bz)
        guard let chunk = chunk(cx: cx, cz: cz) else { return .air }
        let (lx, ly, lz) = localCoord(blockX: bx, blockY: by, blockZ: bz)
        return chunk.block(lx: lx, ly: ly, lz: lz)
    }

    func setBlock(at bx: Int, by: Int, bz: Int, type: VoxelType) {
        guard by >= 0, by < VoxelChunk.sizeY else { return }
        let (cx, cz) = chunkCoord(blockX: bx, blockZ: bz)
        guard let chunk = self.chunk(cx: cx, cz: cz, create: true) else { return }
        let (lx, ly, lz) = localCoord(blockX: bx, blockY: by, blockZ: bz)
        chunk.setBlock(lx: lx, ly: ly, lz: lz, type: type)
    }

    func surfaceY(atWorldX wx: Float, worldZ wz: Float) -> Float {
        let bx = Int(floor(wx / blockSize))
        let bz = Int(floor(wz / blockSize))
        for by in stride(from: VoxelChunk.sizeY - 1, through: 0, by: -1) {
            if block(at: bx, by: by, bz: bz).isSurface {
                return Float(by + 1) * blockSize
            }
        }
        // Estimate from noise when chunk not loaded yet.
        return Float(VoxelWorldGenerator(seed: seed).columnHeight(
            bx: bx, bz: bz, totalSize: totalSize
        )) * blockSize
    }

    func solidSurfaceY(atWorldX wx: Float, worldZ wz: Float) -> Float {
        let bx = Int(floor(wx / blockSize))
        let bz = Int(floor(wz / blockSize))
        for by in stride(from: VoxelChunk.sizeY - 1, through: 0, by: -1) {
            let t = block(at: bx, by: by, bz: bz)
            if t.isSolid {
                return Float(by + 1) * blockSize
            }
        }
        return surfaceY(atWorldX: wx, worldZ: wz)
    }

    // MARK: - Streaming helpers

    /// Chunks in a square around a world position, nearest-first.
    func chunkCoordinatesAround(worldX: Float, worldZ: Float, radiusChunks: Int) -> [(cx: Int, cz: Int)] {
        let (bx, _, bz) = blockCoord(worldX: worldX, worldY: 0, worldZ: worldZ)
        let (pcx, pcz) = chunkCoord(blockX: bx, blockZ: bz)
        var coords: [(Int, Int)] = []
        for dz in -radiusChunks...radiusChunks {
            for dx in -radiusChunks...radiusChunks {
                coords.append((pcx + dx, pcz + dz))
            }
        }
        return coords.sorted { a, b in
            let da = (a.0 - pcx) * (a.0 - pcx) + (a.1 - pcz) * (a.1 - pcz)
            let db = (b.0 - pcx) * (b.0 - pcx) + (b.1 - pcz) * (b.1 - pcz)
            return da < db
        }
    }

    /// Initial load around camp (origin).
    func chunkCoordinatesFromCenter(radiusChunks: Int = 10) -> [(cx: Int, cz: Int)] {
        chunkCoordinatesAround(worldX: 0, worldZ: 0, radiusChunks: radiusChunks)
    }

    func remeshDirtyChunks() {
        for chunk in chunks.values where chunk.isDirty {
            remesh(chunk, animated: false)
        }
    }

    func remeshAll() {
        for chunk in chunks.values {
            chunk.isDirty = true
            remesh(chunk, animated: false)
        }
    }

    func remeshChunk(cx: Int, cz: Int, animated: Bool = true) {
        guard let chunk = chunk(cx: cx, cz: cz) else { return }
        remesh(chunk, animated: animated)
    }

    private func remesh(_ chunk: VoxelChunk, animated: Bool) {
        let name = "chunk_\(chunk.cx)_\(chunk.cz)"
        rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode()

        let geometry = VoxelMesher.mesh(chunk: chunk, world: self)
        chunk.isDirty = false
        guard let geometry else { return }

        let node = SCNNode(geometry: geometry)
        node.name = name
        let (originBX, originBZ) = chunkOriginBlock(cx: chunk.cx, cz: chunk.cz)
        node.position = SCNVector3(Float(originBX) * blockSize, 0, Float(originBZ) * blockSize)
        node.castsShadow = false
        if animated {
            node.opacity = 0
            rootNode.addChildNode(node)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            node.opacity = 1
            SCNTransaction.commit()
        } else {
            rootNode.addChildNode(node)
        }
    }

    // MARK: - Math

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        let r = a % b
        return r == 0 ? q : (a < 0 ? q - 1 : q)
    }

    private static func floorMod(_ a: Int, _ b: Int) -> Int {
        let r = a % b
        return r >= 0 ? r : r + b
    }
}
