import AVFoundation
import Foundation

var assertions = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError("FAIL: \(message)") }
    assertions += 1
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("Scan3D-video-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

var clock = VideoTimeline()
check(clock.accept(.nan) == nil && clock.accept(-1) == nil, "invalid source clock")
check(clock.frames == 0, "rejected frames leave timeline untouched")
check(clock.accept(100) == 0, "first AR timestamp becomes zero")
check(clock.accept(100) == nil && clock.accept(99) == nil, "duplicates and rollback")
check(clock.accept(100.01) == nil, "15 fps limit")
check(abs(clock.accept(100.1)! - 0.1) < 0.0001, "source spacing preserved")
check(clock.frames == 2 && clock.duration > 0.1, "positive duration includes final frame")
check(clock.reachedLimit(400) && clock.accept(400) == nil, "five minute bound")
check(!clock.reachedLimit(.nan), "invalid limit query")

func redBuffer(width: Int = 320, height: Int = 240) throws -> CVPixelBuffer {
    var result: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &result)
    guard status == kCVReturnSuccess, let buffer = result else { throw ScanVideoError.encoder }
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            base[y * row + x * 4] = 0
            base[y * row + x * 4 + 1] = 0
            base[y * row + x * 4 + 2] = 255
            base[y * row + x * 4 + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
}

final class RecordingResult {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<VideoDetails, Error>?
    private var callbacks = 0
    func receive(_ value: Result<VideoDetails, Error>) {
        lock.lock(); result = value; callbacks += 1; lock.unlock(); done.signal()
    }
    func awaitResult() throws -> VideoDetails {
        guard done.wait(timeout: .now() + 30) == .success else { throw ScanVideoError.encoder }
        lock.lock(); defer { lock.unlock() }
        guard callbacks == 1, let result = result else { throw ScanVideoError.encoder }
        return try result.get()
    }
}

func record(url: URL, orientation: ScanVideoOrientation, lowDisk: Bool = false,
            sourceWidth: Int = 320, sourceHeight: Int = 240, stopReason: String = "user") throws -> VideoDetails {
    let result = RecordingResult()
    var diskChecks = 0
    let recorder = VideoRecorder(url: url, orientation: orientation, freeBytes: {
        diskChecks += 1
        return lowDisk && diskChecks >= 2 ? 0 : 1_000_000_000
    }, completion: result.receive)
    let buffer = try redBuffer(width: sourceWidth, height: sourceHeight)
    for index in 0..<30 {
        _ = recorder.append(buffer, timestamp: 10 + Double(index) / 15)
        Thread.sleep(forTimeInterval: 0.035)
    }
    recorder.finish(reason: stopReason)
    recorder.finish(reason: "mustNotReplaceFirstStop")
    return try result.awaitResult()
}

for orientation in ScanVideoOrientation.allCases {
    let url = root.appendingPathComponent("\(orientation.rawValue).mov")
    let details = try record(url: url, orientation: orientation)
    check(details.frames! >= 5, "real encoder accepted frames: \(orientation)")
    check(details.stopReason == "user", "stop is idempotent")
    let info = try await VideoFileInspector.inspect(url)
    check(info.duration > 0.3 && info.duration < 2.3, "movie duration is readable")
    check(info.width == 320 && info.height == 240, "native aspect ratio")
    let asset = AVURLAsset(url: url)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    check(audio.isEmpty, "no microphone or audio track")
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let transform = try await track.load(.preferredTransform)
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 240).applying(transform)
    let portrait = orientation == .portrait || orientation == .portraitUpsideDown
    check(abs(bounds.width) == (portrait ? 240 : 320) && abs(bounds.height) == (portrait ? 320 : 240), "all orientation bounds")
    check(abs(bounds.minX) < 0.001 && abs(bounds.minY) < 0.001, "rotation translated into positive bounds")

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    check(reader.startReading(), "decoder starts")
    var count = 0
    var previous = -Double.infinity
    while let sample = output.copyNextSampleBuffer() {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        check(timestamp > previous, "decoded timestamps strictly increase")
        previous = timestamp
        count += 1
        if count == 1, let image = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(image, .readOnly)
            let pixel = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
            check(pixel[2] > 150 && pixel[0] < 90, "encoded content survives decode")
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
        }
    }
    check(reader.status == .completed && count == details.frames, "every written frame decodes")
}

let scaledURL = root.appendingPathComponent("scaled.mov")
let scaled = try record(url: scaledURL, orientation: .landscapeRight, sourceWidth: 1920, sourceHeight: 1080)
check(scaled.width == 1280 && scaled.height == 720, "bounded resolution without upscaling")
let scaledInfo = try await VideoFileInspector.inspect(scaledURL)
check(scaledInfo.width == 1280 && scaledInfo.height == 720, "bounded output decodes")
let lowURL = root.appendingPathComponent("low-space.mov")
let low = try record(url: lowURL, orientation: .portrait, lowDisk: true)
check(low.stopReason == "lowStorage" && low.frames! > 0, "low disk finalizes previous frames")
_ = try await VideoFileInspector.inspect(lowURL)
assertions += 1
let interruptedURL = root.appendingPathComponent("interrupted.mov")
let interruptedCapture = try record(url: interruptedURL, orientation: .portrait, stopReason: "sessionInterrupted")
check(interruptedCapture.stopReason == "sessionInterrupted", "interruption termination recorded")
_ = try await VideoFileInspector.inspect(interruptedURL)
assertions += 1

let emptyResult = RecordingResult()
let empty = VideoRecorder(url: root.appendingPathComponent("empty.mov"), orientation: .portrait, completion: emptyResult.receive)
empty.finish(); empty.finish()
do { _ = try emptyResult.awaitResult(); fatalError("FAIL: empty recording accepted") } catch { assertions += 1 }
let corruptURL = root.appendingPathComponent("corrupt.mov")
try Data("not a video".utf8).write(to: corruptURL)
do { _ = try await VideoFileInspector.inspect(corruptURL); fatalError("FAIL: corrupt video accepted") } catch { assertions += 1 }

// Full path: journal -> encoder -> decode verification -> manifest -> reopen/hash.
let store = ProjectStore(root: root.appendingPathComponent("projects"))
let project = try store.create()
let (pending, movieURL) = try store.beginVideo(projectID: project.id)
try check(ProjectStore(root: store.root).load(project.id).unfinishedVideos.count == 1, "recording journal survives restart")
let recorded = try record(url: movieURL, orientation: .portrait)
let inspected = try await VideoFileInspector.inspect(movieURL)
let saved = try store.finishVideo(projectID: project.id, videoID: pending.id,
    details: VideoDetails(width: inspected.width, height: inspected.height, duration: inspected.duration,
        frames: recorded.frames, firstARTimestamp: recorded.firstARTimestamp, orientation: recorded.orientation, stopReason: recorded.stopReason))
let reloaded = try ProjectStore(root: store.root).load(project.id)
check(reloaded.savedVideos.count == 1 && reloaded.unfinishedVideos.isEmpty, "completed video replaces journal")
try store.verify(reloaded)
assertions += 1
try check(store.finishVideo(projectID: project.id, videoID: pending.id, details: recorded).id == saved.id, "idempotent publication")
let (recovery, recoveryURL) = try store.beginVideo(projectID: project.id)
_ = try record(url: recoveryURL, orientation: .landscapeRight)
var publicationWrites = 0
let interrupted = ProjectStore(root: store.root) { data, url in
    publicationWrites += 1
    if publicationWrites == 2 { throw CocoaError(.fileWriteOutOfSpace) }
    try data.write(to: url, options: .atomic)
}
do {
    _ = try interrupted.finishVideo(projectID: project.id, videoID: recovery.id, details: recorded)
    fatalError("FAIL: interrupted publication accepted")
} catch { assertions += 1 }
try check(store.load(project.id).unfinishedVideos.count == 1, "failed publication retains recovery journal")
let recoveredInfo = try await VideoFileInspector.inspect(store.pendingVideoURL(projectID: project.id, videoID: recovery.id))
_ = try store.finishVideo(projectID: project.id, videoID: recovery.id,
    details: VideoDetails(width: recoveredInfo.width, height: recoveredInfo.height, duration: recoveredInfo.duration,
        frames: nil, firstARTimestamp: nil, orientation: "movieTrack", stopReason: "recovered"))
try check(store.load(project.id).savedVideos.count == 2, "recovery publishes preserved playable movie")
try check(store.load(project.id).unfinishedVideos.isEmpty, "recovery clears only journal")
let movie = try store.verifiedURL(saved.file, projectID: project.id)
let handle = try FileHandle(forWritingTo: movie)
try handle.write(contentsOf: Data(repeating: 0, count: 20))
try handle.close()
do { _ = try store.verifiedURL(saved.file, projectID: project.id); fatalError("FAIL: changed video hash accepted") } catch { assertions += 1 }
print("PASS \(assertions)/\(assertions) - real H264 encode/decode, timing, orientations, no audio, resource stop, durable video and recovery")
