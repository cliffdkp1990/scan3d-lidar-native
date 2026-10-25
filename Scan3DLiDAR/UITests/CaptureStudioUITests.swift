import XCTest

/// Native UI with explicit synthetic test input; no camera/LiDAR hardware claim.
final class CaptureStudioUITests:XCTestCase {
    override func setUpWithError()throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
    }
    private func launch(dark:Bool=false,large:Bool=false)->XCUIApplication {
        let app=XCUIApplication()
        app.launchEnvironment["SCAN3D_STUDIO_FIXTURE"]="1"
        app.launchEnvironment["SCAN3D_QUALITY_SCENARIO"]=dark ? "dark" : "ready"
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["studio-fixture-label"].waitForExistence(timeout:20))
        return app
    }
    private func screenshot(_ title:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=title;attachment.lifetime = .keepAlways;add(attachment)
    }
    func testPortraitCameraAndLibrary()throws {
        let app=launch()
        XCTAssertTrue(app.staticTexts["Indfang formen."].exists)
        XCTAssertTrue(app.buttons["Mine scanninger"].isHittable)
        screenshot("camera-studio-portrait-SYNTHETIC")
        app.buttons["Mine scanninger"].tap()
        XCTAssertTrue(app.navigationBars["Mine scanninger"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["SIMULATOR — TESTDATA"].waitForExistence(timeout:10))
        screenshot("native-library-SYNTHETIC")
    }
    func testActualStoredGeometryRendererAndControls()throws {
        let app=launch()
        app.buttons["Resultat og eksport"].tap()
        let open=app.buttons["Se seneste gemte 3D-data"]
        for _ in 0..<3 { if open.isHittable { break };app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout:10));open.tap()
        XCTAssertTrue(app.staticTexts["Målt LiDAR-mesh"].waitForExistence(timeout:20))
        XCTAssertFalse(app.staticTexts["Kan ikke vise 3D-filen"].exists)
        let viewport=app.otherElements["geometry-viewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout:10))
        let before=viewport.value as? String
        app.buttons["Zoom ind"].tap()
        XCTAssertNotEqual(viewport.value as? String,before)
        app.buttons["Drej modellen til højre"].tap()
        screenshot("actual-realitykit-viewer-SYNTHETIC")
        app.buttons["Nulstil 3D-visning"].tap()
        XCTAssertTrue((viewport.value as? String)?.contains("1.0") == true || (viewport.value as? String)?.contains("1,0") == true)
    }
    func testDarkImageGuidance()throws {
        let app=launch(dark:true)
        XCTAssertTrue(app.staticTexts["capture-guidance"].label.contains("mangler lys"))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Mere lys"].waitForExistence(timeout:10))
        screenshot("dark-image-guidance-SYNTHETIC")
    }
    func testLandscapeAndLargeText()throws {
        let app=launch(large:true)
        XCTAssertTrue(app.buttons["Mine scanninger"].isHittable)
        screenshot("camera-studio-large-text-SYNTHETIC")
        app.terminate()
        let normal=launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(normal.staticTexts["studio-fixture-label"].waitForExistence(timeout:10))
        XCTAssertTrue(normal.buttons["Mine scanninger"].isHittable)
        screenshot("camera-studio-landscape-SYNTHETIC")
    }
}
