import CryptoKit
import Foundation

struct StoredScanFile: Codable, Equatable {
    let name: String
    let bytes: Int
    let sha256: String
}

struct StoredCapture: Codable, Identifiable {
    let id: UUID
    let slot: Int
    let createdAt: Date
    let photo: StoredScanFile
    let metadata: StoredScanFile
    let thumbnail: StoredScanFile?
    let pointCloud: StoredScanFile
}

struct StoredExport: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let file: StoredScanFile
}

struct PendingVideo: Codable, Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date
    var failure: String?
}

struct VideoDetails: Codable {
    let width: Int
    let height: Int
    let duration: Double
    let frames: Int?
    let firstARTimestamp: Double?
    let orientation: String
    let stopReason: String
}

struct StoredVideo: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let file: StoredScanFile
    let metadata: StoredScanFile
    let details: VideoDetails
}

struct ScanProject: Codable, Identifiable {
    let version: Int
    let id: UUID
    /// One locked target in one AR session. Reopened projects are read-only.
    let coordinateSpaceID: UUID
    let createdAt: Date
    var updatedAt: Date
    var title: String
    var captures: [StoredCapture]
    var currentPhotos: [String: UUID]
    var exports: [StoredExport]
    // Optional fields keep original v1 manifests readable without migration.
    var videos: [StoredVideo]? = nil
    var pendingVideos: [PendingVideo]? = nil

    var savedVideos: [StoredVideo] { videos ?? [] }
    var unfinishedVideos: [PendingVideo] { pendingVideos ?? [] }

    var currentCaptures: [StoredCapture] {
        captures.filter { currentPhotos[String($0.slot)] == $0.id }.sorted { $0.slot < $1.slot }
    }
    var allFiles: [StoredScanFile] {
        captures.flatMap { [$0.photo, $0.metadata, $0.pointCloud] + [$0.thumbnail].compactMap { $0 } }
            + exports.map(\.file) + savedVideos.flatMap { [$0.file, $0.metadata] }
    }
}

struct ProjectLibrary {
    let projects: [ScanProject]
    let unreadableCount: Int
}

enum ProjectStoreError: LocalizedError {
    case invalidManifest, invalidSlot, emptyFile, invalidFormat, damagedFile(String)
    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Projektets manifest er ugyldigt eller fra en nyere version. Originalerne er bevaret."
        case .invalidSlot: return "Fotopositionen er ugyldig."
        case .emptyFile: return "En tom optagelse kan ikke gemmes."
        case .invalidFormat: return "Eksportformatet er ikke understøttet."
        case .damagedFile(let name): return "Filen mangler eller har ændret indhold: \(name)."
        }
    }
}

/// Manifest-last transactions: immutable assets first, atomic manifest last.
/// Failed writes never publish a partial capture or replace the previous manifest.
/// Orphan assets from interrupted writes are retained, never automatically deleted.
final class ProjectStore {
    typealias Writer = (Data, URL) throws -> Void
    let root: URL
    private let writer: Writer
    private let lock = NSRecursiveLock()
    private let fm = FileManager.default

    init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Scan3DProjects", isDirectory: true),
         writer: @escaping Writer = { try $0.write(to: $1, options: .atomic) }) {
        self.root = root
        self.writer = writer
    }

    func create() throws -> ScanProject {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        let project = ScanProject(version: 1, id: UUID(), coordinateSpaceID: UUID(),
            createdAt: now, updatedAt: now, title: "Scanning \(now.formatted(date: .numeric, time: .shortened))",
            captures: [], currentPhotos: [:], exports: [])
        try fm.createDirectory(at: directory(project.id), withIntermediateDirectories: true)
        try commit(project)
        return project
    }

    func load(_ id: UUID) throws -> ScanProject {
        lock.lock(); defer { lock.unlock() }
        let data = try Data(contentsOf: directory(id).appendingPathComponent("project.json"))
        let project = try JSONDecoder().decode(ScanProject.self, from: data)
        guard project.version == 1, project.id == id,
              Set(project.captures.map(\.id)).count == project.captures.count,
              project.captures.allSatisfy({ (0..<36).contains($0.slot) }),
              project.currentPhotos.allSatisfy({ slot, capture in
                  project.captures.contains { String($0.slot) == slot && $0.id == capture }
              }), project.unfinishedVideos.allSatisfy({ $0.name == "video-\($0.id.uuidString).mov" }),
              Set(project.unfinishedVideos.map(\.id)).count == project.unfinishedVideos.count,
              Set(project.savedVideos.map(\.id)).count == project.savedVideos.count,
              Set(project.unfinishedVideos.map(\.id)).isDisjoint(with: project.savedVideos.map(\.id)),
              project.savedVideos.allSatisfy({ $0.details.duration.isFinite && $0.details.duration > 0
                  && $0.details.width > 0 && $0.details.height > 0 }),
              project.allFiles.allSatisfy({ Self.validName($0.name) && $0.bytes > 0
                  && $0.sha256.count == 64 && $0.sha256.allSatisfy { "0123456789abcdef".contains($0) } }) else {
            throw ProjectStoreError.invalidManifest
        }
        return project
    }

    func library() throws -> ProjectLibrary {
        lock.lock(); defer { lock.unlock() }
        guard fm.fileExists(atPath: root.path) else { return ProjectLibrary(projects: [], unreadableCount: 0) }
        let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var projects: [ScanProject] = []
        var unreadable = 0
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            do { projects.append(try load(id)) } catch { unreadable += 1 }
        }
        return ProjectLibrary(projects: projects.sorted { $0.updatedAt > $1.updatedAt }, unreadableCount: unreadable)
    }

    func saveCapture(projectID: UUID, slot: Int, jpeg: Data, metadata: Data,
                     thumbnail: Data?, pointCloud: Data) throws -> ScanProject {
        lock.lock(); defer { lock.unlock() }
        guard (0..<36).contains(slot) else { throw ProjectStoreError.invalidSlot }
        var project = try load(projectID)
        let id = UUID()
        let stem = "capture-\(id.uuidString)"
        let photo = try write(jpeg, name: stem + ".jpg", projectID: projectID)
        let meta = try write(metadata, name: stem + ".json", projectID: projectID)
        let thumb = try thumbnail.map { try write($0, name: stem + "-thumb.jpg", projectID: projectID) }
        let cloud = try write(pointCloud, name: stem + ".ply", projectID: projectID)
        project.captures.append(StoredCapture(id: id, slot: slot, createdAt: Date(),
            photo: photo, metadata: meta, thumbnail: thumb, pointCloud: cloud))
        project.currentPhotos[String(slot)] = id
        project.updatedAt = Date()
        try commit(project)
        return project
    }

    func saveExport(projectID: UUID, data: Data, ext: String) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard ["ply", "obj"].contains(ext) else { throw ProjectStoreError.invalidFormat }
        var project = try load(projectID)
        let id = UUID()
        let file = try write(data, name: "model-\(id.uuidString).\(ext)", projectID: projectID)
        project.exports.append(StoredExport(id: id, createdAt: Date(), file: file))
        project.updatedAt = Date()
        try commit(project)
        return try verifiedURL(file, projectID: projectID)
    }

    func fileURL(_ file: StoredScanFile, projectID: UUID) throws -> URL {
        guard Self.validName(file.name) else { throw ProjectStoreError.invalidManifest }
        return try regularFileURL(name: file.name, projectID: projectID)
    }

    private func regularFileURL(name: String, projectID: UUID) throws -> URL {
        let url = directory(projectID).appendingPathComponent(name)
        // The app's Files directory can be edited outside the app. Never follow links.
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw ProjectStoreError.damagedFile(name)
        }
        return url
    }

    func verifiedURL(_ file: StoredScanFile, projectID: UUID) throws -> URL {
        let url = try fileURL(file, projectID: projectID)
        let actual = try Self.describeFile(at: url)
        guard actual.bytes == file.bytes, actual.sha256 == file.sha256 else {
            throw ProjectStoreError.damagedFile(file.name)
        }
        return url
    }

    func verify(_ project: ScanProject) throws {
        for file in project.allFiles { _ = try verifiedURL(file, projectID: project.id) }
    }

    func beginVideo(projectID: UUID) throws -> (PendingVideo, URL) {
        lock.lock(); defer { lock.unlock() }
        var project = try load(projectID)
        guard project.unfinishedVideos.count < 100 else { throw ProjectStoreError.invalidManifest }
        let id = UUID()
        let pending = PendingVideo(id: id, name: "video-\(id.uuidString).mov", createdAt: Date())
        project.pendingVideos = project.unfinishedVideos + [pending]
        project.updatedAt = Date()
        try commit(project) // Journal before the encoder creates its output.
        return (pending, directory(projectID).appendingPathComponent(pending.name))
    }

    func pendingVideoURL(projectID: UUID, videoID: UUID) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let project = try load(projectID)
        guard let pending = project.unfinishedVideos.first(where: { $0.id == videoID }) else {
            throw ProjectStoreError.invalidManifest
        }
        return try regularFileURL(name: pending.name, projectID: projectID)
    }

    func noteVideoFailure(projectID: UUID, videoID: UUID, message: String) throws {
        lock.lock(); defer { lock.unlock() }
        var project = try load(projectID)
        var pending = project.unfinishedVideos
        guard let index = pending.firstIndex(where: { $0.id == videoID }) else { return }
        pending[index].failure = message
        project.pendingVideos = pending
        project.updatedAt = Date()
        try commit(project)
    }

    /// The caller validates the movie with AVFoundation before publication. If
    /// manifest commit fails, the movie and journal remain available for recovery.
    func finishVideo(projectID: UUID, videoID: UUID, details: VideoDetails) throws -> StoredVideo {
        lock.lock(); defer { lock.unlock() }
        var project = try load(projectID)
        if let existing = project.savedVideos.first(where: { $0.id == videoID }) { return existing }
        guard details.duration.isFinite, details.duration > 0, details.width > 0, details.height > 0,
              let pending = project.unfinishedVideos.first(where: { $0.id == videoID }) else {
            throw ProjectStoreError.invalidManifest
        }
        let movie = try Self.describeFile(at: pendingVideoURL(projectID: projectID, videoID: videoID))
        guard movie.bytes > 0 else { throw ProjectStoreError.emptyFile }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let meta = try write(encoder.encode(details), name: "video-\(videoID.uuidString).json", projectID: projectID)
        let video = StoredVideo(id: videoID, createdAt: pending.createdAt, file: movie, metadata: meta, details: details)
        project.videos = project.savedVideos + [video]
        project.pendingVideos = project.unfinishedVideos.filter { $0.id != videoID }
        project.updatedAt = Date()
        try commit(project)
        return video
    }

    /// Bounded memory for long videos, also used to verify existing photos.
    private static func describeFile(at url: URL) throws -> StoredScanFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var bytes = 0
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty {
            hasher.update(data: block)
            bytes += block.count
        }
        return StoredScanFile(name: url.lastPathComponent, bytes: bytes,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func write(_ data: Data, name: String, projectID: UUID) throws -> StoredScanFile {
        guard !data.isEmpty else { throw ProjectStoreError.emptyFile }
        let file = StoredScanFile(name: name, bytes: data.count, sha256: Self.hash(data))
        try writer(data, directory(projectID).appendingPathComponent(name))
        // Read back before publishing a record in the manifest.
        _ = try verifiedURL(file, projectID: projectID)
        return file
    }
    private func commit(_ project: ScanProject) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writer(encoder.encode(project), directory(project.id).appendingPathComponent("project.json"))
    }
}
