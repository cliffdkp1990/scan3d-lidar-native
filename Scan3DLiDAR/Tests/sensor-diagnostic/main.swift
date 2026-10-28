import Foundation

func check(_ value: Bool, _ reason: String) {
    precondition(value, reason)
}
func diagnostic(fixture: Bool = false, supported: Bool = true, permission: Bool = true,
                running: Bool = true, recent: Bool = true, depth: String = "smoothedSceneDepth",
                confidence: Bool = true, tracking: Bool = true, center: Double? = 0.65,
                samples: Int = 23) -> Scan3DSensorDiagnostic {
    Scan3DSensorDiagnostic(fixture: fixture, supportsLiDAR: supported,
        cameraAuthorized: permission, scanning: running, recentFrame: recent,
        depthMode: depth, depthResolution: "256x192", confidenceMap: confidence,
        trackingNormal: tracking, centerDepthMeters: center,
        centerSupportedSamples: samples, savedPhotos: 4, savedPoints: 1900)
}
let healthy = diagnostic()
check(healthy.verdict == "ARKit modtager målt LiDAR-dybde", "Real pipeline not detected")
check(healthy.report.contains("Ny fysisk ARKit-frame: JA"), "Missing real frame")
check(healthy.report.contains("Centerafstand: 0.65 m"), "Distance lost")
let checks: [(String, Scan3DSensorDiagnostic, String)] = [
    ("fixture",diagnostic(fixture:true),"TESTMOTIV"),
    ("unsupported",diagnostic(supported:false),"understøttes ikke"),
    ("permission",diagnostic(permission:false),"Kameraadgang"),
    ("stopped",diagnostic(running:false),"ikke i gang"),
    ("stale",diagnostic(recent:false),"Ingen ny ARKit-frame"),
    ("no-depth",diagnostic(depth:"ingen"),"ingen dybdedata"),
    ("no-confidence",diagnostic(confidence:false),"ikke verificeres"),
    ("tracking",diagnostic(tracking:false),"ikke stabil"),
    ("center",diagnostic(center:nil),"usikker"),
    ("samples",diagnostic(samples:0),"usikker")
]
for (name,value,expected) in checks {
    check(value.verdict.contains(expected), "Unexpected verdict for \(name): \(value.verdict)")
    check(!value.verdict.contains("modtager målt"), "False positive for \(name)")
}
let fixture = diagnostic(fixture:true)
check(fixture.report.contains("Ny fysisk ARKit-frame: NEJ"), "Simulator claimed real ARKit")
check(fixture.report.contains("Gemte målte LiDAR-punkter: 0"), "Simulator claimed physical cloud")
check(!fixture.report.contains("0.65 m"), "Simulator leaked synthetic distance as physical")
check(!healthy.report.lowercased().contains("udid"), "Report must not collect device IDs")
print("11 diagnostic conditions and privacy safeguards passed")
