import Foundation
var count = 0
func check(_ ok: Bool, _ message: String) {
    guard ok else { fatalError("TEST FEJLEDE: \(message)") }
    count += 1
}
let cloud = PointCollector(resolution:0.02,maxPoints:3)
let zero = CloudVertex(x:0,y:0,z:0)
cloud.add(zero,target:nil)
check(cloud.count == 1,"første punkt")
cloud.add(CloudVertex(x:0.006,y:0.004,z:0.003),target:nil)
check(cloud.count == 1,"voxel dublet")
cloud.add(CloudVertex(x:0.2,y:0,z:0),target:zero,radius:0.1)
check(cloud.count == 1,"udenfor mål")
cloud.add(CloudVertex(x:1,y:0,z:0),target:nil)
cloud.add(CloudVertex(x:2,y:0,z:0),target:nil)
cloud.add(CloudVertex(x:3,y:0,z:0),target:nil)
check(cloud.count == 3,"maksimumgrænse")
let invalid = CloudVertex(x:Float.nan,y:0,z:0)
check(!invalid.finite,"NaN-forkastelse")
let ply = String(decoding: GeometryExport.ply(points:cloud.snapshot()),as:UTF8.self)
check(ply.contains("element vertex 3"),"PLY-antal")
check(ply.hasPrefix("ply\nformat ascii 1.0\n"),"PLY-format")
check(ply.contains("property float z\nend_header"),"PLY-header")
let obj = String(decoding:GeometryExport.obj(vertices:[zero, CloudVertex(x:1,y:0,z:0),CloudVertex(x:0,y:1,z:0)],triangles:[(0,1,2),(-1,1,2)]),as:UTF8.self)
check(obj.contains("f 1 2 3"),"OBJ 1-baseret")
check(!obj.contains("f 0"),"OBJ udelader ugyldig flade")
cloud.clear()
check(cloud.count == 0,"nulstil")
print("PASS \(count)/\(count) point-cloud / PLY / OBJ")
