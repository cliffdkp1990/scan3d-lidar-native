import XCTest
import simd
@testable import Scan3DLiDAR

/// Pure geometry checks. Simulator cannot prove real LiDAR surface fidelity.
final class SurfacePreviewTests: XCTestCase {
    func testAngleBreakDistinguishesCornersFromSimilarPlanes() {
        let front = SIMD3<Float>(0, 0, 1)
        let same = simd_normalize(SIMD3<Float>(0.1, 0, 1))
        let rightAngle = SIMD3<Float>(1, 0, 0)
        XCTAssertFalse(SurfacePreviewProjector.hasAngleBreak(front, same))
        XCTAssertTrue(SurfacePreviewProjector.hasAngleBreak(front, rightAngle))
        XCTAssertFalse(SurfacePreviewProjector.hasAngleBreak(front, -front))
    }

    func testSurfaceModesAndEmptyPreview() {
        XCTAssertEqual(SurfaceVisualizationMode.allCases.count, 3)
        XCTAssertEqual(SurfaceVisualizationMode.natural.label, "Naturlig")
        XCTAssertEqual(SurfaceVisualizationMode.surfaces.label, "Flader")
        XCTAssertEqual(SurfaceVisualizationMode.wireframe.label, "Trådnet")
        XCTAssertTrue(SurfacePreviewFrame.empty.isEmpty)
    }
}
