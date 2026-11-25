import ARKit
import Foundation
import Metal
import simd

/// Converts real ARFrame smoothedSceneDepth pixels into ARKit world-space points.
/// Camera intrinsics and capture image dimensions are accounted for; results remain approximate.
enum LiDARDepthSampler {
    static func sample(frame: ARFrame, into collector: PointCollector, target: CloudVertex?) -> Int {
        guard let selected=LiDARFrameQuality.selected(frame) else { return 0 }
        return DepthBufferSampler.sample(depth:selected.depth,confidence:selected.confidence,intrinsics:frame.camera.intrinsics,
            imageSize:SIMD2<Float>(Float(CVPixelBufferGetWidth(frame.capturedImage)),Float(CVPixelBufferGetHeight(frame.capturedImage))),
            transform:frame.camera.transform,into:collector,target:target)
    }
}

/// Export mesh currently reported by ARKit, bounded to a radius around the locked target.
/// The result includes scene geometry; it is neither a segmented object nor a watertight solid.
enum LiDARSceneMesh {
    static func export(frame: ARFrame, target: CloudVertex, radius: Float = 0.75) -> (Data, Int) {
        var vertices: [CloudVertex] = []
        var triangles: [(Int,Int,Int)] = []
        let radius2 = radius*radius
        for anchor in frame.anchors.compactMap({ $0 as? ARMeshAnchor }) {
            let mesh = anchor.geometry
            let source = mesh.vertices
            guard source.format == .float3, source.componentsPerVector == 3 else { continue }
            let buffer = source.buffer.contents()
            // ARGeometrySource.stride is not necessarily 12 due to padding.
            func worldPoint(_ i: Int) -> CloudVertex? {
                guard i >= 0, i < source.count else { return nil }
                let base = buffer.advanced(by:source.offset + i*source.stride)
                let v = base.assumingMemoryBound(to:Float.self)
                let pos = simd_mul(anchor.transform, SIMD4<Float>(v[0],v[1],v[2],1))
                return CloudVertex(x:pos.x,y:pos.y,z:pos.z)
            }
            let faces = mesh.faces
            guard faces.indexCountPerPrimitive == 3 && (faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4) else { continue }
            let indices = faces.buffer.contents()
            func getIndex(_ i: Int) -> Int {
                let p = indices.advanced(by: i*faces.bytesPerIndex)
                return faces.bytesPerIndex == 4 ? Int(p.assumingMemoryBound(to:UInt32.self).pointee) : Int(p.assumingMemoryBound(to:UInt16.self).pointee)
            }
            var localToGlobal: [Int:Int] = [:]
            for face in 0..<faces.count {
                let ids = (0..<3).map { getIndex(face*3+$0) }
                guard let p0 = worldPoint(ids[0]), let p1 = worldPoint(ids[1]), let p2 = worldPoint(ids[2]),
                      p0.finite && p1.finite && p2.finite,
                      p0.distanceSquared(to:target) <= radius2,
                      p1.distanceSquared(to:target) <= radius2,
                      p2.distanceSquared(to:target) <= radius2 else { continue }
                var global: [Int] = []
                for (i,v) in zip(ids,[p0,p1,p2]) {
                    if let existing = localToGlobal[i] { global.append(existing) }
                    else {
                        localToGlobal[i] = vertices.count
                        global.append(vertices.count)
                        vertices.append(v)
                    }
                }
                triangles.append((global[0],global[1],global[2]))
                if triangles.count >= 160_000 { break }
            }
            if triangles.count >= 160_000 { break }
        }
        let result = GeometryExport.validatedOBJ(vertices:vertices,triangles:triangles)
        return (result.data,result.triangleCount)
    }
}
