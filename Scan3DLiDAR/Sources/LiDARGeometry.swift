import ARKit
import Foundation
import Metal
import simd

/// Converts real ARFrame smoothedSceneDepth pixels into ARKit world-space points.
/// Camera intrinsics and capture image dimensions are accounted for; results remain approximate.
enum LiDARDepthSampler {
    static func sample(frame: ARFrame, into collector: PointCollector, target: CloudVertex?) -> Int {
        guard let depth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return 0 }
        let buffer = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return 0 }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return 0 }
        let imW = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let imH = Float(CVPixelBufferGetHeight(frame.capturedImage))
        let fx = frame.camera.intrinsics[0,0] * Float(width) / imW
        let fy = frame.camera.intrinsics[1,1] * Float(height) / imH
        let cx = frame.camera.intrinsics[2,0] * Float(width) / imW
        let cy = frame.camera.intrinsics[2,1] * Float(height) / imH
        guard fx.isFinite, fy.isFinite, fx > 1, fy > 1 else { return 0 }
        let confidence = depth.confidenceMap
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        }
        guard let raw = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let depths = raw.assumingMemoryBound(to: Float32.self)
        let depthStride = CVPixelBufferGetBytesPerRow(buffer)/MemoryLayout<Float32>.size
        let conf = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }?.assumingMemoryBound(to: UInt8.self)
        let confStride = confidence.map(CVPixelBufferGetBytesPerRow) ?? 0
        let before = collector.count
        // Every 3rd pixel: many viewpoints, limited memory and CPU use on the phone.
        for y in stride(from: 1, to: height-1, by: 3) {
            for x in stride(from: 1, to: width-1, by: 3) {
                let z = depths[y*depthStride+x]
                guard z.isFinite, z >= 0.22, z <= 2.5 else { continue }
                if let conf, conf[y*confStride+x] < 1 { continue }
                // ARKit camera looks along -Z; camera image pixel Y is downward.
                let pos = SIMD4<Float>((Float(x)-cx)*z/fx, -(Float(y)-cy)*z/fy, -z, 1)
                let world = simd_mul(frame.camera.transform, pos)
                collector.add(CloudVertex(x:world.x, y:world.y, z:world.z), target:target)
                if collector.count >= collector.maxPoints { return collector.count-before }
            }
        }
        return collector.count-before
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
        return (GeometryExport.obj(vertices:vertices,triangles:triangles),triangles.count)
    }
}
