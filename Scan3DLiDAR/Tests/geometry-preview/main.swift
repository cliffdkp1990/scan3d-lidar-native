import Foundation

var assertions = 0
func check(_ value: Bool, _ message: String) {
    guard value else { fatalError("FAIL: \(message)") }
    assertions += 1
}
func reject(_ text: String, _ ext: String, _ message: String) {
    do { _ = try GeometryPreview.parse(Data(text.utf8), extension: ext); fatalError("Accepted: \(message)") }
    catch { assertions += 1 }
}
let points = [CloudVertex(x: 10,y: 20,z: 30), CloudVertex(x: 12,y: 21,z: 30), CloudVertex(x: 10,y: 22,z: 30)]
let ply = GeometryExport.ply(points: points)
let cloud = try GeometryPreview.parse(ply, extension: "PLY")
check(cloud.isPointCloud && cloud.vertices.count == 3, "actual PLY exporter round-trip")
check(cloud.sizeMeters == SIMD3<Float>(2,2,0), "meter-space source dimensions")
check(cloud.vertices.first == SIMD3<Float>(10,20,30), "source coordinates remain unchanged")
let display = try cloud.displayMesh()
check(display.displayedPoints == 3 && display.positions.count == 18 && display.indices.count == 72, "visible markers for every small-cloud point")
check(display.indices.allSatisfy { Int($0) < display.positions.count }, "marker indices stay in bounds")
check(display.positions.allSatisfy { abs($0.x) <= 1.01 && abs($0.y) <= 1.01 }, "display recenters and fits source geometry")
let obj = GeometryExport.obj(vertices: points + [CloudVertex(x: 999,y: 999,z: 999)], triangles: [(0,1,2)])
let mesh = try GeometryPreview.parse(obj, extension: "obj")
check(!mesh.isPointCloud && mesh.triangles == [0,1,2], "actual OBJ exporter round-trip and index conversion")
check(mesh.vertices.count == 3 && mesh.sizeMeters == SIMD3<Float>(2,2,0), "unreferenced OBJ outlier does not ruin framing")
check(try mesh.displayMesh().indices == [0,1,2], "mesh topology preserved")
check(try GeometryPreview.parse(Data(String(decoding: ply, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8), extension: "ply").vertices.count == 3, "CRLF accepted")
let prefix = "ply\nformat ascii 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
reject(prefix + "0 0 0\n", "ply", "truncated cloud")
reject(prefix + "0 0 0\n1 0 0\n2 0 0\n", "ply", "extra rows")
reject(prefix + "0 0 0\nnan 1 0\n", "ply", "NaN")
reject(prefix + "0 0 0\ninf 1 0\n", "ply", "infinity")
reject(prefix + "0 0 0\n1000001 1 0\n", "ply", "unreasonable coordinate")
reject(prefix + "0 0 0\n0 0 0\n", "ply", "zero-size cloud")
reject(prefix.replacingOccurrences(of: "element vertex 2", with: "element vertex -1"), "ply", "negative count")
reject(prefix.replacingOccurrences(of: "element vertex 2", with: "element vertex 480001"), "ply", "vertex cap before allocation")
reject(prefix.replacingOccurrences(of: "property float y", with: "property float z"), "ply", "wrong property order")
reject(prefix.replacingOccurrences(of: "format ascii 1.0", with: "format binary_little_endian 1.0"), "ply", "binary PLY deliberately unsupported")
reject(prefix.replacingOccurrences(of: "end_header\n", with: ""), "ply", "unterminated header")
reject("", "obj", "empty OBJ")
reject("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 0 2 3\n", "obj", "zero face index")
reject("v 0 0 0\nv 1 0 0\nv 0 1 0\nf -1 2 3\n", "obj", "negative face index")
reject("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 4\n", "obj", "missing vertex")
reject("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 2\n", "obj", "repeated index")
reject("v 0 0 0\nv 1 0 0\nv 2 0 0\nf 1 2 3\n", "obj", "zero-area triangle")
reject("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/1 2/2 3/3\n", "obj", "texture import not silently discarded")
reject("mtllib external.mtl\n", "obj", "external resources never loaded")
reject("v nan 0 0\nf 1 2 3\n", "obj", "invalid OBJ vertex")
reject("anything", "stl", "unsupported extension")
do { _ = try GeometryPreview.parse(Data([0xff,0xfe]), extension: "ply"); fatalError("UTF-8 accepted") }
catch { assertions += 1 }
do { _ = try GeometryPreview.parse(Data(repeating: 32, count: GeometryPreview.maxBytes + 1), extension: "ply"); fatalError("oversize accepted") }
catch { assertions += 1 }
let many = (0..<120_000).map { CloudVertex(x: Float($0) * 0.001,y: 0,z: 0) }
let large = try GeometryPreview.parse(GeometryExport.ply(points: many), extension: "ply")
let bounded = try large.displayMesh()
check(large.vertices.count == 120_000 && bounded.displayedPoints == 20_000, "source preserved and display work bounded")
check(bounded.positions.count == 120_000 && bounded.indices.count == 480_000, "bounded marker allocation")
var camera = GeometryCamera()
camera.zoom(by: 1000)
check(camera.distance == 2.2, "zoom-in limit")
camera.zoom(by: 0.0001)
check(camera.distance == 12, "zoom-out limit")
camera.rotate(horizontal: 10_000, vertical: 20)
check(abs(camera.yaw) <= 2 * .pi && camera.pitch == 1.4, "orbit wraps and pitch clamps")
camera.rotate(horizontal: 0, vertical: -20)
check(camera.pitch == -1.4, "lower pitch limit")
let before = camera.position
camera.zoom(by: .nan); camera.rotate(horizontal: .infinity)
check(camera.position == before, "invalid gesture deltas ignored")
camera = GeometryCamera()
check(camera.distance == 4.5 && camera.yaw == 0 && camera.pitch == 0.2, "reset restores fit camera")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try ply.write(to: temporary)
check(try GeometryPreview.read(temporary) == ply, "bounded file reader returns full data")
try FileManager.default.removeItem(at: temporary)
print("PASS \(assertions)/\(assertions) geometry preview, malformed files, resource bounds and camera")
