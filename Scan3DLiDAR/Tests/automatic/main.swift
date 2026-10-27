import Foundation
var assertions = 0
func check(_ ok: Bool, _ message: String) {
    guard ok else { fatalError("FAIL: \(message)") }
    assertions += 1
}
var policy = AutomaticCapture()
func attempt(enabled: Bool = true, running: Bool = true, suspended: Bool = false,
             saving: Bool = false, ready: Bool = true, slot: Int? = 12,
             covered: Set<Int> = [], retake: Int? = nil, time: Double = 1) -> Bool {
    policy.shouldCapture(enabled: enabled, running: running, suspended: suspended,
        saving: saving, ready: ready, slot: slot, covered: covered, retake: retake, timestamp: time)
}
check(!attempt(enabled: false), "manual mode")
check(!attempt(running: false), "paused camera")
check(!attempt(suspended: true), "library, export, inactive app")
check(!attempt(saving: true), "save in flight")
check(!attempt(ready: false), "quality not approved")
check(!attempt(slot: nil), "missing position")
check(!attempt(slot: 36), "invalid position")
check(!attempt(covered: [12]), "no duplicate")
check(!attempt(retake: 12), "retake requires manual confirmation")
check(!attempt(time: .nan), "invalid clock")
check(attempt(), "stable new position triggers")
check(!attempt(slot: 13, time: 1.5), "rate bounded even at new position")
check(!attempt(time: 0.5), "clock rollback blocked")
check(attempt(slot: 13, time: 2.3), "next stable new position")
check(!attempt(slot: 13, covered: [12, 13], time: 5), "saved position stays blocked")
policy.reset()
check(attempt(time: 0), "new coordinate session resets scheduling")
print("PASS \(assertions)/\(assertions) - automatic photo scheduling")
