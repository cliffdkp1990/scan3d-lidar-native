import Foundation

/// One on-demand, read-only snapshot. Never includes images, camera coordinates,
/// location, device identifiers, Apple credentials, or project file paths.
/// The result proves only that an ARKit sensor pipeline reported data at snapshot time.
struct Scan3DSensorDiagnostic {
    let fixture: Bool
    let supportsLiDAR: Bool
    let cameraAuthorized: Bool
    let scanning: Bool
    let recentFrame: Bool
    let depthMode: String
    let depthResolution: String
    let confidenceMap: Bool
    let trackingNormal: Bool
    let centerDepthMeters: Double?
    let centerSupportedSamples: Int
    let savedPhotos: Int
    let savedPoints: Int

    var verdict: String {
        if fixture { return "TESTMOTIV: Ingen fysisk LiDAR-test" }
        if !supportsLiDAR { return "LiDAR understøttes ikke på enheden" }
        if !cameraAuthorized { return "Kameraadgang mangler" }
        if !scanning { return "Kameraet er ikke i gang" }
        if !recentFrame { return "Ingen ny ARKit-frame: kontroller kameraet" }
        if depthMode == "ingen" { return "ARKit leverer ingen dybdedata" }
        if !confidenceMap { return "Dybdekvalitet kan ikke verificeres" }
        if !trackingNormal { return "Sporingen er ikke stabil" }
        if centerDepthMeters == nil || centerSupportedSamples < 1 {
            return "Dybden mod centrum er usikker"
        }
        return "ARKit modtager målt LiDAR-dybde"
    }

    var report: String {
        func status(_ value: Bool) -> String { value ? "JA" : "NEJ" }
        let distance = centerDepthMeters.map { String(format: "%.2f m", $0) } ?? "ingen gyldig måling"
        return [
            "Scan3D - iPhone LiDAR-selvtest v1",
            "Resultat: \(verdict)",
            "Syntetisk simulator-test: \(status(fixture))",
            "LiDAR-kapacitet: \(status(supportsLiDAR))",
            "Kameratilladelse: \(status(cameraAuthorized))",
            "Scanning aktiv: \(status(scanning))",
            "Ny fysisk ARKit-frame: \(status(recentFrame && !fixture))",
            "Dybdekilde: \(fixture ? "simulator (ingen sensor)" : depthMode)",
            "Dybdemålingens opløsning: \(fixture ? "ikke relevant" : depthResolution)",
            "Confidence-map: \(status(confidenceMap && !fixture))",
            "Stabil ARKit-sporing: \(status(trackingNormal && !fixture))",
            "Centerafstand: \(fixture ? "simulator, ikke målt" : distance)",
            "Støttede centersamples: \(fixture ? 0 : centerSupportedSamples)/25",
            "Gemte fotos i aktiv mission: \(savedPhotos)",
            "Gemte målte LiDAR-punkter: \(fixture ? 0 : savedPoints)",
            "Bemærk: ingen foto, lokation eller projektfiler sendes automatisk.",
            "Dette beviser ikke kalibreret nøjagtighed, tæt mesh eller 3D-printbarhed."
        ].joined(separator: "\n")
    }
}
