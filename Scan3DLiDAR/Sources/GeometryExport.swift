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
    init?(_ point: CloudVertex, step: Float) {
        let values=[point.x,point.y,point.z].map { (Double($0)/Double(step)).rounded(.down) }
        guard values.allSatisfy({ $0.isFinite && $0 >= Double(Int32.min) && $0 <= Double(Int32.max) }) else { return nil }
        x=Int32(values[0]); y=Int32(values[1]); z=Int32(values[2])
    }
}

/// Bounded, deduplicated set of world-space LiDAR points.
final class PointCollector {
    private var pointsByCell: [VoxelIndex: (point: CloudVertex, weight: Int)] = [:]
    let resolution: Float
    let maxPoints: Int
    init(resolution: Float = 0.008, maxPoints: Int = 120_000) {
        self.resolution = resolution.isFinite && resolution > 0 && resolution <= 1 ? resolution : 0.008
        self.maxPoints = max(1,min(2_000_000,maxPoints))
    }
    var count: Int { pointsByCell.count }
    func clear() { pointsByCell.removeAll(keepingCapacity: true) }
    func add(_ point: CloudVertex, target: CloudVertex?, radius: Float = 0.7) {
        guard point.finite, radius.isFinite, radius > 0, target?.finite != false else { return }
        if let target, point.distanceSquared(to: target) > radius * radius { return }
        guard let key = VoxelIndex(point, step: resolution) else { return }
        if let sample=pointsByCell[key] {
            let weight=min(8,sample.weight)
            let n=Float(weight)
            let averaged=CloudVertex(x:(sample.point.x*n+point.x)/(n+1),
                y:(sample.point.y*n+point.y)/(n+1),z:(sample.point.z*n+point.z)/(n+1))
            pointsByCell[key]=(averaged,weight+1)
        } else if count < maxPoints { pointsByCell[key]=(point,1) }
    }
    func snapshot() -> [CloudVertex] { pointsByCell.values.map { $0.point } }
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

    struct OBJResult {
        let data: Data
        let triangleCount: Int
        let discardedTriangleCount: Int
    }

    private struct FaceKey: Hashable {
        let a: Int
        let b: Int
        let c: Int

        init(_ a: Int, _ b: Int, _ c: Int) {
            let indices = [a,b,c].sorted()
            self.a = indices[0]
            self.b = indices[1]
            self.c = indices[2]
        }
    }

    /// Face indices are *0-based* here. OBJ uses *1-based* vertex indices.
    /// Preserve positions and winding; drop invalid vertices, invalid/zero-area
    /// faces and duplicate indexed faces. This is not mesh repair or segmentation.
    static func validatedOBJ(vertices: [CloudVertex], triangles: [(Int, Int, Int)]) -> OBJResult {
        var lines = ["# Scan3D Studio native LiDAR spatial mesh", "# Units: meters, ARKit session coordinates", "o lidar_capture"]
        var indices = [Int](repeating: 0, count: vertices.count)
        var nextIndex = 1
        for (i,v) in vertices.enumerated() where v.finite {
            indices[i] = nextIndex
            nextIndex += 1
            lines.append("v \(v.x) \(v.y) \(v.z)")
        }

        // Double intermediates prevent overflow/underflow for finite Float inputs.
        func hasArea(_ a: CloudVertex, _ b: CloudVertex, _ c: CloudVertex) -> Bool {
            let ux = Double(b.x) - Double(a.x)
            let uy = Double(b.y) - Double(a.y)
            let uz = Double(b.z) - Double(a.z)
            let vx = Double(c.x) - Double(a.x)
            let vy = Double(c.y) - Double(a.y)
            let vz = Double(c.z) - Double(a.z)
            let x = uy*vz - uz*vy
            let y = uz*vx - ux*vz
            let z = ux*vy - uy*vx
            return x != 0 || y != 0 || z != 0
        }

        var seen = Set<FaceKey>()
        var exported = 0
        for (a,b,c) in triangles {
            guard vertices.indices.contains(a), vertices.indices.contains(b), vertices.indices.contains(c),
                  a != b, b != c, a != c,
                  indices[a] > 0, indices[b] > 0, indices[c] > 0,
                  hasArea(vertices[a],vertices[b],vertices[c]) else { continue }
            guard seen.insert(FaceKey(a,b,c)).inserted else { continue }
            lines.append("f \(indices[a]) \(indices[b]) \(indices[c])")
            exported += 1
        }
        return OBJResult(data: Data((lines.joined(separator:"\n") + "\n").utf8),
            triangleCount: exported, discardedTriangleCount: triangles.count - exported)
    }

    static func obj(vertices: [CloudVertex], triangles: [(Int, Int, Int)]) -> Data {
        validatedOBJ(vertices: vertices, triangles: triangles).data
    }
}
