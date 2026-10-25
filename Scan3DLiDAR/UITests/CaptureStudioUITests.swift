import XCTest
import UIKit

/// Native UI with explicit synthetic test input; no camera/LiDAR hardware claim.
final class CaptureStudioUITests:XCTestCase {
    override func setUpWithError()throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
    }
    private func launch(dark:Bool=false,large:Bool=false,scenario:String?=nil,dense:Bool=false)->XCUIApplication {
        let app=XCUIApplication()
        app.launchEnvironment["SCAN3D_STUDIO_FIXTURE"]="1"
        app.launchEnvironment["SCAN3D_QUALITY_SCENARIO"]=scenario ?? (dark ? "dark" : "ready")
        app.launchEnvironment["SCAN3D_DENSE_CLOUD_FIXTURE"]=dense ? "1":"0"
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["studio-fixture-label"].waitForExistence(timeout:20))
        return app
    }
    private func screenshot(_ title:String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=title;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func moveInsideViewport(_ viewport:XCUIElement,in app:XCUIApplication,fast:Bool) {
        let window=app.windows.firstMatch, windowFrame=window.frame, frame=viewport.frame
        let origin=window.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
        let start=origin.withOffset(CGVector(dx:frame.minX+frame.width*(fast ? 0.25:0.7)-windowFrame.minX,
                                           dy:frame.midY-windowFrame.minY))
        let end=origin.withOffset(CGVector(dx:frame.minX+frame.width*(fast ? 0.75:0.35)-windowFrame.minX,
                                         dy:frame.midY-windowFrame.minY))
        XCTAssertTrue(frame.contains(start.screenPoint));XCTAssertTrue(frame.contains(end.screenPoint))
        // Anchor the physical path to the stable window, while the model's accessibility value changes.
        if fast { start.press(forDuration:0.01,thenDragTo:end,withVelocity:.fast,thenHoldForDuration:0) }
        else { start.press(forDuration:0.2,thenDragTo:end) }
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
    private func viewportPixels(_ viewport:XCUIElement)->(background:Double,teal:Int)? {
        guard viewport.exists,let region=viewport.screenshot().image.cgImage,
              region.width>=100,region.height>=100 else { return nil }
        let side=160
        var pixels=[UInt8](repeating:0,count:side*side*4)
        let drawn=pixels.withUnsafeMutableBytes { bytes->Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(region,in:CGRect(x:0,y:0,width:side,height:side));return true
        }
        guard drawn else { return nil }
        var luminance:[Int]=[],teal=0
        for index in stride(from:0,to:pixels.count,by:4) {
            let r=Int(pixels[index]), g=Int(pixels[index+1]), b=Int(pixels[index+2])
            luminance.append((r+g+b)/3)
            if g-r>20 && b-r>20 { teal += 1 }
        }
        luminance.sort()
        return (Double(luminance[luminance.count/2]),teal)
    }
    func testActualDensePointCloud()throws {
        let app=launch(dense:true)
        app.buttons["Resultat og eksport"].tap()
        let open=app.buttons["Se seneste gemte 3D-data"]
        for _ in 0..<3 { if open.isHittable { break };app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout:10));open.tap()
        XCTAssertTrue(app.staticTexts["Målte LiDAR-punkter"].waitForExistence(timeout:30))
        let pointCount=app.staticTexts["stored-point-count"]
        XCTAssertTrue(pointCount.waitForExistence(timeout:10))
        // SwiftUI formats integers for the user's locale (for example 48,000 or 48.000).
        XCTAssertEqual(pointCount.label.filter(\.isNumber),"4800020000",pointCount.label)
        XCTAssertFalse(app.staticTexts["Kan ikke vise 3D-filen"].exists)
        let viewport=app.descendants(matching:.any).matching(identifier:"geometry-viewport").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout:10))
        let drawn=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in (self.viewportPixels(viewport)?.teal ?? 0)>50 },object:nil)
        wait(for:[drawn],timeout:20)
        let darkPixels=try XCTUnwrap(viewportPixels(viewport))
        let darkPoints=darkPixels.teal,darkBrightness=darkPixels.background
        XCTAssertLessThan(darkBrightness,100,"Dark canvas renders dark pixels")
        screenshot("actual-point-cloud-dark-SYNTHETIC")
        let before=viewport.value as? String
        app.buttons["Zoom ind"].tap()
        XCTAssertNotEqual(viewport.value as? String,before)
        app.buttons["Nulstil 3D-visning"].tap()
        let background=app.buttons["geometry-light-background"]
        XCTAssertTrue(background.isHittable)
        XCTAssertGreaterThanOrEqual(background.frame.height,44,"The background choice has a complete touch target")
        background.tap()
        let switched=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in background.value as? String == "Valgt" },object:nil)
        wait(for:[switched],timeout:10)
        let bright=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in (self.viewportPixels(viewport)?.background ?? 0)>200 },object:nil)
        wait(for:[bright],timeout:10)
        XCTAssertTrue(viewport.exists,"Viewport keeps its semantic identifier after appearance changes")
        let lightPixels=try XCTUnwrap(viewportPixels(viewport))
        let lightBrightness=lightPixels.background,lightPoints=lightPixels.teal
        XCTAssertGreaterThan(lightPoints,50,"Teal points remain visible on the light canvas")
        print("POINTCLOUD_CANVAS measured dark=\(darkBrightness), light=\(lightBrightness); visible teal pixels dark=\(darkPoints), light=\(lightPoints); synthetic 48000 saved, 20000 displayed")
        screenshot("actual-point-cloud-light-SYNTHETIC")
        app.buttons["geometry-dark-background"].tap()
        let darkAgain=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in (self.viewportPixels(viewport)?.background ?? 255)<100 },object:nil)
        wait(for:[darkAgain],timeout:10)
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
        let viewport=app.descendants(matching:.any).matching(identifier:"geometry-viewport").firstMatch
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
        print("VIEWPORT_BEFORE_SWIPE frame=\(viewport.frame) value=\(String(describing:pinched))")
        moveInsideViewport(viewport,in:app,fast:true)
        let debug=XCTAttachment(string:app.debugDescription);debug.name="native-hierarchy-after-swipe";debug.lifetime = .keepAlways;add(debug)
        let swiped=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in viewport.value as? String != pinched },object:nil)
        wait(for:[swiped],timeout:3)
        let afterSwipe=viewport.value as? String
        moveInsideViewport(viewport,in:app,fast:false)
        let dragged=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in viewport.value as? String != afterSwipe },object:nil)
        wait(for:[dragged],timeout:8)
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
        reveal(app.staticTexts["studio-distance"],in:app)
        XCTAssertEqual(app.staticTexts["studio-distance"].label,"Afstand: ≈ 0,72 m")
        assertWithinWidth(app.staticTexts["studio-distance"],in:app)
        screenshot("camera-studio-large-text-facts-SYNTHETIC")
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
