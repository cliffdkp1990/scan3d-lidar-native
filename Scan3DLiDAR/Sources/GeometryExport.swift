import Foundation

/// Sensor-derived 3D geometry. Independent of ARKit; tested with Linux Swift.
struct CloudVertex: Equatable {
    let x: Float
    let y: Float
    let z: Float
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    func distanceSquared(to other: CloudVertex) -> Float {
        let dx=x-other.x, dy=y-other.y, dz=z-other.z
        return dx*dx + dy*dy + dz*dz
    }
}

private struct VoxelIndex: Hashable {
    let x: Int32
    let y: Int32
    let z: Int32
    init(_ point: CloudVertex, step: Float) {
        x = Int32((point.x/step).rounded(.down))
        y = Int32((point.y/step).rounded(.down))
        z = Int32((point.z/step).rounded(.down))
    }
}

/// Bounded, deduplicated set of world-space LiDAR points.
final class PointCollector {
    private var pointsByCell: [VoxelIndex: CloudVertex] = [:]
    let resolution: Float
    let maxPoints: Int
    init(resolution: Float = 0.025, maxPoints: Int = 120_000) {
        self.resolution = resolution
        self.maxPoints = maxPoints
    }
    var count: Int { pointsByCell.count }
    func clear() { pointsByCell.removeAll(keepingCapacity: true) }
    func add(_ point: CloudVertex, target: CloudVertex?, radius: Float = 0.7) {
        guard point.finite, count < maxPoints else { return }
        if let target, point.distanceSquared(to: target) > radius * radius { return }
        let key = VoxelIndex(point, step: resolution)
        if pointsByCell[key] == nil { pointsByCell[key] = point }
    }
    func snapshot() -> [CloudVertex] { Array(pointsByCell.values) }
}

/// OBJ and PLY output are local and intentionally omit color / photo textures.
/// OBJ output is ARKit's coarse spatial mesh, not a watertight print mesh.
enum GeometryExport {
    static func ply(points: [CloudVertex]) -> Data {
        let valid = points.filter(\.finite)
        var lines = [
            "ply", "format ascii 1.0", "comment Scan3D Studio LiDAR – ARKit session coordinates in meters",
            "element vertex \(valid.count)",
            "property float x", "property float y", "property float z", "end_header"
        ]
        lines.reserveCapacity(valid.count+8)
        for p in valid { lines.append("\(p.x) \(p.y) \(p.z)") }
        return Data((lines.joined(separator:"\n") + "\n").utf8)
    }

    /// Face indices are *0-based* here. OBJ uses *1-based* vertex indices.
    static func obj(vertices: [CloudVertex], triangles: [(Int, Int, Int)]) -> Data {
        var lines = ["# Scan3D Studio native LiDAR spatial mesh", "# Units: meters, ARKit session coordinates", "o lidar_capture"]
        for v in vertices {
            lines.append("v \(v.x) \(v.y) \(v.z)")
        }
        for (a,b,c) in triangles where a >= 0 && b >= 0 && c >= 0 && a < vertices.count && b < vertices.count && c < vertices.count {
            lines.append("f \(a+1) \(b+1) \(c+1)")
        }
        return Data((lines.joined(separator:"\n") + "\n").utf8)
    }
}
