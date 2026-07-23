import SceneKit
import UIKit

/// Builds an SCNGeometry for one chunk using exposed-face culling and vertex colors.
enum VoxelMesher {

    private struct Face {
        let dx: Int, dy: Int, dz: Int
        let corners: [(Float, Float, Float)]
        let normal: SCNVector3
    }

    // Corners relative to block min corner; winding CCW when viewed from outside.
    private static let faces: [Face] = [
        Face(dx: 0, dy: 1, dz: 0,
             corners: [(0,1,0), (0,1,1), (1,1,1), (1,1,0)],
             normal: SCNVector3(0, 1, 0)),
        Face(dx: 0, dy: -1, dz: 0,
             corners: [(0,0,0), (1,0,0), (1,0,1), (0,0,1)],
             normal: SCNVector3(0, -1, 0)),
        Face(dx: 1, dy: 0, dz: 0,
             corners: [(1,0,0), (1,1,0), (1,1,1), (1,0,1)],
             normal: SCNVector3(1, 0, 0)),
        Face(dx: -1, dy: 0, dz: 0,
             corners: [(0,0,0), (0,0,1), (0,1,1), (0,1,0)],
             normal: SCNVector3(-1, 0, 0)),
        Face(dx: 0, dy: 0, dz: 1,
             corners: [(0,0,1), (1,0,1), (1,1,1), (0,1,1)],
             normal: SCNVector3(0, 0, 1)),
        Face(dx: 0, dy: 0, dz: -1,
             corners: [(0,0,0), (0,1,0), (1,1,0), (1,0,0)],
             normal: SCNVector3(0, 0, -1)),
    ]

    static func mesh(chunk: VoxelChunk, world: VoxelWorld) -> SCNGeometry? {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [Float] = []
        var indices: [Int32] = []
        vertices.reserveCapacity(4096)
        indices.reserveCapacity(6144)

        let bs = world.blockSize
        let (baseBX, baseBZ) = world.chunkOriginBlock(cx: chunk.cx, cz: chunk.cz)

        for ly in 0..<VoxelChunk.sizeY {
            for lz in 0..<VoxelChunk.sizeZ {
                for lx in 0..<VoxelChunk.sizeX {
                    let type = chunk.block(lx: lx, ly: ly, lz: lz)
                    guard !type.isEmpty else { continue }

                    let bx = baseBX + lx
                    let bz = baseBZ + lz
                    let c = type.scnColor
                    let alpha: Float = type == .water ? 0.72 : (type == .leaf ? 0.85 : 1.0)

                    for face in faces {
                        let nType = neighborType(
                            lx: lx + face.dx, ly: ly + face.dy, lz: lz + face.dz,
                            bx: bx + face.dx, by: ly + face.dy, bz: bz + face.dz,
                            chunk: chunk, world: world
                        )

                        let shouldEmit: Bool
                        if type == .water {
                            shouldEmit = nType != .water
                        } else if type == .leaf {
                            shouldEmit = nType.isEmpty || nType == .water
                        } else {
                            shouldEmit = nType.isTransparent
                        }
                        guard shouldEmit else { continue }

                        let baseIndex = Int32(vertices.count)
                        let ox = Float(lx) * bs
                        let oy = Float(ly) * bs
                        let oz = Float(lz) * bs

                        for corner in face.corners {
                            vertices.append(SCNVector3(
                                ox + corner.0 * bs,
                                oy + corner.1 * bs,
                                oz + corner.2 * bs
                            ))
                            normals.append(face.normal)
                            colors.append(contentsOf: [c.x, c.y, c.z, alpha])
                        }
                        indices.append(contentsOf: [
                            baseIndex, baseIndex + 1, baseIndex + 2,
                            baseIndex, baseIndex + 2, baseIndex + 3
                        ])
                    }
                }
            }
        }

        guard !indices.isEmpty else { return nil }

        let vSource = SCNGeometrySource(vertices: vertices)
        let nSource = SCNGeometrySource(normals: normals)

        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vSource, nSource, colorSource], elements: [element])

        let mat = SCNMaterial()
        mat.lightingModel = .lambert
        mat.diffuse.contents = UIColor.white
        mat.isDoubleSided = false
        mat.transparencyMode = .aOne
        mat.blendMode = .alpha
        geo.firstMaterial = mat
        return geo
    }

    private static func neighborType(lx: Int, ly: Int, lz: Int,
                                     bx: Int, by: Int, bz: Int,
                                     chunk: VoxelChunk, world: VoxelWorld) -> VoxelType {
        if chunk.inBounds(lx: lx, ly: ly, lz: lz) {
            return chunk.block(lx: lx, ly: ly, lz: lz)
        }
        return world.block(at: bx, by: by, bz: bz)
    }
}
