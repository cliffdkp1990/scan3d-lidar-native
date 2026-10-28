import Foundation

var count=0
func check(_ condition:Bool,_ description:String) {
    precondition(condition,description)
    count += 1
}
let choice = LiDARDepthFallbackPolicy.choose
check(choice(true,true) == .smoothedSceneDepth,"prefer a validated smoothed measurement")
check(choice(true,false) == .smoothedSceneDepth,"smoothed center alone is enough")
check(choice(false,true) == .sceneDepth,"raw valid center rescues rejected smoothed map")
check(choice(false,false) == nil,"two invalid sensors never invent depth")
check(LiDARDepthOrigin.sceneDepth.rawValue == "sceneDepth","report discrete source exactly")
check(LiDARDepthOrigin.smoothedSceneDepth.rawValue == "smoothedSceneDepth","report averaged source exactly")
print("PASS \(count)/\(count) portable ARKit depth fallback policy checks")
