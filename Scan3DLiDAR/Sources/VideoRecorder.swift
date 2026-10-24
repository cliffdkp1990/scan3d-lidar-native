import AVFoundation
import CoreImage
import Foundation

enum ScanVideoOrientation: String, CaseIterable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight
    func transform(width: Int, height: Int) -> CGAffineTransform {
        switch self {
        case .landscapeRight: return .identity
        case .portrait: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
        case .landscapeLeft: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(width), ty: CGFloat(height))
        case .portraitUpsideDown: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(width))
        }
    }
}

enum ScanVideoError: LocalizedError {
    case noFrames, encoder, invalidMovie, lowStorage
    var errorDescription: String? {
        switch self {
        case .noFrames: return "Videoen modtog ingen brugbare kamerabilleder. Start en ny optagelse."
        case .encoder: return "Videoen kunne ikke færdiggøres. Den igangværende fil er bevaret."
        case .invalidMovie: return "Videoen kan ikke læses som en afspillelig video. Originalfilen er bevaret."
        case .lowStorage: return "Video stoppet: mindre end 200 MB ledig plads."
        }
    }
}

struct VideoMediaInfo {
    let width: Int
    let height: Int
    let duration: Double
}

enum VideoFileInspector {
    /// Check track, positive duration and a decoded frame before exposing playback.
    /// This is not a full-file corruption or physical-camera quality test.
    static func inspect(_ url: URL) async throws -> VideoMediaInfo {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ScanVideoError.invalidMovie
        }
        let duration = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        guard duration.isFinite, duration > 0, size.width > 0, size.height > 0 else {
            throw ScanVideoError.invalidMovie
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        guard reader.canAdd(output) else { throw ScanVideoError.invalidMovie }
        reader.add(output)
        guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
              CMSampleBufferGetImageBuffer(sample) != nil else { throw ScanVideoError.invalidMovie }
        reader.cancelReading()
        return VideoMediaInfo(width: Int(size.width), height: Int(size.height), duration: duration)
    }
}

/// Records the existing AR camera stream. No second AVCaptureSession, audio,
/// overlays or microphone access. At most one source pixel buffer is retained.
final class VideoRecorder {
    typealias Completion = (Result<VideoDetails, Error>) -> Void
    private let url: URL
    private let orientation: ScanVideoOrientation
    private let completion: Completion
    private let onFinishing: () -> Void
    private let freeBytes: () throws -> Int64
    private let queue = DispatchQueue(label: "dk.scan3d.video", qos: .userInitiated)
    private let lock = NSLock()
    private var accepting = true
    private var frameInFlight = false
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timeline = VideoTimeline()
    private var width = 0
    private var height = 0
    private var lastDiskCheck: Double?
    private var fatalError: Error?
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(url: URL, orientation: ScanVideoOrientation,
         freeBytes: (() throws -> Int64)? = nil, onFinishing: @escaping () -> Void = {},
         completion: @escaping Completion) {
        self.url = url
        self.orientation = orientation
        self.completion = completion
        self.onFinishing = onFinishing
        self.freeBytes = freeBytes ?? {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.deletingLastPathComponent().path)
            guard let size = attributes[.systemFreeSize] as? NSNumber else { throw ScanVideoError.lowStorage }
            return size.int64Value
        }
    }

    /// Drops frames under backpressure instead of accumulating an unbounded queue.
    @discardableResult
    func append(_ pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        lock.lock()
        guard accepting, !frameInFlight else { lock.unlock(); return false }
        frameInFlight = true
        queue.async { [self] in
            defer { lock.lock(); frameInFlight = false; lock.unlock() }
            do {
                guard timestamp.isFinite, timestamp >= 0 else { return }
                if timeline.reachedLimit(timestamp) { finish(reason: "durationLimit"); return }
                if lastDiskCheck == nil || timestamp - lastDiskCheck! >= 1 {
                    guard try freeBytes() >= 200 * 1_048_576 else {
                        // Finalize valid earlier frames, even when storage is low.
                        if timeline.frames == 0 { fatalError = ScanVideoError.lowStorage }
                        finish(reason: "lowStorage"); return
                    }
                    lastDiskCheck = timestamp
                }
                if writer == nil { try prepare(pixelBuffer) }
                guard let input = input, input.isReadyForMoreMediaData,
                      let adaptor = adaptor, let pool = adaptor.pixelBufferPool else { return }
                var next = timeline
                guard let seconds = next.accept(timestamp) else { return }
                var destination: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
                      let destination = destination else { throw ScanVideoError.encoder }
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                    y: CGFloat(height) / image.extent.height))
                context.render(scaled, to: destination, bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                guard adaptor.append(destination, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 60_000)) else {
                    throw writer?.error ?? ScanVideoError.encoder
                }
                timeline = next
            } catch {
                fatalError = error
                finish(reason: "encoderError")
            }
        }
        lock.unlock()
        return true
    }

    /// Idempotent: first stop wins; all previously queued frame work completes first.
    func finish(reason: String = "user") {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        accepting = false
        queue.async { [self] in
            onFinishing()
            guard let writer = writer, let input = input, timeline.frames > 0 else {
                completion(.failure(fatalError ?? ScanVideoError.noFrames)); return
            }
            guard fatalError == nil, writer.status == .writing else {
                writer.cancelWriting()
                completion(.failure(fatalError ?? writer.error ?? ScanVideoError.encoder)); return
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(seconds: timeline.duration, preferredTimescale: 60_000))
            writer.finishWriting { [self] in
                queue.async { [self] in
                    guard writer.status == .completed else {
                        completion(.failure(writer.error ?? ScanVideoError.encoder)); return
                    }
                    completion(.success(VideoDetails(width: width, height: height, duration: timeline.duration,
                        frames: timeline.frames, firstARTimestamp: timeline.firstTimestamp,
                        orientation: orientation.rawValue, stopReason: reason)))
                }
            }
        }
        lock.unlock()
    }

    private func prepare(_ pixelBuffer: CVPixelBuffer) throws {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { throw ScanVideoError.encoder }
        let scale = min(1, 1280.0 / Double(max(sourceWidth, sourceHeight)))
        width = max(2, Int(Double(sourceWidth) * scale) / 2 * 2)
        height = max(2, Int(Double(sourceHeight) * scale) / 2 * 2)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000,
                AVVideoExpectedSourceFrameRateKey: 15, AVVideoMaxKeyFrameIntervalKey: 30]
        ])
        input.expectsMediaDataInRealTime = true
        input.transform = orientation.transform(width: width, height: height)
        guard writer.canAdd(input) else { throw ScanVideoError.encoder }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.startWriting() else { throw writer.error ?? ScanVideoError.encoder }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }
}
