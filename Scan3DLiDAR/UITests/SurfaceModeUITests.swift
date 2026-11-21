import XCTest

/// Verify the actual segmented visualization control with synthetic Simulator
/// input. This does not claim any physical LiDAR coverage or precision.
final class SurfaceModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testAllThreeSurfaceModesRemainSelectableWithoutPhysicalLiDAR() {
        let app = XCUIApplication()
        app.launchEnvironment["SCAN3D_STUDIO_FIXTURE"] = "1"
        app.launchEnvironment["SCAN3D_QUALITY_SCENARIO"] = "ready"
        app.launch()
        XCTAssertTrue(app.staticTexts["studio-fixture-label"].waitForExistence(timeout: 20))

        let modes = app.segmentedControls["studio-surface-mode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        let natural = modes.buttons["Naturlig"]
        let surfaces = modes.buttons["Flader"]
        let wireframe = modes.buttons["Trådnet"]

        XCTAssertTrue(natural.isSelected, "The original camera is the default")
        XCTAssertTrue(surfaces.exists)
        XCTAssertTrue(wireframe.exists)

        surfaces.tap()
        XCTAssertTrue(surfaces.isSelected)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Flader vises, når målet")
        ).firstMatch.exists, "Synthetic input must not fabricate measured surfaces")

        wireframe.tap()
        XCTAssertTrue(wireframe.isSelected)
        XCTAssertTrue(app.staticTexts["studio-fixture-label"].exists)

        natural.tap()
        XCTAssertTrue(natural.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "studio-camera").firstMatch.exists)
    }
}
