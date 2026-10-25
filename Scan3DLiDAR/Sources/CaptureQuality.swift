import Foundation

enum PhotoCondition: String, Equatable {
    case ready, lowDetail, tooDark, tooBright, unavailable
    var allowsCapture: Bool { self == .ready || self == .lowDetail }
    var title: String {
        switch self {
        case .ready: return "Konturer fundet"
        case .lowDetail: return "Få detaljer"
        case .tooDark: return "Mere lys"
        case .tooBright: return "For lyst"
        case .unavailable: return "Analyserer"
        }
    }
    var guidance: String {
        switch self {
        case .ready: return "Billedets lys og konturer kan bruges."
        case .lowDetail: return "Få billeddetaljer. LiDAR kan stadig bruges; prøv en anden vinkel."
        case .tooDark: return "Der mangler lys. Lys genstanden jævnt op."
        case .tooBright: return "Store dele af billedet er meget lyse. Undgå genskin og direkte lys."
        case .unavailable: return "Venter på en frisk billedkontrol."
        }
    }
}

/// Heuristics on sampled image luminance, not a calibrated focus/photography score.
struct LumaQuality: Equatable {
    let mean: Double
    let deviation: Double
    let edgeEnergy: Double
    let darkFraction: Double
    let brightFraction: Double
    var condition: PhotoCondition {
        if mean < 28 && darkFraction > 0.65 { return .tooDark }
        if mean > 237 && brightFraction > 0.70 { return .tooBright }
        if deviation < 8 || edgeEnergy < 2.5 { return .lowDetail }
        return .ready
    }
    static func measure(_ samples: [UInt8], width: Int) -> LumaQuality? {
        guard width >= 3, width <= 512, samples.count >= width * 3, samples.count % width == 0,
              samples.count <= 200_000 else { return nil }
        let n = Double(samples.count)
        let mean = samples.reduce(0.0) { $0 + Double($1) } / n
        let variance = samples.reduce(0.0) { $0 + pow(Double($1)-mean,2) } / n
        let height = samples.count / width
        var edges = 0.0
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                let i = y*width+x
                edges += abs(Double(samples[i-1]) + Double(samples[i+1]) + Double(samples[i-width]) + Double(samples[i+width]) - 4*Double(samples[i]))
            }
        }
        return LumaQuality(mean:mean, deviation:sqrt(variance), edgeEnergy:edges/Double((width-2)*(height-2)),
            darkFraction:Double(samples.filter { $0 < 12 }.count)/n,
            brightFraction:Double(samples.filter { $0 > 245 }.count)/n)
    }
}

struct DepthEstimate: Equatable {
    let meters: Float
    let supportedSamples: Int
    let spread: Float
}

enum DepthQuality {
    /// Require medium/high ARKit confidence and a coherent central patch.
    static func estimate(depths: [Float], confidence: [UInt8]) -> DepthEstimate? {
        guard depths.count == confidence.count, depths.count <= 100 else { return nil }
        let values = zip(depths,confidence).filter { $0.0.isFinite && $0.0 >= 0.22 && $0.0 <= 2.5 && $0.1 >= 1 && $0.1 <= 2 }.map { $0.0 }.sorted()
        guard values.count >= 9 else { return nil }
        let median = values[values.count/2]
        let spread = values[(values.count*3)/4] - values[values.count/4]
        guard spread <= max(0.035,median*0.04) else { return nil }
        return DepthEstimate(meters:median,supportedSamples:values.count,spread:spread)
    }
    static func supportsPoint(_ center: Float, neighbours: [Float]) -> Bool {
        guard center.isFinite, center >= 0.22, center <= 2.5 else { return false }
        let valid = neighbours.filter { $0.isFinite && $0 >= 0.22 && $0 <= 2.5 }.sorted()
        guard valid.count >= 3 else { return false }
        return abs(center-valid[valid.count/2]) <= max(0.025,center*0.025)
    }
    static func unproject(x: Float, y: Float, depth: Float, fx: Float, fy: Float, cx: Float, cy: Float) -> CloudVertex? {
        guard [x,y,depth,fx,fy,cx,cy].allSatisfy(\.isFinite), depth > 0, fx > 0, fy > 0 else { return nil }
        return CloudVertex(x:(x-cx)*depth/fx,y:-(y-cy)*depth/fy,z:-depth)
    }
}

enum CaptureMotion {
    static func angularRate(from a: ScanPoint, to b: ScanPoint, interval: Double) -> Double {
        guard a.finite, b.finite, interval.isFinite, interval > 0, a.length.isFinite, b.length.isFinite,
              a.length > 0.001, b.length > 0.001 else { return .infinity }
        let cosine = min(1,max(-1,a.dot(b)/(a.length*b.length)))
        return acos(cosine)/interval
    }
    static func held(linear: Double, angular: Double) -> Bool {
        linear.isFinite && angular.isFinite && linear >= 0 && linear < 0.10 && angular >= 0 && angular < 0.18
    }
    static func fresh(qualityTime: Double?, frameTime: Double, maximumAge: Double = 0.8) -> Bool {
        guard let time=qualityTime, time.isFinite, frameTime.isFinite else { return false }
        return frameTime >= time && frameTime-time <= maximumAge
    }
}

/// One requested photo at a time; a delayed callback cannot publish another project.
struct PhotoRequestToken: Equatable {
    let id: UUID
    let projectID: UUID
    let slot: Int
    let generation: UUID
}

struct PhotoCaptureLifecycle {
    private(set) var active: PhotoRequestToken?
    mutating func begin(projectID: UUID, slot: Int, generation: UUID) -> PhotoRequestToken? {
        guard active == nil, (0..<36).contains(slot) else { return nil }
        let token=PhotoRequestToken(id:UUID(),projectID:projectID,slot:slot,generation:generation)
        active=token
        return token
    }
    mutating func finish(_ token: PhotoRequestToken) -> Bool {
        guard active == token else { return false }
        active=nil
        return true
    }
}
