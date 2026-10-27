import Foundation

// Pure Swift geometry, independent of ARKit. Angles refer to the relative AR session axes.
struct ScanPoint: Equatable {
    let x: Double
    let y: Double
    let z: Double
    static func -(lhs: ScanPoint, rhs: ScanPoint) -> ScanPoint {
        ScanPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    var length: Double { sqrt(x*x + y*y + z*z) }
    var horizontalLength: Double { hypot(x, z) }
    func dot(_ other: ScanPoint) -> Double { x*other.x + y*other.y + z*other.z }
}

struct ScanSlot: Equatable {
    let ring: Int // 0 low, 1 middle, 2 high
    let sector: Int // 0...11
    var index: Int { ring*12+sector }
    var label: String {
        let names = ["NEDE", "MIDTE", "OPPE"]
        return "\(names[ring]) · vinkel \(sector+1)/12"
    }
}

struct ScanFeedback {
    let slot: ScanSlot
    let distance: Double
    let centerAngleDegrees: Double
    let ready: Bool
    let instruction: String
}

enum MissionGeometry {
    static func slot(camera: ScanPoint, target: ScanPoint) -> ScanSlot? {
        guard camera.finite, target.finite else { return nil }
        let delta = camera-target
        let radius = delta.horizontalLength
        guard radius.isFinite, radius >= 0.12 else { return nil }
        var azimuth = atan2(delta.x, delta.z)
        if azimuth < 0 { azimuth += 2 * .pi }
        let sector = min(11, Int((azimuth / (2 * .pi))*12))
        let threshold = max(0.11, radius*0.22)
        let ring = delta.y > threshold ? 2 : delta.y < -threshold ? 0 : 1
        return ScanSlot(ring: ring, sector: sector)
    }

    static func evaluate(camera: ScanPoint, forward: ScanPoint, target: ScanPoint,
                         trackingGood: Bool, still: Bool) -> ScanFeedback? {
        guard camera.finite, forward.finite, target.finite,
              let slot = slot(camera: camera, target: target) else { return nil }
        let toward = target-camera
        let distance = toward.length
        guard distance.isFinite, forward.length > 0.001 else { return nil }
        let denom = max(0.0001, forward.length*distance)
        let cosine = min(1.0, max(-1.0, forward.dot(toward)/denom))
        let angle = acos(cosine)*180.0 / .pi
        let message: String
        if !trackingGood { message = "Vent på stabil ARKit-sporing." }
        else if distance < 0.30 { message = "Gå lidt tilbage fra genstanden." }
        else if distance > 2.20 { message = "Gå tættere på genstanden." }
        else if angle > 12 { message = "Drej kameraet mod den låste genstand." }
        else if !still { message = "Hold telefonen helt stille et øjeblik." }
        else { message = "Klar til foto – \(slot.label)." }
        return ScanFeedback(slot: slot, distance: distance, centerAngleDegrees: angle,
                            ready: trackingGood && still && distance >= 0.30 && distance <= 2.20 && angle <= 12,
                            instruction: message)
    }

    static func nextUncovered(after current: Int?, covered: Set<Int>) -> ScanSlot? {
        let base = current ?? -1
        for delta in 1...36 {
            let index = (base+delta) % 36
            if !covered.contains(index) { return ScanSlot(ring: index/12, sector: index%12) }
        }
        return nil
    }
}


// V11: Guidance is always relative to the locked AR session target, NOT GPS or survey-grade LiDAR.
struct MissionNavigation: Equatable {
    let target: ScanSlot
    let message: String
    let stepCount: Int
}

enum MissionRoute {
    static func nearestUncovered(from current: ScanSlot, covered: Set<Int>) -> ScanSlot? {
        let candidates = (0..<36).filter { !covered.contains($0) }
        guard !candidates.isEmpty else { return nil }
        func score(_ index: Int) -> Int {
            let ring = index / 12, sector = index % 12
            let clockwise = (sector-current.sector+12) % 12
            let reverse = (current.sector-sector+12) % 12
            return abs(ring-current.ring)*14 + min(clockwise,reverse)*2
        }
        let index = candidates.min {
            score($0) == score($1) ? $0 < $1 : score($0) < score($1)
        }!
        return ScanSlot(ring:index/12, sector:index%12)
    }

    static func navigate(from current: ScanSlot, covered: Set<Int>) -> MissionNavigation? {
        guard let next = nearestUncovered(from:current, covered:covered) else { return nil }
        return navigateTo(from: current, target: next)
    }

    static func navigateTo(from current: ScanSlot, target next: ScanSlot) -> MissionNavigation {
        if next == current {
            return MissionNavigation(target:next, message:"Du står ved næste fotoposition. Ret kameraet mod genstanden, og hold telefonen stille.", stepCount:0)
        }
        let clockwise = (next.sector-current.sector+12)%12
        let anticlockwise = (current.sector-next.sector+12)%12
        var steps: [String] = []
        if next.ring != current.ring {
            steps.append(next.ring > current.ring ? "Hæv kameraet til næste højde" : "Sænk kameraet til næste højde")
        }
        if clockwise != 0 {
            if clockwise <= anticlockwise { steps.append("Gå cirka \(clockwise*30)° med uret rundt om genstanden") }
            else { steps.append("Gå cirka \(anticlockwise*30)° mod uret rundt om genstanden") }
        }
        steps.append("Bevar afstanden og peg på genstanden")
        return MissionNavigation(target:next, message:steps.joined(separator:". ")+". Mål: \(next.label).", stepCount:min(clockwise,anticlockwise))
    }
}


// V12: pure policy for explicit retakes. No LiDAR or ARKit dependency.
enum MissionRetake {
    static func select(slot: Int, covered: Set<Int>) -> Int? {
        guard (0..<36).contains(slot), covered.contains(slot) else { return nil }
        return slot
    }

    static func canCapture(slot: Int, covered: Set<Int>, retake: Int?, cameraReady: Bool) -> Bool {
        guard cameraReady, (0..<36).contains(slot) else { return false }
        if covered.contains(slot) { return retake == slot }
        // When a retake is requested, never take an unrelated new image by mistake.
        return retake == nil
    }
}


// V2: Capture approval must be recomputed against the exact ARFrame being saved.
// Previous UI readiness must not authorize a later frame at a different angle.
enum CaptureValidation {
    static func approve(camera: ScanPoint, forward: ScanPoint, target: ScanPoint,
                        trackingGood: Bool, heldSteady: Bool, expectedSlot: Int?,
                        covered: Set<Int>, retake: Int?) -> ScanFeedback? {
        guard trackingGood, heldSteady, let expectedSlot = expectedSlot else { return nil }
        guard let fresh = MissionGeometry.evaluate(camera: camera, forward: forward,
            target: target, trackingGood: trackingGood, still: heldSteady),
              fresh.ready, fresh.slot.index == expectedSlot,
              MissionRetake.canCapture(slot: fresh.slot.index, covered: covered,
                                       retake: retake, cameraReady: fresh.ready) else { return nil }
        return fresh
    }
}
