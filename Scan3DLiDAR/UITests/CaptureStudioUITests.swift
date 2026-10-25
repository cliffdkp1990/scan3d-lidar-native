import XCTest

/// Native UI with explicit synthetic test input; no camera/LiDAR hardware claim.
final class CaptureStudioUITests:XCTestCase {
    override func setUpWithError()throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
    }
    private func launch(dark:Bool=false,large:Bool=false,scenario:String?=nil)->XCUIApplication {
        let app=XCUIApplication()
        app.launchEnvironment["SCAN3D_STUDIO_FIXTURE"]="1"
        app.launchEnvironment["SCAN3D_QUALITY_SCENARIO"]=scenario ?? (dark ? "dark" : "ready")
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["studio-fixture-label"].waitForExistence(timeout:20))
        return app
    }
    private func screenshot(_ title:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=title;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func assertWithinWidth(_ element:XCUIElement,in app:XCUIApplication,file:StaticString=#filePath,line:UInt=#line) {
        let window=app.windows.firstMatch.frame, frame=element.frame
        XCTAssertGreaterThan(frame.width,0,file:file,line:line)
        XCTAssertGreaterThanOrEqual(frame.minX,window.minX-1,file:file,line:line)
        XCTAssertLessThanOrEqual(frame.maxX,window.maxX+1,file:file,line:line)
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<10 {
            let frame=element.frame, window=app.windows.firstMatch.frame
            if frame.height>0 && frame.minY>=window.minY+30 && frame.maxY<=window.maxY-30 { return }
            app.swipeUp()
        }
        XCTFail("Control could not be reached by vertical scrolling: \(element.identifier)")
    }
    func testPortraitCameraAndLibrary()throws {
        let app=launch()
        XCTAssertTrue(app.staticTexts["Indfang formen."].exists)
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width,390,"Full native display; no legacy launch-screen letterboxing")
        XCTAssertTrue(app.buttons["Mine scanninger"].isHittable)
        assertWithinWidth(app.buttons["Resultat og eksport"],in:app)
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
        screenshot("actual-realitykit-viewer-default-SYNTHETIC")
        let before=viewport.value as? String
        app.buttons["Zoom ind"].tap()
        XCTAssertNotEqual(viewport.value as? String,before)
        app.buttons["Drej modellen til højre"].tap()
        screenshot("actual-realitykit-viewer-SYNTHETIC")
        app.buttons["Nulstil 3D-visning"].tap()
        XCTAssertTrue((viewport.value as? String)?.contains("1.0") == true || (viewport.value as? String)?.contains("1,0") == true)
        let reset=viewport.value as? String
        viewport.pinch(withScale:0.8,velocity:-0.5)
        XCTAssertNotEqual(viewport.value as? String,reset)
        let pinched=viewport.value as? String
        viewport.swipeRight()
        XCTAssertNotEqual(viewport.value as? String,pinched)
        app.buttons["Nulstil 3D-visning"].tap()
        screenshot("actual-realitykit-viewer-reset-SYNTHETIC")
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
        assertWithinWidth(app.staticTexts["Indfang formen."],in:app)
        assertWithinWidth(app.buttons["Resultat og eksport"],in:app)
        screenshot("camera-studio-large-text-SYNTHETIC")
        reveal(app.buttons["capture-photo"],in:app)
        assertWithinWidth(app.buttons["capture-photo"],in:app)
        screenshot("camera-studio-large-text-controls-SYNTHETIC")
        app.terminate()
        let normal=launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in normal.windows.firstMatch.frame.width>normal.windows.firstMatch.frame.height },object:nil)
        wait(for:[rotated],timeout:10)
        XCTAssertTrue(normal.staticTexts["studio-fixture-label"].waitForExistence(timeout:10))
        XCTAssertTrue(normal.buttons["Mine scanninger"].isHittable)
        assertWithinWidth(normal.buttons["Resultat og eksport"],in:normal)
        assertWithinWidth(normal.buttons["capture-photo"],in:normal)
        screenshot("camera-studio-landscape-SYNTHETIC")
    }
    func testPermissionAndInterruptionGuidance()throws {
        let denied=launch(scenario:"denied")
        XCTAssertTrue(denied.buttons["Åbn kameraindstillinger"].isHittable)
        screenshot("camera-permission-guidance-SYNTHETIC")
        denied.terminate()
        let interrupted=launch(scenario:"interrupted")
        XCTAssertTrue(interrupted.staticTexts["Kameraet er afbrudt. Gemte optagelser er bevaret."].waitForExistence(timeout:10))
        XCTAssertFalse(interrupted.buttons["Åbn kameraindstillinger"].exists)
    }
}
