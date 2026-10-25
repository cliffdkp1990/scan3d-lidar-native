import CoreVideo
import Foundation

var count=0
func check(_ ok:Bool,_ message:String) { guard ok else { fatalError("FAIL: \(message)") }; count += 1 }
let black=Array(repeating:UInt8(0),count:96*96)
let white=Array(repeating:UInt8(255),count:96*96)
let flat=Array(repeating:UInt8(128),count:96*96)
let checker=(0..<(96*96)).map { UInt8((($0%96)/4+($0/96)/4)%2==0 ? 70:180) }
check(LumaQuality.measure(black,width:96)?.condition == .tooDark,"near-black image is rejected")
check(LumaQuality.measure(white,width:96)?.condition == .tooBright,"clipped image is rejected")
check(LumaQuality.measure(flat,width:96)?.condition == .lowDetail,"flat matte surface is not called out-of-focus")
check(LumaQuality.measure(flat,width:96)?.condition.allowsCapture == true,"low texture remains usable for LiDAR")
check(LumaQuality.measure(checker,width:96)?.condition == .ready,"structured, well-lit image")
check(LumaQuality.measure([1,2],width:2)==nil,"invalid dimensions")
check(LumaQuality.measure(black,width:Int.max)==nil,"hostile width cannot overflow")
check(!PhotoCondition.unavailable.allowsCapture,"unknown image quality cannot approve auto photo")
check(!PhotoCondition.tooDark.allowsCapture && !PhotoCondition.tooBright.allowsCapture,"bad exposure blocks auto photo")
let depth=DepthQuality.estimate(depths:Array(repeating:0.72,count:25),confidence:Array(repeating:2,count:25))
check(depth?.meters == 0.72 && depth?.supportedSamples == 25,"coherent high-confidence center")
check(DepthQuality.estimate(depths:Array(repeating:0.72,count:25),confidence:Array(repeating:0,count:25))==nil,"low-confidence depth not invented")
check(DepthQuality.estimate(depths:Array(repeating:.nan,count:25),confidence:Array(repeating:2,count:25))==nil,"nonfinite depth")
check(DepthQuality.estimate(depths:[Float](repeating:0.7,count:8),confidence:[UInt8](repeating:2,count:8))==nil,"sparse patch")
check(DepthQuality.estimate(depths:[Float](repeating:0.5,count:12)+[Float](repeating:1.5,count:13),confidence:[UInt8](repeating:2,count:25))==nil,"foreground-background depth edge")
check(DepthQuality.estimate(depths:[1],confidence:[])==nil,"mismatched confidence")
check(DepthQuality.supportsPoint(0.72,neighbours:[0.71,0.72,0.73,0.72]),"coherent point")
check(!DepthQuality.supportsPoint(0.5,neighbours:[1,1,1,1]),"isolated depth spike")
check(!DepthQuality.supportsPoint(0.5,neighbours:[0.5,.nan]),"insufficient neighbour support")
check(DepthQuality.unproject(x:100,y:50,depth:1,fx:200,fy:200,cx:100,cy:50)==CloudVertex(x:0,y:0,z:-1),"optical center")
check(DepthQuality.unproject(x:120,y:30,depth:1,fx:200,fy:200,cx:100,cy:50)==CloudVertex(x:0.1,y:0.1,z:-1),"intrinsics account for principal-point offset")
check(DepthQuality.unproject(x:0,y:0,depth:1,fx:0,fy:1,cx:0,cy:0)==nil,"invalid focal length")
let f=ScanPoint(x:0,y:0,z:-1), right=ScanPoint(x:1,y:0,z:0)
check(CaptureMotion.angularRate(from:f,to:f,interval:0.1)<0.0001,"no rotation")
check(CaptureMotion.angularRate(from:f,to:right,interval:1)>1.5,"rotation detected even without translation")
check(!CaptureMotion.held(linear:0.01,angular:0.3),"rotational blur prevention")
check(CaptureMotion.held(linear:0.03,angular:0.02),"stable handheld pose")
check(!CaptureMotion.held(linear:.nan,angular:0),"invalid movement")
check(CaptureMotion.fresh(qualityTime:10,frameTime:10.7),"fresh quality result")
check(!CaptureMotion.fresh(qualityTime:10,frameTime:11),"stale quality result")
check(!CaptureMotion.fresh(qualityTime:11,frameTime:10),"future result cannot approve earlier frame")
let project=UUID(), generation=UUID()
var lifecycle=PhotoCaptureLifecycle()
let request=lifecycle.begin(projectID:project,slot:4,generation:generation)!
check(lifecycle.begin(projectID:project,slot:5,generation:generation)==nil,"one high-resolution request at a time")
check(!lifecycle.finish(PhotoRequestToken(id:UUID(),projectID:project,slot:4,generation:generation)),"late unrelated callback ignored")
check(lifecycle.finish(request),"matching request finishes")
check(!lifecycle.finish(request),"duplicate callback ignored")
check(lifecycle.begin(projectID:project,slot:40,generation:generation)==nil,"invalid capture position")
let collector=PointCollector(resolution:0.02,maxPoints:1)
collector.add(CloudVertex(x:0.002,y:0,z:0),target:nil)
collector.add(CloudVertex(x:0.008,y:0,z:0),target:nil)
check(abs(collector.snapshot()[0].x-0.005)<0.0001,"repeated points denoised even at capacity")
collector.add(CloudVertex(x:1,y:0,z:0),target:nil)
check(collector.count==1,"point budget retained")
collector.add(CloudVertex(x:Float.greatestFiniteMagnitude,y:0,z:0),target:nil)
check(collector.count==1,"voxel coordinate overflow rejected")
check(PointCollector(resolution:0).resolution > 0,"invalid voxel spacing normalized")

// Actual CoreVideo buffers, including padded rows and both luma ranges.
func pixelBuffer(_ format:OSType,value:UInt8)throws->CVPixelBuffer {
    var result:CVPixelBuffer?
    let options=[kCVPixelBufferBytesPerRowAlignmentKey:128] as CFDictionary
    let code=CVPixelBufferCreate(kCFAllocatorDefault,322,242,format,options,&result)
    guard code==kCVReturnSuccess,let result else { throw NSError(domain:"CoreVideo fixture",code:Int(code)) }
    CVPixelBufferLockBaseAddress(result,[])
    defer { CVPixelBufferUnlockBaseAddress(result,[]) }
    if CVPixelBufferGetPlaneCount(result)>0 {
        let bytes=CVPixelBufferGetBytesPerRowOfPlane(result,0)*CVPixelBufferGetHeightOfPlane(result,0)
        memset(CVPixelBufferGetBaseAddressOfPlane(result,0),Int32(value),bytes)
    }
    return result
}
let full=try pixelBuffer(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,value:128)
check(LumaBufferSampler.analyze(full)?.mean==128,"real full-range luma plane with padded rows")
let videoBlack=try pixelBuffer(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,value:16)
check(LumaBufferSampler.analyze(videoBlack)?.condition == .tooDark,"video-range black normalizes to zero")
let videoWhite=try pixelBuffer(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,value:235)
check(LumaBufferSampler.analyze(videoWhite)?.condition == .tooBright,"video-range white normalizes to 255")
print("PASS \(count)/\(count) image planes, capture quality, depth confidence, motion, lifecycle and denoising")
