import Foundation

var assertions = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError("FAIL: \(message)") }
    assertions += 1
}
func denied(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError("FAIL: accepted \(message)") } catch { assertions += 1 }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Scan3D-tests-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }
let store = ProjectStore(root: root)
try check(store.library().projects.isEmpty, "new library is empty")
let first = try store.create()
let other = try store.create()
check(first.id != other.id && first.coordinateSpaceID != other.coordinateSpaceID, "project and coordinates are isolated")
let jpeg = Data("original photo fixture".utf8)
let metadata = Data("{\"slot\":12}".utf8)
let cloud = Data("ply\nformat ascii 1.0\nelement vertex 0\nend_header\n".utf8)
let saved = try store.saveCapture(projectID: first.id, slot: 12, jpeg: jpeg, metadata: metadata,
    thumbnail: Data("thumbnail fixture".utf8), pointCloud: cloud)
check(saved.currentCaptures.count == 1 && saved.captures.count == 1, "successful save publishes once")
try store.verify(saved)
assertions += 1
let original = saved.captures[0]
check(original.photo.sha256.count == 64, "stored SHA-256")
check(original.photo.bytes == jpeg.count, "stored byte length")
try check(Data(contentsOf: store.verifiedURL(original.photo, projectID: first.id)) == jpeg, "exact image readback")
let reopenedStore = ProjectStore(root: root)
try check(reopenedStore.load(first.id).currentPhotos == saved.currentPhotos, "restart preserves current photos")
let replaced = try reopenedStore.saveCapture(projectID: first.id, slot: 12, jpeg: Data("new photo".utf8),
    metadata: metadata, thumbnail: nil, pointCloud: cloud)
check(replaced.captures.count == 2 && replaced.currentCaptures.count == 1, "retake preserves history")
check(replaced.currentCaptures[0].id != original.id, "retake becomes current only after commit")
try check(Data(contentsOf: store.verifiedURL(original.photo, projectID: first.id)) == jpeg, "retake leaves original untouched")
try check(store.load(other.id).captures.isEmpty, "second project stays empty")
denied("invalid slot") { _ = try store.saveCapture(projectID: first.id, slot: 36, jpeg: jpeg, metadata: metadata, thumbnail: nil, pointCloud: cloud) }
denied("empty image") { _ = try store.saveCapture(projectID: first.id, slot: 13, jpeg: Data(), metadata: metadata, thumbnail: nil, pointCloud: cloud) }

// Fail independently at every asset write and at manifest publication. Previous
// visible state and all original assets must survive each simulated disk failure.
for failAt in 1...5 {
    var writes = 0
    let failing = ProjectStore(root: root) { data, url in
        writes += 1
        if writes == failAt { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
    denied("disk failure \(failAt)") {
        _ = try failing.saveCapture(projectID: first.id, slot: 12, jpeg: Data("failed retake".utf8),
            metadata: metadata, thumbnail: Data("thumb".utf8), pointCloud: cloud)
    }
    let after = try reopenedStore.load(first.id)
    check(after.currentPhotos == replaced.currentPhotos && after.captures.count == 2, "failure never publishes partial retake \(failAt)")
    try store.verify(after)
    assertions += 1
}
let export = try store.saveExport(projectID: first.id, data: cloud, ext: "ply")
try check(Data(contentsOf: export) == cloud, "export readback")
try check(store.load(first.id).exports.count == 1, "export survives restart")
denied("unsupported export") { _ = try store.saveExport(projectID: first.id, data: cloud, ext: "../../bad") }
denied("path escape") {
    _ = try store.verifiedURL(StoredScanFile(name: "../project.json", bytes: 1, sha256: String(repeating: "0", count: 64)), projectID: first.id)
}
// Detect mutation, not merely missing files or a matching file extension.
let originalURL = try store.fileURL(original.photo, projectID: first.id)
try Data(repeating: 0, count: jpeg.count).write(to: originalURL, options: .atomic)
denied("same-size corrupt image") { _ = try store.verifiedURL(original.photo, projectID: first.id) }
try jpeg.write(to: originalURL, options: .atomic)
let photoLink = StoredScanFile(name: "linked.jpg", bytes: jpeg.count, sha256: original.photo.sha256)
let linkURL = root.appendingPathComponent(first.id.uuidString).appendingPathComponent(photoLink.name)
try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: originalURL)
denied("symlink image") { _ = try store.verifiedURL(photoLink, projectID: first.id) }
let badID = UUID()
let badDir = root.appendingPathComponent(badID.uuidString)
try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
try Data("interrupted manifest".utf8).write(to: badDir.appendingPathComponent("project.json"))
let listing = try store.library()
check(listing.projects.count == 2 && listing.unreadableCount == 1, "one corrupt project does not hide valid projects")
check(listing.projects.first?.id == first.id, "recently updated first")
let manifestURL = root.appendingPathComponent(other.id.uuidString).appendingPathComponent("project.json")
var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
json["version"] = 999
try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)
denied("future schema") { _ = try store.load(other.id) }
try store.verify(store.load(first.id))
assertions += 1
print("PASS \(assertions)/\(assertions) - durable projects, retakes, interrupted writes, integrity and restart")
