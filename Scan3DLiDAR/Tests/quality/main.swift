import CoreVideo
import Foundation
import simd

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

// Actual scalar CoreVideo maps -> calibrated world points -> collector -> PLY -> reader.
// Poisoned row padding makes a width/stride error observable rather than a self-checking formula.
func scalarBuffer(_ format:OSType,width:Int=7,height:Int=7)throws->CVPixelBuffer {
    var result:CVPixelBuffer?
    let options=[kCVPixelBufferBytesPerRowAlignmentKey:64] as CFDictionary
    let code=CVPixelBufferCreate(kCFAllocatorDefault,width,height,format,options,&result)
    guard code==kCVReturnSuccess,let result else { throw NSError(domain:"Depth fixture",code:Int(code)) }
    return result
}
func setDepth(_ buffer:CVPixelBuffer,_ value:(Int,Int)->Float) {
    check(CVPixelBufferLockBaseAddress(buffer,[])==kCVReturnSuccess,"depth fixture lock")
    defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
    let row=CVPixelBufferGetBytesPerRow(buffer)/MemoryLayout<Float>.size
    let pointer=CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:Float.self)
    for y in 0..<CVPixelBufferGetHeight(buffer) { for x in 0..<row {
        pointer[y*row+x]=x<CVPixelBufferGetWidth(buffer) ? value(x,y):.nan
    }}
}
func setConfidence(_ buffer:CVPixelBuffer,_ value:UInt8) {
    check(CVPixelBufferLockBaseAddress(buffer,[])==kCVReturnSuccess,"confidence fixture lock")
    defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
    let row=CVPixelBufferGetBytesPerRow(buffer)
    let pointer=CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self)
    for y in 0..<CVPixelBufferGetHeight(buffer) { for x in 0..<row {
        pointer[y*row+x]=x<CVPixelBufferGetWidth(buffer) ? value:255
    }}
}
let depthMap=try scalarBuffer(kCVPixelFormatType_DepthFloat32)
let confidenceMap=try scalarBuffer(kCVPixelFormatType_OneComponent8)
setDepth(depthMap) { _,_ in 1 };setConfidence(confidenceMap,2)
check(CVPixelBufferGetBytesPerRow(depthMap)>7*MemoryLayout<Float>.size,"fixture really has padded depth rows")
check(CVPixelBufferGetBytesPerRow(confidenceMap)>7,"fixture really has padded confidence rows")
check(DepthBufferSampler.center(depth:depthMap,confidence:confidenceMap)?.supportedSamples==25,"actual coherent center patch ignores padding")
let calibration=simd_float3x3(columns:(SIMD3<Float>(14,0,0),SIMD3<Float>(0,14,0),SIMD3<Float>(7,7,1)))
let imageSize=SIMD2<Float>(14,14), mapSize=SIMD2<Float>(7,7)
func sampleDepth(_ collector:PointCollector,pose:simd_float4x4=matrix_identity_float4x4,target:CloudVertex?=nil)->Int {
    DepthBufferSampler.sample(depth:depthMap,confidence:confidenceMap,intrinsics:calibration,
        imageSize:imageSize,transform:pose,into:collector,target:target)
}
func near(_ a:CloudVertex,_ b:CloudVertex)->Bool { a.distanceSquared(to:b)<0.00000001 }
let actualCloud=PointCollector()
check(sampleDepth(actualCloud)==9,"nine actual interior depth pixels produce nine points")
check(actualCloud.snapshot().contains { near($0,CloudVertex(x:-2.5/7,y:2.5/7,z:-1)) },"native sensor top-left is negative X, positive Y, negative Z")
let roundTrip=try GeometryPreview.parse(GeometryExport.ply(points:actualCloud.snapshot()),extension:"ply")
check(roundTrip.vertices.count==9,"actual buffers survive persisted PLY parsing")
check(abs(roundTrip.sizeMeters.x-4/7)<0.0001 && abs(roundTrip.sizeMeters.y-4/7)<0.0001 && roundTrip.sizeMeters.z==0,"known planar geometry keeps expected metric extents")
var pose=matrix_identity_float4x4
pose.columns.0=SIMD4<Float>(0,0,-1,0);pose.columns.2=SIMD4<Float>(1,0,0,0);pose.columns.3=SIMD4<Float>(2,3,4,1)
let moved=PointCollector()
check(sampleDepth(moved,pose:pose)==9,"rotated and translated camera preserves all supported samples")
check(moved.snapshot().contains { near($0,CloudVertex(x:1,y:3+2.5/7,z:4+2.5/7)) },"independent 90-degree camera rotation and translation give expected world coordinates")
let centerWorld=DepthBufferSampler.worldPoint(x:3.5,y:3.5,depth:1,intrinsics:calibration,imageSize:imageSize,mapSize:mapSize,transform:pose)
check(centerWorld.map { near($0,CloudVertex(x:1,y:3,z:4)) }==true,"target lock shares the tested depth/camera calibration")
let doubled=simd_float3x3(columns:(SIMD3<Float>(28,0,0),SIMD3<Float>(0,28,0),SIMD3<Float>(14,14,1)))
let hiResWorld=DepthBufferSampler.worldPoint(x:3.5,y:3.5,depth:1,intrinsics:doubled,imageSize:SIMD2<Float>(28,28),mapSize:mapSize,transform:pose)
check(hiResWorld==centerWorld,"image resolution and matching intrinsics can change without changing physical scale")
let roi=PointCollector()
check(sampleDepth(roi,target:CloudVertex(x:0,y:0,z:-1))==9,"default target ROI keeps the known small plane")
let saturated=PointCollector(resolution:1,maxPoints:1)
check(sampleDepth(saturated)==1 && saturated.count==1,"point budget stays bounded")
check(near(saturated.snapshot()[0],CloudVertex(x:-1.5/7,y:1.5/7,z:-1)),"later observations refine an existing voxel after the budget is reached")
setConfidence(confidenceMap,0)
check(DepthBufferSampler.center(depth:depthMap,confidence:confidenceMap)==nil,"actual unsupported confidence patch never locks a target")
check(sampleDepth(PointCollector())==0,"actual low-confidence map never generates points")
setConfidence(confidenceMap,255)
check(sampleDepth(PointCollector())==0,"unknown confidence codes are rejected")
setConfidence(confidenceMap,2)
setDepth(depthMap) { x,y in x==3 && y==3 ? 2:1 }
let spike=PointCollector();_=sampleDepth(spike)
check(spike.count==8 && spike.snapshot().allSatisfy { abs($0.z+1)<0.0001 },"isolated depth spike is absent from actual saved geometry")
setDepth(depthMap) { x,_ in x<3 ? 0.6:1 }
check(DepthBufferSampler.center(depth:depthMap,confidence:confidenceMap)==nil,"actual foreground/background cliff cannot approve target center")
let cliff=PointCollector();_=sampleDepth(cliff)
check(cliff.count==9 && cliff.snapshot().allSatisfy { abs($0.z+0.6)<0.0001 || abs($0.z+1)<0.0001 },"both measured planes survive without an interpolated bridge")
let mismatch=try scalarBuffer(kCVPixelFormatType_OneComponent8,width:9)
setConfidence(mismatch,2)
check(DepthBufferSampler.center(depth:depthMap,confidence:mismatch)==nil,"mismatched actual confidence dimensions are refused")
let invalidFormat=try scalarBuffer(kCVPixelFormatType_32BGRA)
check(DepthBufferSampler.center(depth:invalidFormat,confidence:confidenceMap)==nil,"BGRA bytes are never read as float depth")
setDepth(depthMap) { _,_ in 1 }
var invalidPose=matrix_identity_float4x4;invalidPose[3,0] = .nan
check(sampleDepth(PointCollector(),pose:invalidPose)==0,"nonfinite camera pose cannot create geometry")
invalidPose=matrix_identity_float4x4;invalidPose[3,3]=0
check(sampleDepth(PointCollector(),pose:invalidPose)==0,"invalid homogeneous camera transform is refused")
var invalidCalibration=calibration;invalidCalibration[0,0]=0
check(DepthBufferSampler.worldPoint(x:3,y:3,depth:1,intrinsics:invalidCalibration,imageSize:imageSize,mapSize:mapSize,transform:pose)==nil,"invalid focal calibration cannot lock a target")
let invalidROI=PointCollector()
check(sampleDepth(invalidROI,target:CloudVertex(x:.nan,y:0,z:0))==0,"invalid ROI cannot bypass the spatial filter")
invalidROI.add(CloudVertex(x:0,y:0,z:0),target:nil,radius:.nan)
check(invalidROI.count==0,"invalid ROI radius cannot disable bounded sampling")

// Regression: an available but corrupt/low-confidence smoothed map must not
// suppress a good raw ARKit map. Test with actual *separately allocated*
// CoreVideo buffers, not synthetic bool flags alone.
let rawDepthMap=try scalarBuffer(kCVPixelFormatType_DepthFloat32)
let rawConfidenceMap=try scalarBuffer(kCVPixelFormatType_OneComponent8)
setDepth(depthMap) { _,_ in .nan };setConfidence(confidenceMap,2)
setDepth(rawDepthMap) { _,_ in 0.8 };setConfidence(rawConfidenceMap,2)
func selectedDepth() -> DepthBufferSampler.Selected? {
    DepthBufferSampler.selected(
        smoothedDepth:depthMap,smoothedConfidence:confidenceMap,
        rawDepth:rawDepthMap,rawConfidence:rawConfidenceMap)
}
let rescued=selectedDepth()
check(rescued?.origin == .sceneDepth && abs((rescued?.center.meters ?? 0)-0.8)<0.0001,
      "real raw depth recovers when present smoothed depth is NaN")
let rescuedCloud=PointCollector()
if let source=rescued {
    let n=DepthBufferSampler.sample(depth:source.depth,confidence:source.confidence,
        intrinsics:calibration,imageSize:imageSize,transform:matrix_identity_float4x4,
        into:rescuedCloud,target:nil)
    check(n==9 && rescuedCloud.snapshot().allSatisfy { abs($0.z+0.8)<0.0001 },
          "real sampled points use the identical raw source as center distance")
} else { check(false,"raw rescue must supply concrete buffers") }
setDepth(depthMap) { _,_ in 1 }
let smoothed=selectedDepth()
check(smoothed?.origin == .smoothedSceneDepth && smoothed?.center.meters == 1,
      "verified smoothed source still wins when both maps are valid")
if let source=smoothed {
    let cloud=PointCollector()
    let n=DepthBufferSampler.sample(depth:source.depth,confidence:source.confidence,
        intrinsics:calibration,imageSize:imageSize,transform:matrix_identity_float4x4,
        into:cloud,target:nil)
    check(n==9 && cloud.snapshot().allSatisfy { abs($0.z+1)<0.0001 },
          "smoothed center and point-cloud geometry match exactly")
} else { check(false,"valid smoothed source must supply concrete buffers") }
setConfidence(confidenceMap,0)
check(selectedDepth()?.origin == .sceneDepth,"low-confidence smoothed data falls back to measured raw")
setConfidence(rawConfidenceMap,0)
check(selectedDepth()==nil,"both low-confidence sources fail closed")
setConfidence(rawConfidenceMap,255)
check(selectedDepth()==nil,"unknown raw confidence levels never approve a scan")
setDepth(rawDepthMap) { _,_ in 0.8 };setConfidence(rawConfidenceMap,2)
check(DepthBufferSampler.selected(smoothedDepth:depthMap,smoothedConfidence:nil,
    rawDepth:rawDepthMap,rawConfidence:rawConfidenceMap)?.origin == .sceneDepth,
    "missing smoothed confidence does not hide good raw data")
check(DepthBufferSampler.selected(smoothedDepth:nil,smoothedConfidence:nil,
    rawDepth:nil,rawConfidence:nil)==nil,"missing both sensor maps never creates a target")
check(DepthBufferSampler.selected(smoothedDepth:depthMap,smoothedConfidence:confidenceMap,
    rawDepth:rawDepthMap,rawConfidence:mismatch)?.origin == nil,
    "smoothed and raw invalid/mismatched dimensions cannot be silently mixed")

print("PASS \(count)/\(count) image planes, actual depth buffers, camera calibration, metric exports, capture quality and lifecycle")
