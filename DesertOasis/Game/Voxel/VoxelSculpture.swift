import SceneKit
import UIKit

/// MagicaVoxel-style grid of unit cubes. Shapes are built by placing many small voxels
/// (spheres, cylinders, ellipsoids) — never by stretching a single large box.
final class VoxelSculpture {
    private(set) var sizeX: Int
    private(set) var sizeY: Int
    private(set) var sizeZ: Int
    /// World-space origin of grid cell (0,0,0) min corner.
    var origin: SIMD3<Float>
    private var cells: [UInt8]

    init(sizeX: Int, sizeY: Int, sizeZ: Int, origin: SIMD3<Float> = .zero) {
        self.sizeX = max(1, sizeX)
        self.sizeY = max(1, sizeY)
        self.sizeZ = max(1, sizeZ)
        self.origin = origin
        self.cells = [UInt8](repeating: VoxelType.air.rawValue, count: self.sizeX * self.sizeY * self.sizeZ)
    }

    /// Grow to fit a point if needed (expensive; prefer sizing up front).
    convenience init(minCapacityX: Int, minCapacityY: Int, minCapacityZ: Int) {
        self.init(sizeX: minCapacityX, sizeY: minCapacityY, sizeZ: minCapacityZ)
    }

    @inline(__always)
    private func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
        x + sizeX * (z + sizeZ * y)
    }

    func inBounds(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= 0 && x < sizeX && y >= 0 && y < sizeY && z >= 0 && z < sizeZ
    }

    func get(_ x: Int, _ y: Int, _ z: Int) -> VoxelType {
        guard inBounds(x, y, z) else { return .air }
        return VoxelType(rawValue: cells[index(x, y, z)]) ?? .air
    }

    func set(_ x: Int, _ y: Int, _ z: Int, _ type: VoxelType) {
        guard inBounds(x, y, z) else { return }
        cells[index(x, y, z)] = type.rawValue
    }

    // MARK: - Brush primitives (fill with unit cubes)

    func fillBox(x0: Int, y0: Int, z0: Int, x1: Int, y1: Int, z1: Int, type: VoxelType) {
        let xa = min(x0, x1), xb = max(x0, x1)
        let ya = min(y0, y1), yb = max(y0, y1)
        let za = min(z0, z1), zb = max(z0, z1)
        for y in ya...yb {
            for z in za...zb {
                for x in xa...xb {
                    set(x, y, z, type)
                }
            }
        }
    }

    /// Solid ellipsoid centered at (cx,cy,cz) with radii in voxels.
    func fillEllipsoid(cx: Float, cy: Float, cz: Float,
                       rx: Float, ry: Float, rz: Float, type: VoxelType) {
        let x0 = Int(floor(cx - rx)), x1 = Int(ceil(cx + rx))
        let y0 = Int(floor(cy - ry)), y1 = Int(ceil(cy + ry))
        let z0 = Int(floor(cz - rz)), z1 = Int(ceil(cz + rz))
        let rx2 = max(rx * rx, 0.01), ry2 = max(ry * ry, 0.01), rz2 = max(rz * rz, 0.01)
        for y in y0...y1 {
            for z in z0...z1 {
                for x in x0...x1 {
                    let dx = (Float(x) + 0.5 - cx)
                    let dy = (Float(y) + 0.5 - cy)
                    let dz = (Float(z) + 0.5 - cz)
                    if (dx * dx) / rx2 + (dy * dy) / ry2 + (dz * dz) / rz2 <= 1.0 {
                        set(x, y, z, type)
                    }
                }
            }
        }
    }

    func fillSphere(cx: Float, cy: Float, cz: Float, r: Float, type: VoxelType) {
        fillEllipsoid(cx: cx, cy: cy, cz: cz, rx: r, ry: r, rz: r, type: type)
    }

    /// Axis-aligned cylinder along Y (default), X, or Z.
    func fillCylinder(axis: Axis = .y,
                      c0: Float, c1: Float,
                      a0: Float, a1: Float,
                      radius: Float, type: VoxelType) {
        let r2 = radius * radius
        switch axis {
        case .y:
            let yLo = Int(floor(min(a0, a1))), yHi = Int(ceil(max(a0, a1)))
            let x0 = Int(floor(c0 - radius)), x1 = Int(ceil(c0 + radius))
            let z0 = Int(floor(c1 - radius)), z1 = Int(ceil(c1 + radius))
            for y in yLo...yHi {
                for z in z0...z1 {
                    for x in x0...x1 {
                        let dx = Float(x) + 0.5 - c0
                        let dz = Float(z) + 0.5 - c1
                        if dx * dx + dz * dz <= r2 { set(x, y, z, type) }
                    }
                }
            }
        case .x:
            let xLo = Int(floor(min(a0, a1))), xHi = Int(ceil(max(a0, a1)))
            let y0 = Int(floor(c0 - radius)), y1 = Int(ceil(c0 + radius))
            let z0 = Int(floor(c1 - radius)), z1 = Int(ceil(c1 + radius))
            for x in xLo...xHi {
                for z in z0...z1 {
                    for y in y0...y1 {
                        let dy = Float(y) + 0.5 - c0
                        let dz = Float(z) + 0.5 - c1
                        if dy * dy + dz * dz <= r2 { set(x, y, z, type) }
                    }
                }
            }
        case .z:
            let zLo = Int(floor(min(a0, a1))), zHi = Int(ceil(max(a0, a1)))
            let x0 = Int(floor(c0 - radius)), x1 = Int(ceil(c0 + radius))
            let y0 = Int(floor(c1 - radius)), y1 = Int(ceil(c1 + radius))
            for z in zLo...zHi {
                for y in y0...y1 {
                    for x in x0...x1 {
                        let dx = Float(x) + 0.5 - c0
                        let dy = Float(y) + 0.5 - c1
                        if dx * dx + dy * dy <= r2 { set(x, y, z, type) }
                    }
                }
            }
        }
    }

    /// Hollow tube (cylinder shell).
    func fillTube(axis: Axis = .y,
                  c0: Float, c1: Float,
                  a0: Float, a1: Float,
                  outerR: Float, innerR: Float, type: VoxelType) {
        let o2 = outerR * outerR, i2 = innerR * innerR
        switch axis {
        case .y:
            let yLo = Int(floor(min(a0, a1))), yHi = Int(ceil(max(a0, a1)))
            let x0 = Int(floor(c0 - outerR)), x1 = Int(ceil(c0 + outerR))
            let z0 = Int(floor(c1 - outerR)), z1 = Int(ceil(c1 + outerR))
            for y in yLo...yHi {
                for z in z0...z1 {
                    for x in x0...x1 {
                        let dx = Float(x) + 0.5 - c0
                        let dz = Float(z) + 0.5 - c1
                        let d = dx * dx + dz * dz
                        if d <= o2 && d >= i2 { set(x, y, z, type) }
                    }
                }
            }
        default:
            fillCylinder(axis: axis, c0: c0, c1: c1, a0: a0, a1: a1, radius: outerR, type: type)
        }
    }

    enum Axis { case x, y, z }

    // MARK: - Meshing

    /// Face-culled mesh of every solid unit cube — teapot / MagicaVoxel look.
    func mesh(unit: Float = VoxelMetrics.unit,
              colorOverride: ((VoxelType) -> UIColor)? = nil) -> SCNGeometry? {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [Float] = []
        var indices: [Int32] = []
        vertices.reserveCapacity(2048)
        indices.reserveCapacity(3072)

        let faces = Self.faces
        let ox = origin.x, oy = origin.y, oz = origin.z

        for y in 0..<sizeY {
            for z in 0..<sizeZ {
                for x in 0..<sizeX {
                    let type = get(x, y, z)
                    guard !type.isEmpty else { continue }

                    let ui = colorOverride?(type) ?? type.color
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let alpha: Float = type == .water ? 0.72 : (type == .leaf ? 0.85 : Float(a))

                    for face in faces {
                        let nx = x + face.dx, ny = y + face.dy, nz = z + face.dz
                        let nType = get(nx, ny, nz)
                        let shouldEmit: Bool
                        if type == .water {
                            shouldEmit = nType != .water
                        } else if type == .leaf {
                            shouldEmit = nType.isEmpty || nType == .water
                        } else {
                            shouldEmit = nType.isTransparent
                        }
                        guard shouldEmit else { continue }

                        let base = Int32(vertices.count)
                        let bx = ox + Float(x) * unit
                        let by = oy + Float(y) * unit
                        let bz = oz + Float(z) * unit
                        for corner in face.corners {
                            vertices.append(SCNVector3(
                                bx + corner.0 * unit,
                                by + corner.1 * unit,
                                bz + corner.2 * unit
                            ))
                            normals.append(face.normal)
                            colors.append(contentsOf: [Float(r), Float(g), Float(b), alpha])
                        }
                        indices.append(contentsOf: [
                            base, base + 1, base + 2,
                            base, base + 2, base + 3
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
        // Soft self-light for canvas interiors
        if cells.contains(where: { $0 == VoxelType.canvas.rawValue }) {
            mat.emission.contents = UIColor(white: 0.08, alpha: 1)
        }
        geo.firstMaterial = mat
        return geo
    }

    func makeNode(name: String? = nil,
                  unit: Float = VoxelMetrics.unit,
                  colorOverride: ((VoxelType) -> UIColor)? = nil) -> SCNNode {
        let node = SCNNode(geometry: mesh(unit: unit, colorOverride: colorOverride))
        node.name = name
        return node
    }

    private struct Face {
        let dx: Int, dy: Int, dz: Int
        let corners: [(Float, Float, Float)]
        let normal: SCNVector3
    }

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
}
