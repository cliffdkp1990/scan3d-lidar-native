import ARKit
import CoreImage
import CoreVideo
import ImageIO
import UIKit

enum CameraImageQuality {
    static func jpeg(_ buffer:CVPixelBuffer, orientation:CGImagePropertyOrientation, context:CIContext) throws -> (data:Data,width:Int,height:Int) {
        let input=CIImage(cvPixelBuffer:buffer).oriented(orientation)
        guard let color=CGColorSpace(name:CGColorSpace.sRGB),
              let image=context.createCGImage(input,from:input.extent,format:.RGBA8,colorSpace:color) else { throw ProjectStoreError.emptyFile }
        let data=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil) else { throw ProjectStoreError.emptyFile }
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.95,kCGImagePropertyOrientation:1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ProjectStoreError.emptyFile }
        return (data as Data,image.width,image.height)
    }
    static func analyze(_ buffer:CVPixelBuffer)->LumaQuality? { LumaBufferSampler.analyze(buffer) }
    static func orientation(_ interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interface {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        default: return .right
        }
    }
}

enum LiDARFrameQuality {
    static func center(_ frame: ARFrame) -> DepthEstimate? {
        guard let data=frame.smoothedSceneDepth ?? frame.sceneDepth, let confidence=data.confidenceMap else { return nil }
        let buffer=data.depthMap
        let width=CVPixelBufferGetWidth(buffer), height=CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              width >= 5, height >= 5, CVPixelBufferGetWidth(confidence)==width, CVPixelBufferGetHeight(confidence)==height else { return nil }
        CVPixelBufferLockBaseAddress(buffer,.readOnly); CVPixelBufferLockBaseAddress(confidence,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly); CVPixelBufferUnlockBaseAddress(confidence,.readOnly) }
        guard let z=CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to:Float32.self),
              let c=CVPixelBufferGetBaseAddress(confidence)?.assumingMemoryBound(to:UInt8.self) else { return nil }
        let row=CVPixelBufferGetBytesPerRow(buffer)/MemoryLayout<Float32>.size
        let cr=CVPixelBufferGetBytesPerRow(confidence)
        guard row >= width, cr >= width else { return nil }
        var depths:[Float]=[], confidences:[UInt8]=[]
        for y in (height/2-2)...(height/2+2) { for x in (width/2-2)...(width/2+2) {
            depths.append(z[y*row+x]); confidences.append(c[y*cr+x])
        }}
        return DepthQuality.estimate(depths:depths,confidence:confidences)
    }
}
