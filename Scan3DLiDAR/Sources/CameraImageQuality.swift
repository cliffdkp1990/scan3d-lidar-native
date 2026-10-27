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
        return DepthBufferSampler.center(depth:data.depthMap,confidence:confidence)
    }
}
