import CoreImage
import CoreVideo
import ImageIO
import UIKit
import XCTest
@testable import Scan3DLiDAR

/// Real CoreVideo -> CoreImage -> ImageIO output, without a physical sensor claim.
final class CameraImageTests:XCTestCase {
    private func buffer()throws->CVPixelBuffer {
        var value:CVPixelBuffer?
        let result=CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,nil,&value)
        let image=try XCTUnwrap(value)
        XCTAssertEqual(result,kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(image,[])
        defer { CVPixelBufferUnlockBaseAddress(image,[]) }
        let y=try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(image,0)).assumingMemoryBound(to:UInt8.self)
        let row=CVPixelBufferGetBytesPerRowOfPlane(image,0)
        for py in 0..<240 { for px in 0..<320 { y[py*row+px]=UInt8(45 + px/3 + py/4) } }
        memset(CVPixelBufferGetBaseAddressOfPlane(image,1),128,CVPixelBufferGetBytesPerRowOfPlane(image,1)*CVPixelBufferGetHeightOfPlane(image,1))
        return image
    }
    func testActualJPEGEncodingForAllInterfaceOrientations()throws {
        let source=try buffer()
        let context=CIContext()
        for orientation in [UIInterfaceOrientation.portrait,.portraitUpsideDown,.landscapeLeft,.landscapeRight] {
            let encoded=try CameraImageQuality.jpeg(source,orientation:CameraImageQuality.orientation(orientation),context:context)
            let image=try XCTUnwrap(CGImageSourceCreateWithData(encoded.data as CFData,nil))
            XCTAssertEqual(CGImageSourceGetCount(image),1)
            let decoded=try XCTUnwrap(CGImageSourceCreateImageAtIndex(image,0,nil))
            let portrait=orientation == .portrait || orientation == .portraitUpsideDown
            XCTAssertEqual(encoded.width,portrait ? 240:320)
            XCTAssertEqual(encoded.height,portrait ? 320:240)
            XCTAssertEqual(decoded.width,encoded.width);XCTAssertEqual(decoded.height,encoded.height)
            XCTAssertGreaterThan(encoded.data.count,1000)
            let metadata=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [String:Any])
            XCTAssertEqual((metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1,1,"Pixels already oriented; no double rotation")
            XCTAssertEqual(metadata[kCGImagePropertyColorModel as String] as? String,"RGB")
        }
    }
    func testActualFrameQualityAdapterAcceptsTheEncodedSource()throws {
        let measured=try XCTUnwrap(CameraImageQuality.analyze(try buffer()))
        XCTAssertTrue(measured.condition.allowsCapture)
        XCTAssertGreaterThan(measured.mean,30)
        XCTAssertLessThan(measured.mean,230)
    }
}
