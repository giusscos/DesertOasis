import SceneKit
import UIKit

/// Chunked full-3D voxel world. Block coords are world-space integers; origin is world center.
final class VoxelWorld {
    let blockSize: Float
    let seed: UInt64
    /// Half-extent in blocks (world spans [-halfExtent, halfExtent)).
    let halfExtent: Int
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

    var totalSize: Float { Float(halfExtent * 2) * blockSize }

    // MARK: - Coords

    func chunkKey(_ cx: Int, _ cz: Int) -> Int { cx * 10_000 + cz }

    func chunkCoord(blockX: Int, blockZ: Int) -> (Int, Int) {
        let ox = blockX + halfExtent
        let oz = blockZ + halfExtent
        return (ox / VoxelChunk.sizeX, oz / VoxelChunk.sizeZ)
    }

    func localCoord(blockX: Int, blockY: Int, blockZ: Int) -> (Int, Int, Int) {
        let ox = blockX + halfExtent
        let oz = blockZ + halfExtent
        return (ox % VoxelChunk.sizeX, blockY, oz % VoxelChunk.sizeZ)
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

    // MARK: - Access

    func chunk(cx: Int, cz: Int, create: Bool = false) -> VoxelChunk? {
        let key = chunkKey(cx, cz)
        if let c = chunks[key] { return c }
        guard create, cx >= 0, cx < chunksX, cz >= 0, cz < chunksZ else { return nil }
        let c = VoxelChunk(cx: cx, cz: cz)
        chunks[key] = c
        return c
    }

    func allChunks() -> [VoxelChunk] { Array(chunks.values) }

    func block(at bx: Int, by: Int, bz: Int) -> VoxelType {
        guard by >= 0, by < VoxelChunk.sizeY else { return .air }
        guard bx >= -halfExtent, bx < halfExtent, bz >= -halfExtent, bz < halfExtent else { return .air }
        let (cx, cz) = chunkCoord(blockX: bx, blockZ: bz)
        guard let chunk = chunk(cx: cx, cz: cz) else { return .air }
        let (lx, ly, lz) = localCoord(blockX: bx, blockY: by, blockZ: bz)
        return chunk.block(lx: lx, ly: ly, lz: lz)
    }

    func setBlock(at bx: Int, by: Int, bz: Int, type: VoxelType) {
        guard by >= 0, by < VoxelChunk.sizeY else { return }
        guard bx >= -halfExtent, bx < halfExtent, bz >= -halfExtent, bz < halfExtent else { return }
        let (cx, cz) = chunkCoord(blockX: bx, blockZ: bz)
        guard let chunk = self.chunk(cx: cx, cz: cz, create: true) else { return }
        let (lx, ly, lz) = localCoord(blockX: bx, blockY: by, blockZ: bz)
        chunk.setBlock(lx: lx, ly: ly, lz: lz, type: type)
    }

    /// Top of the highest non-air block in the column (world Y of the top face).
    func surfaceY(atWorldX wx: Float, worldZ wz: Float) -> Float {
        let bx = Int(floor(wx / blockSize))
        let bz = Int(floor(wz / blockSize))
        for by in stride(from: VoxelChunk.sizeY - 1, through: 0, by: -1) {
            if block(at: bx, by: by, bz: bz).isSurface {
                return Float(by + 1) * blockSize
            }
        }
        return 0
    }

    /// Top solid (non-water) surface — useful for oasis bowl depth checks.
    func solidSurfaceY(atWorldX wx: Float, worldZ wz: Float) -> Float {
        let bx = Int(floor(wx / blockSize))
        let bz = Int(floor(wz / blockSize))
        for by in stride(from: VoxelChunk.sizeY - 1, through: 0, by: -1) {
            let t = block(at: bx, by: by, bz: bz)
            if t.isSolid {
                return Float(by + 1) * blockSize
            }
        }
        return 0
    }

    // MARK: - Meshing

    /// Chunk coords sorted nearest-to-farthest from world center (camp).
    func chunkCoordinatesFromCenter() -> [(cx: Int, cz: Int)] {
        var coords: [(Int, Int)] = []
        coords.reserveCapacity(chunksX * chunksZ)
        for cz in 0..<chunksZ {
            for cx in 0..<chunksX {
                coords.append((cx, cz))
            }
        }
        let midX = Float(chunksX - 1) * 0.5
        let midZ = Float(chunksZ - 1) * 0.5
        return coords.sorted { a, b in
            let da = (Float(a.0) - midX) * (Float(a.0) - midX) + (Float(a.1) - midZ) * (Float(a.1) - midZ)
            let db = (Float(b.0) - midX) * (Float(b.0) - midX) + (Float(b.1) - midZ) * (Float(b.1) - midZ)
            return da < db
        }
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
        let originX = Float(chunk.cx * VoxelChunk.sizeX - halfExtent) * blockSize
        let originZ = Float(chunk.cz * VoxelChunk.sizeZ - halfExtent) * blockSize
        node.position = SCNVector3(originX, 0, originZ)
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
}
