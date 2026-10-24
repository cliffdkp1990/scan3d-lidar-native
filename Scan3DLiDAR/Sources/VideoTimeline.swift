import Foundation

/// Only accepted frames advance the timeline. AR timestamps never become wall
/// clock dates; recording starts at zero and cannot run backwards or beyond 5 min.
struct VideoTimeline {
    let frameRate = 15.0
    let maximumDuration = 300.0
    private(set) var firstTimestamp: Double?
    private(set) var lastTimestamp: Double?
    private(set) var frames = 0

    mutating func accept(_ timestamp: Double) -> Double? {
        guard timestamp.isFinite, timestamp >= 0 else { return nil }
        if let last = lastTimestamp, timestamp - last < 1.0 / frameRate - 0.000_001 { return nil }
        let relative = timestamp - (firstTimestamp ?? timestamp)
        guard relative >= 0, relative < maximumDuration else { return nil }
        if firstTimestamp == nil { firstTimestamp = timestamp }
        lastTimestamp = timestamp
        frames += 1
        return relative
    }
    func reachedLimit(_ timestamp: Double) -> Bool {
        guard timestamp.isFinite, let start = firstTimestamp else { return false }
        return timestamp - start >= maximumDuration
    }
    var duration: Double {
        guard let first = firstTimestamp, let last = lastTimestamp else { return 0 }
        return last - first + 1.0 / frameRate
    }
}
