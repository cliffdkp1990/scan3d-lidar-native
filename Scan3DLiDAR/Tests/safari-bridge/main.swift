import Foundation

var assertions = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError("FAIL: \(message)") }
    assertions += 1
}
func denied(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError("FAIL: accepted \(message)") } catch { assertions += 1 }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Scan3D-bridge-tests-\(UUID())")
defer { try? FileManager.default.removeItem(at: root) }
let store = ProjectStore(root: root.appendingPathComponent("projects"))
let cache = root.appendingPathComponent("cache")
let project = try store.create()
check(project.safariModel == nil, "empty projects have no fabricated model")
let points = [CloudVertex(x: 0.1, y: 0.2, z: 0.3), CloudVertex(x: 1.1, y: 0.2, z: 0.3), CloudVertex(x: 0.1, y: 1.2, z: 0.3)]
let ply = GeometryExport.ply(points: points)
let obj = GeometryExport.obj(vertices: points, triangles: [(0, 1, 2)])
let fixtures = ProcessInfo.processInfo.environment["BRIDGE_FIXTURE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
if let fixtures { try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true) }
for (ext, model) in [("ply", ply), ("obj", obj)] {
    _ = try store.saveExport(projectID: project.id, data: model, ext: ext)
    var saved = try store.load(project.id)
    let file = saved.exports.last!.file
    check(saved.safariModel == file, "latest saved \(ext) selected")
    let manifest = store.root.appendingPathComponent(project.id.uuidString).appendingPathComponent("project.json")
    let originalManifest = try Data(contentsOf: manifest)
    let archiveURL = try SafariProjectArchive.prepare(projectID: project.id, file: file, store: store, synthetic: false, cacheRoot: cache)
    let archive = try Data(contentsOf: archiveURL)
    let raw = try JSONSerialization.jsonObject(with: archive) as! [String: Any]
    let payload = raw["project"] as! [String: Any], asset = payload["model"] as! [String: Any]
    check(raw["format"] as? String == "scan3d-safari-project" && raw["version"] as? Int == 2, "existing v2 format")
    check((payload["photos"] as? [String])?.isEmpty == true, "model-only copy; no private photos or video")
    check(Data(base64Encoded: asset["data"] as! String) == model, "exact original model bytes")
    check(asset["sha256"] as? String == file.sha256 && asset["bytes"] as? Int == model.count, "actual hash and byte length")
    check(asset["origin"] as? String == "import", "native model is a file import, not browser measurement")
    try check(Data(contentsOf: manifest) == originalManifest, "native manifest unchanged")
    try check(Data(contentsOf: store.verifiedURL(file, projectID: project.id)) == model, "source geometry unchanged")
    let repeated = try SafariProjectArchive.prepare(projectID: project.id, file: file, store: store, synthetic: false, cacheRoot: cache)
    check(repeated == archiveURL, "reopening does not create unbounded duplicate share filenames")
    if let fixtures {
        try archive.write(to: fixtures.appendingPathComponent("native-\(ext).scan3d.json"))
        try model.write(to: fixtures.appendingPathComponent("original.\(ext)"))
    }
    let synthetic = try SafariProjectArchive.encode(project: saved, file: file, data: model, synthetic: true)
    let demo = try JSONSerialization.jsonObject(with: synthetic) as! [String: Any]
    check(((demo["project"] as! [String: Any])["model"] as! [String: Any])["origin"] as? String == "demo", "synthetic model stays explicitly a demo")
    if ext == "obj", let fixtures { try synthetic.write(to: fixtures.appendingPathComponent("synthetic.scan3d.json")) }
    denied("changed bytes") { _ = try SafariProjectArchive.encode(project: saved, file: file, data: model + Data("# tampered".utf8), synthetic: false) }
    let other = try store.create()
    denied("cross-project file") { _ = try SafariProjectArchive.prepare(projectID: other.id, file: file, store: store, synthetic: false, cacheRoot: cache) }
    saved.title = String(repeating: "🛰️", count: 100) + "\u{0000}"
    let titled = try JSONSerialization.jsonObject(with: SafariProjectArchive.encode(project: saved, file: file, data: model, synthetic: false)) as! [String: Any]
    check(((titled["project"] as! [String: Any])["name"] as! String).utf16.count <= 100, "Unicode title fits the JS UTF-16 bound")
}
var saved = try store.load(project.id)
let prior = saved.exports.last!
let captured = try store.saveCapture(projectID: project.id, slot: 0, jpeg: Data("SYNTHETIC PHOTO BYTES; not exported".utf8),
    metadata: Data("{}".utf8), thumbnail: nil, pointCloud: ply)
let current = captured.currentCaptures[0]
saved.captures = [StoredCapture(id: current.id, slot: current.slot, createdAt: prior.createdAt.addingTimeInterval(10),
    photo: current.photo, metadata: current.metadata, thumbnail: current.thumbnail, pointCloud: current.pointCloud)]
saved.currentPhotos = ["0": current.id]
check(saved.safariModel == current.pointCloud, "newer capture wins over stale mesh export")
saved.exports.append(StoredExport(id: UUID(), createdAt: current.createdAt.addingTimeInterval(20), file: prior.file))
check(saved.safariModel == prior.file, "new mesh wins after subsequent export")
let url = try store.fileURL(prior.file, projectID: project.id)
let original = try Data(contentsOf: url)
try Data("corrupt".utf8).write(to: url)
denied("externally corrupted model") { _ = try SafariProjectArchive.prepare(projectID: project.id, file: prior.file, store: store, synthetic: false, cacheRoot: cache) }
try original.write(to: url)
let huge = Data(repeating: 32, count: SafariProjectArchive.maxModelBytes + 1)
_ = try store.saveExport(projectID: project.id, data: huge, ext: "obj")
let hugeFile = try store.load(project.id).exports.last!.file
denied("oversized original") { _ = try SafariProjectArchive.prepare(projectID: project.id, file: hugeFile, store: store, synthetic: false, cacheRoot: cache) }
try check(store.verifiedURL(hugeFile, projectID: project.id).isFileURL, "oversized original still shareable")
for invalid in ["mtllib https://example.com/evil.mtl\nv 0 0 0\n", "v nan 0 0\n", "v 0x1p0 0 0\nv 0 1 0\nv 0 0 1\nf 1 2 3\n"] {
    _ = try store.saveExport(projectID: project.id, data: Data(invalid.utf8), ext: "obj")
    let file = try store.load(project.id).exports.last!.file
    denied("incompatible geometry") { _ = try SafariProjectArchive.prepare(projectID: project.id, file: file, store: store, synthetic: false, cacheRoot: cache) }
}
print("Safari bridge source assertions passed: \(assertions). Synthetic fixtures only; no physical LiDAR test.")
