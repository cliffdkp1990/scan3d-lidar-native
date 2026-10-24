import Foundation
var assertions = 0
func check(_ ok: Bool, _ message: String) {
    guard ok else { fatalError("FAIL: \(message)") }
    assertions += 1
}
let target = ScanPoint(x:0,y:0,z:0)
let center = ScanPoint(x:0,y:0,z:1)
let forward = ScanPoint(x:0,y:0,z:-1)
func accept(camera:ScanPoint=center, look:ScanPoint=forward,
            tracking:Bool=true, steady:Bool=true, expected:Int?=12,
            covered:Set<Int>=[], retake:Int?=nil) -> Bool {
    CaptureValidation.approve(camera:camera,forward:look,target:target,
        trackingGood:tracking,heldSteady:steady,expectedSlot:expected,
        covered:covered,retake:retake) != nil
}
check(accept(),"stable new capture accepted")
check(!accept(steady:false),"moving denied")
check(!accept(tracking:false),"tracking loss denied")
check(!accept(expected:13),"stale expected index denied")
check(!accept(expected:nil),"missing expected slot denied")
check(!accept(camera:.init(x:1,y:0,z:0),look:.init(x:-1,y:0,z:0)),"new camera angle denied")
check(!accept(look:.init(x:0,y:0,z:1)),"looking away denied")
check(!accept(camera:.init(x:0,y:0,z:3)),"distance denied")
check(!accept(covered:[12]),"duplicate denied")
check(accept(covered:[12],retake:12),"selected retake accepted")
check(!accept(covered:[12],retake:13),"wrong selected retake denied")
check(!accept(covered:[],retake:13),"new photo when retaking another position denied")
check(MissionGeometry.slot(camera:.init(x:Double.nan,y:0,z:1),target:target) == nil,"nan position rejected")
check(MissionGeometry.evaluate(camera:center,forward:.init(x:Double.nan,y:0,z:0),target:target,trackingGood:true,still:true) == nil,"nan forward rejected")
check(MissionGeometry.evaluate(camera:center,forward:.init(x:0,y:0,z:0),target:target,trackingGood:true,still:true) == nil,"zero forward rejected")
print("PASS \(assertions)/\(assertions) - fresh capture frame validation and data safety")
