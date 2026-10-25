import CoreVideo
import Foundation
import simd

/// The same depth/confidence buffer reader is used by ARKit capture and CoreVideo regression tests.
enum DepthBufferSampler {
    private struct Maps {
        let width:Int, height:Int, depthStride:Int, confidenceStride:Int
        let depth:UnsafePointer<Float32>, confidence:UnsafePointer<UInt8>
        func supported(_ x:Int,_ y:Int)->Float? {
            let c=confidence[y*confidenceStride+x], z=depth[y*depthStride+x]
            return c >= 1 && c <= 2 && z.isFinite && z >= 0.22 && z <= 2.5 ? z:nil
        }
    }

    /// Keep all pointer access inside the successful, paired CoreVideo locks.
    private static func read<T>(_ depth:CVPixelBuffer,_ confidence:CVPixelBuffer,_ body:(Maps)->T)->T? {
        let width=CVPixelBufferGetWidth(depth), height=CVPixelBufferGetHeight(depth)
        guard CVPixelBufferGetPixelFormatType(depth)==kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence)==kCVPixelFormatType_OneComponent8,
              !CVPixelBufferIsPlanar(depth), !CVPixelBufferIsPlanar(confidence),
              width >= 5, height >= 5,
              width==CVPixelBufferGetWidth(confidence), height==CVPixelBufferGetHeight(confidence) else { return nil }
        let depthBytes=CVPixelBufferGetBytesPerRow(depth), confidenceBytes=CVPixelBufferGetBytesPerRow(confidence)
        guard depthBytes/MemoryLayout<Float32>.size >= width, depthBytes%MemoryLayout<Float32>.size==0,
              confidenceBytes >= width else { return nil }
        guard CVPixelBufferLockBaseAddress(depth,.readOnly)==kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(depth,.readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence,.readOnly)==kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(confidence,.readOnly) }
        guard let d=CVPixelBufferGetBaseAddress(depth)?.assumingMemoryBound(to:Float32.self),
              let c=CVPixelBufferGetBaseAddress(confidence)?.assumingMemoryBound(to:UInt8.self) else { return nil }
        return body(Maps(width:width,height:height,depthStride:depthBytes/MemoryLayout<Float32>.size,
                         confidenceStride:confidenceBytes,depth:UnsafePointer(d),confidence:UnsafePointer(c)))
    }

    static func center(depth:CVPixelBuffer,confidence:CVPixelBuffer)->DepthEstimate? {
        let result:DepthEstimate?? = read(depth,confidence) { maps in
            var depths:[Float]=[], confidences:[UInt8]=[]
            for y in (maps.height/2-2)...(maps.height/2+2) { for x in (maps.width/2-2)...(maps.width/2+2) {
                depths.append(maps.depth[y*maps.depthStride+x])
                confidences.append(maps.confidence[y*maps.confidenceStride+x])
            }}
            return DepthQuality.estimate(depths:depths,confidence:confidences)
        }
        return result ?? nil
    }

    /// Intrinsics reference the captured image in native sensor orientation, not the rotated JPEG.
    static func worldPoint(x:Float,y:Float,depth:Float,intrinsics:simd_float3x3,
                           imageSize:SIMD2<Float>,mapSize:SIMD2<Float>,transform:simd_float4x4)->CloudVertex? {
        guard valid(intrinsics:intrinsics,imageSize:imageSize,transform:transform),
              mapSize.x.isFinite, mapSize.y.isFinite, mapSize.x > 0, mapSize.y > 0,
              let p=DepthQuality.unproject(x:x,y:y,depth:depth,
                fx:intrinsics[0,0]*mapSize.x/imageSize.x,fy:intrinsics[1,1]*mapSize.y/imageSize.y,
                cx:intrinsics[2,0]*mapSize.x/imageSize.x,cy:intrinsics[2,1]*mapSize.y/imageSize.y) else { return nil }
        let world=simd_mul(transform,SIMD4<Float>(p.x,p.y,p.z,1))
        let point=CloudVertex(x:world.x,y:world.y,z:world.z)
        return point.finite ? point:nil
    }

    private static func valid(intrinsics:simd_float3x3,imageSize:SIMD2<Float>,transform:simd_float4x4)->Bool {
        guard imageSize.x.isFinite,imageSize.y.isFinite,imageSize.x > 0,imageSize.y > 0,
              intrinsics[0,0].isFinite,intrinsics[1,1].isFinite,intrinsics[2,0].isFinite,intrinsics[2,1].isFinite,
              intrinsics[0,0] > 0,intrinsics[1,1] > 0 else { return false }
        for column in 0..<4 { for row in 0..<4 where !transform[column,row].isFinite { return false } }
        return abs(transform[0,3])<0.0001 && abs(transform[1,3])<0.0001 && abs(transform[2,3])<0.0001 && abs(transform[3,3]-1)<0.0001
    }

    static func sample(depth:CVPixelBuffer,confidence:CVPixelBuffer,intrinsics:simd_float3x3,
                       imageSize:SIMD2<Float>,transform:simd_float4x4,
                       into collector:PointCollector,target:CloudVertex?)->Int {
        guard valid(intrinsics:intrinsics,imageSize:imageSize,transform:transform), target?.finite != false else { return 0 }
        return read(depth,confidence) { maps in
            let sx=Float(maps.width)/imageSize.x, sy=Float(maps.height)/imageSize.y
            let fx=intrinsics[0,0]*sx, fy=intrinsics[1,1]*sy, cx=intrinsics[2,0]*sx, cy=intrinsics[2,1]*sy
            guard fx.isFinite,fy.isFinite,cx.isFinite,cy.isFinite,fx > 0,fy > 0 else { return 0 }
            let before=collector.count
            for y in stride(from:1,to:maps.height-1,by:2) { for x in stride(from:1,to:maps.width-1,by:2) {
                guard let z=maps.supported(x,y) else { continue }
                let neighbours=[maps.supported(x-1,y),maps.supported(x+1,y),maps.supported(x,y-1),maps.supported(x,y+1)].compactMap{$0}
                guard DepthQuality.supportsPoint(z,neighbours:neighbours),
                      let p=DepthQuality.unproject(x:Float(x),y:Float(y),depth:z,fx:fx,fy:fy,cx:cx,cy:cy) else { continue }
                let world=simd_mul(transform,SIMD4<Float>(p.x,p.y,p.z,1))
                collector.add(CloudVertex(x:world.x,y:world.y,z:world.z),target:target)
                // At capacity, still process observations of existing voxels; no new cells are allocated.
            }}
            return collector.count-before
        } ?? 0
    }
}
