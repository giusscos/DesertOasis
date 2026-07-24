import SceneKit
import UIKit

enum VoxelMesher {

    static func mesh(chunk: VoxelChunk, world: VoxelWorld) -> SCNGeometry? {
        let bs = world.blockSize
        let (baseBX, baseBZ) = world.chunkOriginBlock(cx: chunk.cx, cz: chunk.cz)

        // Build 18×48×18 padded block array.
        // Layout: pi = (lx+1) + 18*((lz+1) + 18*ly)  for lx,lz ∈ [-1..16], ly ∈ [0..47]
        var padded = [UInt8](repeating: 0, count: 18 * 48 * 18)
        for ly in 0..<48 {
            for lz in -1...16 {
                for lx in -1...16 {
                    let pi = (lx+1) + 18 * ((lz+1) + 18*ly)
                    let t: VoxelType = chunk.inBounds(lx: lx, ly: ly, lz: lz)
                        ? chunk.block(lx: lx, ly: ly, lz: lz)
                        : world.block(at: baseBX+lx, by: ly, bz: baseBZ+lz)
                    padded[pi] = t.rawValue
                }
            }
        }

        var outV: UnsafeMutablePointer<Float>?   = nil
        var outN: UnsafeMutablePointer<Float>?   = nil
        var outC: UnsafeMutablePointer<Float>?   = nil
        var outI: UnsafeMutablePointer<Int32>?   = nil
        var vc: Int32 = 0, ic: Int32 = 0

        let count = voxel_mesh_build(padded, bs, &outV, &outN, &outC, &outI, &vc, &ic)
        guard count > 0,
              let vp = outV, let np = outN, let cp = outC, let ip = outI else { return nil }
        defer { voxel_mesh_free(outV, outN, outC, outI) }

        let vcI = Int(vc), icI = Int(ic)

        let vSrc = SCNGeometrySource(
            data: Data(bytes: vp, count: vcI * 12), semantic: .vertex,
            vectorCount: vcI, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)

        let nSrc = SCNGeometrySource(
            data: Data(bytes: np, count: vcI * 12), semantic: .normal,
            vectorCount: vcI, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)

        let cSrc = SCNGeometrySource(
            data: Data(bytes: cp, count: vcI * 16), semantic: .color,
            vectorCount: vcI, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)

        let elem = SCNGeometryElement(
            data: Data(bytes: ip, count: icI * 4),
            primitiveType: .triangles, primitiveCount: icI / 3, bytesPerIndex: 4)

        let geo = SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])
        let mat = SCNMaterial()
        mat.lightingModel    = .lambert
        mat.diffuse.contents = UIColor.white
        mat.isDoubleSided    = false
        mat.transparencyMode = .aOne
        mat.blendMode        = .alpha
        geo.firstMaterial    = mat
        return geo
    }
}
