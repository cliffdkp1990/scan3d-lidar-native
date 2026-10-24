import Foundation

/// Scheduling only. The exact AR frame must still pass CaptureValidation.
/// Timers cannot approve a photo; a new, stable, uncovered position is required.
struct AutomaticCapture {
    private var lastAttempt: TimeInterval?
    mutating func reset() { lastAttempt = nil }
    mutating func shouldCapture(enabled: Bool, running: Bool, suspended: Bool,
                                saving: Bool, ready: Bool, slot: Int?,
                                covered: Set<Int>, retake: Int?, timestamp: TimeInterval) -> Bool {
        guard enabled, running, !suspended, !saving, ready, timestamp.isFinite,
              let slot = slot, (0..<36).contains(slot), retake == nil,
              !covered.contains(slot) else { return false }
        // Conservative interval also bounds failed-frame retries and disk pressure.
        if let last = lastAttempt, timestamp < last || timestamp - last < 1.2 { return false }
        lastAttempt = timestamp
        return true
    }
}
