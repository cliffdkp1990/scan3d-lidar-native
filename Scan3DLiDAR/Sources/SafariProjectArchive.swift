import CryptoKit
import Foundation

enum SafariArchiveError: LocalizedError {
    case noModel, tooLarge, incompatible
    var errorDescription: String? {
        switch self {
        case .noModel: return "Der er endnu ingen gemt 3D-model. Scan med LiDAR først."
        case .tooLarge: return "Modellen overstiger webversionens grænser: 8 MiB, 200.000 punkter eller 60.000 trekanter. Del originalen i stedet; den er bevaret."
        case .incompatible: return "Modellen kan ikke læses af webversionen. Originalen er bevaret og kan stadig deles."
        }
    }
}

extension ScanProject {
    /// A newer capture must win over a mesh exported before that capture.
    var safariModel: StoredScanFile? {
        let capture = currentCaptures.max { $0.createdAt < $1.createdAt }
        let export = exports.max { $0.createdAt < $1.createdAt }
        if let export, capture == nil || export.createdAt >= capture!.createdAt { return export.file }
        return capture?.pointCloud
    }
}

/// Local, model-only bridge into the existing Safari v2 format. No sensor emulation,
/// network, new native manifest format, coordinate conversion or reconstruction.
enum SafariProjectArchive {
    static let maxModelBytes = 8 * 1024 * 1024
    static let maxVertices = 200_000
    static let maxTriangles = 60_000

    private struct Asset: Encodable {
        let name: String
        let bytes: Int
        let sha256: String
        let type = "text/plain"
        let origin: String
        let data: String
    }
    private struct Project: Encodable {
        let name: String
        let createdAt: Date
        let updatedAt: Date
        let photos: [String] = []
        let model: Asset
    }
    private struct Archive: Encodable {
        let format = "scan3d-safari-project"
        let version = 2
        let project: Project
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(project: ScanProject, file: StoredScanFile, data: Data, synthetic: Bool) throws -> Data {
        try Task.checkCancellation()
        guard project.createdAt.timeIntervalSince1970.isFinite, project.updatedAt.timeIntervalSince1970.isFinite else {
            throw ProjectStoreError.invalidManifest
        }
        guard project.allFiles.contains(file), data.count == file.bytes, digest(data) == file.sha256 else {
            throw ProjectStoreError.damagedFile(file.name)
        }
        guard !data.isEmpty, data.count <= maxModelBytes else { throw SafariArchiveError.tooLarge }
        guard file.name.count <= 100, !file.name.contains("/"), !file.name.contains("\\"),
              !file.name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              let text = String(data: data, encoding: .utf8) else { throw SafariArchiveError.incompatible }
        let ext = (file.name as NSString).pathExtension.lowercased()
        let decimal = try NSRegularExpression(pattern: #"^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$"#)
        // Apply the web limit before the native preview compacts unused OBJ vertices.
        var sourceVertices = 0
        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            if index % 1024 == 0 { try Task.checkCancellation() }
            let tokens = line.split(whereSeparator: \.isWhitespace)
            if ext == "obj", tokens.first == "v" { sourceVertices += 1 }
            let coordinates = ext == "obj" ? tokens.first == "v" : tokens.count == 3 && Float(tokens[0]) != nil
            if coordinates {
                let values = ext == "obj" ? tokens.dropFirst() : tokens[...]
                guard values.allSatisfy({ decimal.firstMatch(in: String($0), range: NSRange(location: 0, length: $0.utf16.count)) != nil }) else {
                    throw SafariArchiveError.incompatible
                }
            }
        }
        guard sourceVertices <= maxVertices else { throw SafariArchiveError.tooLarge }
        let geometry = try GeometryPreview.parse(data, extension: ext)
        guard geometry.vertices.count <= maxVertices, geometry.triangles.count / 3 <= maxTriangles else {
            throw SafariArchiveError.tooLarge
        }
        let prefix = synthetic ? "Syntetisk demo · " : ""
        var title = String(String.UnicodeScalarView((prefix + project.title).unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }))
        while title.utf16.count > 100 { title.removeLast() }
        let asset = Asset(name: file.name, bytes: data.count, sha256: file.sha256,
            origin: synthetic ? "demo" : "import", data: data.base64EncodedString())
        let archive = Archive(project: Project(name: title, createdAt: project.createdAt,
            updatedAt: project.updatedAt, model: asset))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(archive)
    }

    /// Called automatically when a saved result is shown. Explicit ShareLink is
    /// still required to leave the app; this never uploads or opens another app.
    static func prepare(projectID: UUID, file: StoredScanFile, store: ProjectStore,
                        synthetic: Bool, cacheRoot: URL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("Scan3D-Safari-Share", isDirectory: true)) throws -> URL {
        let project = try store.load(projectID)
        guard project.allFiles.contains(file) else { throw SafariArchiveError.noModel }
        guard file.bytes > 0, file.bytes <= maxModelBytes else { throw SafariArchiveError.tooLarge }
        let original = try store.fileURL(file, projectID: projectID)
        // Read a bounded copy, then verify its exact length and SHA against the
        // manifest. This also catches a changed file without hashing unbounded data.
        let handle = try FileHandle(forReadingFrom: original)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_048_576, maxModelBytes + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            if data.count > maxModelBytes { throw SafariArchiveError.tooLarge }
        }
        let archive = try encode(project: project, file: file, data: data, synthetic: synthetic)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let url = cacheRoot.appendingPathComponent("Scan3D-\(digest(archive)).scan3d.json")
        // Content-addressed temporary copy: repeated opens reuse one name. Never
        // touch source models, photos, videos, manifests or another user's project.
        try archive.write(to: url, options: .atomic)
        let readback = try Data(contentsOf: url)
        guard readback == archive else { throw ProjectStoreError.damagedFile(url.lastPathComponent) }
        return url
    }
}
