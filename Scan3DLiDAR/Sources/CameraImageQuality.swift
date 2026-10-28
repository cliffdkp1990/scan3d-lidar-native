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

/// Same depth source and same confidence check for locking a target and
/// generating its points. A present but invalid smoothed map does not prevent
/// a fallback to the *same frame's* raw, confidence-validated sceneDepth.
struct LiDARFrameDepthSelection {
    let data: ARDepthData
    let estimate: DepthEstimate
    let origin: LiDARDepthOrigin
}

enum LiDARFrameQuality {
    private static func validatedCenter(_ data: ARDepthData?) -> DepthEstimate? {
        guard let data, let confidence=data.confidenceMap else { return nil }
        return DepthBufferSampler.center(depth:data.depthMap,confidence:confidence)
    }

    static func selected(_ frame: ARFrame) -> LiDARFrameDepthSelection? {
        let smoothed=frame.smoothedSceneDepth
        let goodSmoothed=validatedCenter(smoothed)
        // No second buffer lock or validation unless the smoothed map failed.
        let raw=goodSmoothed == nil ? frame.sceneDepth : nil
        let goodRaw=goodSmoothed == nil ? validatedCenter(raw) : nil
        switch LiDARDepthFallbackPolicy.choose(
            smoothedCenterValid:goodSmoothed != nil,
            rawCenterValid:goodRaw != nil) {
        case .smoothedSceneDepth:
            guard let data=smoothed,let estimate=goodSmoothed else { return nil }
            return LiDARFrameDepthSelection(data:data,estimate:estimate,origin:.smoothedSceneDepth)
        case .sceneDepth:
            guard let data=raw,let estimate=goodRaw else { return nil }
            return LiDARFrameDepthSelection(data:data,estimate:estimate,origin:.sceneDepth)
        case nil:
            return nil
        }
    }

    static func center(_ frame: ARFrame) -> DepthEstimate? {
        selected(frame)?.estimate
    }
}
