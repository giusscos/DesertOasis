import Foundation

/// Dense 16×48×16 block storage for one world chunk.
final class VoxelChunk {
    static let sizeX = 16
    static let sizeY = 48
    static let sizeZ = 16
    static var volume: Int { sizeX * sizeY * sizeZ }

    let cx: Int
    let cz: Int
    private var blocks: [UInt8]
    var isDirty = true

    init(cx: Int, cz: Int) {
        self.cx = cx
        self.cz = cz
        self.blocks = [UInt8](repeating: VoxelType.air.rawValue, count: Self.volume)
    }

    @inline(__always)
    private func index(_ lx: Int, _ ly: Int, _ lz: Int) -> Int {
        lx + Self.sizeX * (lz + Self.sizeZ * ly)
    }

    func inBounds(lx: Int, ly: Int, lz: Int) -> Bool {
        lx >= 0 && lx < Self.sizeX &&
        ly >= 0 && ly < Self.sizeY &&
        lz >= 0 && lz < Self.sizeZ
    }

    func block(lx: Int, ly: Int, lz: Int) -> VoxelType {
        guard inBounds(lx: lx, ly: ly, lz: lz) else { return .air }
        return VoxelType(rawValue: blocks[index(lx, ly, lz)]) ?? .air
    }

    func setBlock(lx: Int, ly: Int, lz: Int, type: VoxelType) {
        guard inBounds(lx: lx, ly: ly, lz: lz) else { return }
        let i = index(lx, ly, lz)
        if blocks[i] != type.rawValue {
            blocks[i] = type.rawValue
            isDirty = true
        }
    }

    /// Fill an entire local column from yStart..<yEnd (exclusive).
    func fillColumn(lx: Int, lz: Int, yStart: Int, yEnd: Int, type: VoxelType) {
        let lo = max(0, yStart)
        let hi = min(Self.sizeY, yEnd)
        guard lo < hi, lx >= 0, lx < Self.sizeX, lz >= 0, lz < Self.sizeZ else { return }
        for ly in lo..<hi {
            blocks[index(lx, ly, lz)] = type.rawValue
        }
        isDirty = true
    }
}
