import CoreVideo
import Foundation

/// Camera-plane adapter shared by the app and actual CoreVideo regression tests.
enum LumaBufferSampler {
    /// Read only a bounded central luma grid, not the entire full-resolution image.
    static func analyze(_ buffer: CVPixelBuffer) -> LumaQuality? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let fullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard fullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        let width=CVPixelBufferGetWidthOfPlane(buffer,0), height=CVPixelBufferGetHeightOfPlane(buffer,0)
        let stride=CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
        guard width >= 32, height >= 32, stride >= width,
              let pointer=CVPixelBufferGetBaseAddressOfPlane(buffer,0)?.assumingMemoryBound(to:UInt8.self) else { return nil }
        let side=96
        var values: [UInt8]=[]
        values.reserveCapacity(side*side)
        for y in 0..<side {
            for x in 0..<side {
                let px=min(width-1, width/5 + x*(width*3/5)/side)
                let py=min(height-1, height/5 + y*(height*3/5)/side)
                let raw=Int(pointer[py*stride+px])
                values.append(fullRange ? UInt8(raw) : UInt8(min(255,max(0,(raw-16)*255/219))))
            }
        }
        return LumaQuality.measure(values,width:side)
    }
}
