import ARKit
import Combine
import CoreImage
import Foundation
import ImageIO
import UIKit
import simd
import Vision

enum ScanVideoState { case idle, preparing, recording, finishing }

/// Native Scan3D prototype for LiDAR-capable iPhones. All image processing is on-device.
/// World position is in ARKit session coordinates (meters), not a survey-grade global position.
final class ScanEngine: NSObject, ObservableObject, ARSessionDelegate {
    @Published var distanceText = "–"
    @Published var positionText = "–"
    @Published var trackingText = "Tryk Start"
    @Published var subjectText = "Intet objekt foreslået"
    @Published var orientationText = "–"
    @Published var guidanceText = "Peg mod genstanden, og gå roligt rundt om den."
    @Published var savedCount = 0
    @Published var lidarPointCount = 0
    @Published var exportedCloudURL: URL?
    @Published var exportedMeshURL: URL?
    @Published var exportedTriangleCount = 0
    @Published var exportMessage = "Tag billeder fra flere vinkler for at opbygge en LiDAR-punktsky."
    @Published var showWireframe = true
    private let cloud = PointCollector()
    private var depthPointsBySlot: [Int: [CloudVertex]] = [:]
    var hasMeshSupport: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) }

    @Published var lastPhotoURL: URL?
    @Published var detectedRect: CGRect? // normalized Vision coordinates, diagnostic only
    @Published var running = false
    @Published var automaticPhotos = true
    @Published private(set) var savingPhoto = false
    @Published private(set) var activeProject: ScanProject?
    @Published private(set) var projects: [ScanProject] = []
    @Published private(set) var libraryMessage = ""
    @Published private(set) var captureSuspended = false
    @Published var automaticVideo = true
    @Published private(set) var videoState: ScanVideoState = .idle
    @Published private(set) var videoMessage = "Video starter sammen med et nyt låst objekt. Ingen lyd optages."
    private var videoRecorder: VideoRecorder?
    private var pendingVideoStop: String?
    private var pendingAutomaticVideoStart = false
    private var videoBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    var videoBusy: Bool { videoState != .idle }
    let projectStore = ProjectStore()
    private let fileQueue = DispatchQueue(label: "dk.scan3d.project-files", qos: .userInitiated)
    private var automaticCapture = AutomaticCapture()
    private var needsNewCoordinateSpace = false
    @Published var missionTargetLocked = false
    @Published var missionReady = false
    @Published var missionCurrentSlot = "Lås genstanden for at begynde"
    @Published var missionCoverage: [Bool] = Array(repeating: false, count: 36)
    @Published var missionNext = "Først: peg på genstanden, og tryk Lås genstand."
    @Published var missionProgress = "0/36 vinkler"
    @Published var missionNavigation = "Lås genstanden for at få næste bevægelse."
    @Published var retakeSlotIndex: Int? = nil
    @Published var retakeHint = "Tryk en grøn position for at tage billedet om."
    private var targetPoint: ScanPoint?
    private var capturedSlots = Set<Int>()
    private var currentSlotIndex: Int?
    private var previousCamera: ScanPoint?
    private var previousTimestamp: TimeInterval?
    private var stableSince: TimeInterval?

    weak var session: ARSession?
    private let visionQueue = DispatchQueue(label: "dk.scan3d.vision", qos: .userInitiated)
    private var lastVisionTime: TimeInterval = 0
    private var visionBusy = false
    private let ciContext = CIContext()
    private var latestDistance: Float?
    private var latestPosition: SIMD3<Float>?

    static var supportsLiDAR: Bool {
        ARWorldTrackingConfiguration.isSupported &&
        ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    func start(using session: ARSession) {
        guard !savingPhoto, !videoBusy else { return }
        guard Self.supportsLiDAR else {
            trackingText = "LiDAR-dybde er ikke understøttet på denne enhed."
            return
        }
        self.session = session
        session.delegate = self
        session.delegateQueue = .main // ARKit callbacks and mission state stay on main thread.
        if needsNewCoordinateSpace {
            resetMission()
            needsNewCoordinateSpace = false
        }
        if !running && previousTimestamp == nil { resetMission() }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        config.frameSemantics.insert(.smoothedSceneDepth)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        session.run(config, options: previousTimestamp == nil ? [.resetTracking, .removeExistingAnchors] : [])
        running = true
        trackingText = "Starter ARKit …"
    }

    func stop() {
        stopVideo(reason: "cameraPaused")
        session?.pause()
        self.running = false
        self.trackingText = "Sat på pause"
        self.missionReady = false
        stableSince = nil
        // A paused device may move. Preserve stored projects, but never assume the
        // old world coordinates are still valid on resume without relocalization.
        needsNewCoordinateSpace = true
    }

    func suspendCapture(_ suspended: Bool) {
        if suspended { stopVideo(reason: "captureSuspended") }
        captureSuspended = suspended
        missionReady = false
        stableSince = nil
        if !suspended, pendingAutomaticVideoStart {
            pendingAutomaticVideoStart = false
            if automaticVideo { startVideo() }
        }
    }

    func refreshLibrary() {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let library = try self.projectStore.library()
                DispatchQueue.main.async {
                    self.projects = library.projects
                    self.libraryMessage = library.unreadableCount == 0 ? ""
                        : "\(library.unreadableCount) projekt(er) kunne ikke læses. Filerne er bevaret i Filer → Scan3D."
                }
            } catch {
                DispatchQueue.main.async { self.libraryMessage = "Biblioteket kunne ikke læses: \(error.localizedDescription)" }
            }
        }
    }

    func resetMission() {
        guard !savingPhoto, !videoBusy else { return }
        activeProject = nil
        automaticCapture.reset()
        savedCount = 0
        lastPhotoURL = nil
        targetPoint = nil
        cloud.clear()
        depthPointsBySlot.removeAll()
        lidarPointCount = 0
        exportedCloudURL = nil
        exportedMeshURL = nil
        exportedTriangleCount = 0
        exportMessage = "Scan flere vinkler, og eksporter derefter PLY eller OBJ."
        capturedSlots.removeAll()
        retakeSlotIndex = nil
        retakeHint = "Tryk en grøn position for at tage billedet om."
        currentSlotIndex = nil
        previousCamera = nil
        previousTimestamp = nil
        stableSince = nil
        missionTargetLocked = false
        missionReady = false
        missionCoverage = Array(repeating: false, count: 36)
        missionProgress = "0/36 vinkler"
        missionNavigation = "Lås genstanden for at få næste bevægelse."
        missionCurrentSlot = "Lås genstanden for at begynde"
        missionNext = "Peg på genstanden, og tryk Lås genstand."
    }

    /// Approximate 3D target by projecting a center LiDAR depth reading along the camera forward ray.
    /// This is NOT a semantic segmentation, a calibrated object center, or an ARAnchor.
    func lockCenteredTarget() {
        guard !savingPhoto, !videoBusy else {
            guidanceText = "Afslut og gem optagelsen, før du vælger et nyt mål."
            return
        }
        guard running, let frame = session?.currentFrame else {
            guidanceText = "Start ARKit-kameraet først."
            return
        }
        guard case .normal = frame.camera.trackingState else {
            guidanceText = "Vent på stabil sporing, før du låser målet."
            return
        }
        guard let depthBuffer = frame.smoothedSceneDepth?.depthMap,
              let depth = Self.middleDepth(depthBuffer), depth >= 0.3, depth <= 2.2 else {
            guidanceText = "Peg på en synlig overflade mellem ca. 30 cm og 2,2 m."
            return
        }
        let matrix = frame.camera.transform
        let t = matrix.columns.3
        let forward = matrix.columns.2
        // Commit the new project before replacing any in-memory target/state.
        do { activeProject = try projectStore.create() }
        catch {
            guidanceText = "Kunne ikke oprette projekt: \(error.localizedDescription)"
            return
        }
        automaticCapture.reset()
        targetPoint = ScanPoint(x: Double(t.x-forward.x*depth),
                                y: Double(t.y-forward.y*depth),
                                z: Double(t.z-forward.z*depth))
        cloud.clear()
        depthPointsBySlot.removeAll()
        lidarPointCount = 0
        exportedCloudURL = nil
        exportedMeshURL = nil
        exportedTriangleCount = 0
        savedCount = 0
        lastPhotoURL = nil
        capturedSlots.removeAll()
        retakeSlotIndex = nil
        retakeHint = "Tryk en grøn position for at tage billedet om."
        missionCoverage = Array(repeating: false, count: 36)
        missionProgress = "0/36 vinkler"
        missionTargetLocked = true
        missionReady = false
        stableSince = nil
        previousCamera = nil
        currentSlotIndex = nil
        guidanceText = "Genstanden er låst cirka. Gå roligt rundt om den."
        missionNext = "Find første vinkel og hold telefonen stille."
        missionNavigation = "Ret kameraet mod genstanden, og gå roligt omkring den."
        refreshLibrary()
        if automaticVideo {
            if captureSuspended { pendingAutomaticVideoStart = true }
            else { startVideo() }
        }
    }

    func startVideo() {
        guard !videoBusy, running, !captureSuspended, let projectID = activeProject?.id else {
            videoMessage = "Lås først et objekt med kameraet aktivt."
            return
        }
        let orientation: ScanVideoOrientation
        let interface = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.interfaceOrientation
        switch interface {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        default: orientation = .portrait
        }
        videoState = .preparing
        pendingVideoStop = nil
        videoMessage = "Klargør video …"
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let (pending, url) = try self.projectStore.beginVideo(projectID: projectID)
                DispatchQueue.main.async {
                    let recorder = VideoRecorder(url: url, orientation: orientation, onFinishing: { [weak self] in
                        DispatchQueue.main.async {
                            self?.videoState = .finishing
                            self?.videoMessage = "Afslutter og kontrollerer video …"
                        }
                    }) { [weak self] result in
                        self?.completeVideo(result, projectID: projectID, videoID: pending.id, url: url)
                    }
                    self.videoRecorder = recorder
                    self.videoState = .recording
                    self.videoMessage = "Optager uden lyd · højst 5 min · retning fastlagt ved start."
                    if let reason = self.pendingVideoStop { self.stopVideo(reason: reason) }
                    else if !self.running || self.captureSuspended { self.stopVideo(reason: "captureSuspended") }
                }
            } catch {
                DispatchQueue.main.async {
                    self.videoState = .idle
                    self.videoMessage = "Video kunne ikke starte: \(error.localizedDescription)"
                    self.endVideoBackgroundTask()
                }
            }
        }
    }

    func stopVideo(reason: String = "user") {
        guard videoBusy else { return }
        if videoBackgroundTask == .invalid {
            videoBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Scan3D video finish") { [weak self] in
                self?.videoMessage = "iOS afbrød afslutningen. Kontroller den bevarede video i Mine scanninger."
                self?.endVideoBackgroundTask()
            }
        }
        if videoState == .preparing { pendingVideoStop = pendingVideoStop ?? reason; return }
        videoState = .finishing
        videoMessage = "Afslutter og kontrollerer video …"
        videoRecorder?.finish(reason: reason)
    }

    private func completeVideo(_ result: Result<VideoDetails, Error>, projectID: UUID, videoID: UUID, url: URL) {
        // This callback may run on the encoder queue. Inspection and hashing stay
        // off the main thread, including when iOS is ending a background task.
        Task.detached(priority: .userInitiated) { [self] in
            let message: String
            do {
                let encoded = try result.get()
                let checked = try await VideoFileInspector.inspect(url)
                let details = VideoDetails(width: checked.width, height: checked.height, duration: checked.duration,
                    frames: encoded.frames, firstARTimestamp: encoded.firstARTimestamp,
                    orientation: encoded.orientation, stopReason: encoded.stopReason)
                _ = try projectStore.finishVideo(projectID: projectID, videoID: videoID, details: details)
                let reason: String
                switch encoded.stopReason {
                case "lowStorage": reason = " Stoppet ved lav lagerplads."
                case "thermal": reason = " Stoppet, fordi telefonen blev varm."
                case "durationLimit": reason = " Grænsen på 5 minutter er nået."
                case "coverageComplete": reason = " Alle 36 fotovinkler er registreret."
                default: reason = ""
                }
                message = "Video gemt i Mine scanninger.\(reason)"
            } catch {
                try? projectStore.noteVideoFailure(projectID: projectID, videoID: videoID, message: error.localizedDescription)
                message = "Video ikke godkendt: \(error.localizedDescription) Se den bevarede optagelse i Mine scanninger."
            }
            await MainActor.run {
                self.videoState = .idle
                self.videoRecorder = nil
                self.pendingVideoStop = nil
                self.videoMessage = message
                self.endVideoBackgroundTask()
                self.refreshLibrary()
            }
        }
    }

    private func endVideoBackgroundTask() {
        if videoBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(videoBackgroundTask)
            videoBackgroundTask = .invalid
        }
    }

    /// A previously covered angle may be replaced once the iPhone is physically back at that slot.
    /// The requested index does NOT override ARKit slot verification or camera stability.
    func requestRetake(_ slot: Int) {
        guard !savingPhoto else { return }
        guard missionTargetLocked, MissionRetake.select(slot: slot, covered: capturedSlots) != nil else {
            retakeHint = "Lås en genstand og vælg en grøn position med et eksisterende foto."
            return
        }
        retakeSlotIndex = slot
        let selected = ScanSlot(ring: slot / 12, sector: slot % 12)
        retakeHint = "Tag om: \(selected.label). Gå tilbage til samme vinkel; foto tages kun ved grønt lys."
        missionNext = "Genfoto: \(selected.label)"
        missionReady = false
    }

    func cancelRetake() {
        retakeSlotIndex = nil
        retakeHint = "Genfotografering annulleret. Tidligere billeder er bevaret."
        missionReady = false
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        stopVideo(reason: "sessionError")
        running = false
        missionReady = false
        stableSince = nil
        needsNewCoordinateSpace = true
        trackingText = "ARKit-fejl: \(error.localizedDescription)"
    }

    func sessionWasInterrupted(_ session: ARSession) {
        stopVideo(reason: "sessionInterrupted")
        // Apple: do not pause inside this callback, or interruption-ended is lost.
        running = false
        missionReady = false
        stableSince = nil
        needsNewCoordinateSpace = true
        trackingText = "Kamera afbrudt. Projektet er bevaret."
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        trackingText = "Tryk Fortsæt og lås objektet igen. Tidligere optagelser ligger i Mine scanninger."
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async { self.trackingText = self.name(for: camera.trackingState) }
    }

    private func name(for tracking: ARCamera.TrackingState) -> String {
        switch tracking {
        case .normal: return "Position følges"
        case .notAvailable: return "Sporing ikke tilgængelig"
        case .limited: return "Begrænset sporing – bevæg telefonen langsomt"
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard Self.supportsLiDAR, running else { return }
        if videoState == .recording {
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .serious || thermal == .critical { stopVideo(reason: "thermal") }
            else if !captureSuspended { videoRecorder?.append(frame.capturedImage, timestamp: frame.timestamp) }
        }
        let t = frame.camera.transform.columns.3
        let position = SIMD3<Float>(t.x, t.y, t.z)
        let depth = frame.smoothedSceneDepth.flatMap { Self.middleDepth($0.depthMap) }
        latestPosition = position
        latestDistance = depth
        let cameraPoint = ScanPoint(x: Double(position.x), y: Double(position.y), z: Double(position.z))
        let forwardColumn = frame.camera.transform.columns.2
        let lookDirection = ScanPoint(x: -Double(forwardColumn.x),
                                      y: -Double(forwardColumn.y),
                                      z: -Double(forwardColumn.z))
        let time = frame.timestamp
        let velocity: Double
        if let last = previousCamera, let lastTime = previousTimestamp, time > lastTime {
            velocity = (cameraPoint-last).length / (time-lastTime)
        } else { velocity = Double.infinity }
        previousCamera = cameraPoint
        previousTimestamp = time
        let still = velocity < 0.13
        if !still { stableSince = nil }
        else if stableSince == nil { stableSince = time }
        let heldSteady = stableSince.map { time-$0 > 0.65 } ?? false
        if let target = targetPoint {
            let trackingGood: Bool
            if case .normal = frame.camera.trackingState { trackingGood = true } else { trackingGood = false }
            if let feedback = MissionGeometry.evaluate(camera: cameraPoint,
                 forward: lookDirection, target: target,
                 trackingGood: trackingGood, still: heldSteady) {
                currentSlotIndex = feedback.slot.index
                missionCurrentSlot = feedback.slot.label
                let alreadyCaptured = capturedSlots.contains(feedback.slot.index)
                let retakeThisSlot = MissionRetake.canCapture(slot: feedback.slot.index,
                    covered: capturedSlots, retake: retakeSlotIndex, cameraReady: feedback.ready)
                missionReady = retakeThisSlot
                guidanceText = alreadyCaptured && retakeSlotIndex != feedback.slot.index
                    ? "Denne vinkel er allerede dækket. Vælg den grønne position, hvis billedet skal tages om."
                    : feedback.ready && retakeSlotIndex == feedback.slot.index
                        ? "Klar til genfoto: \(feedback.slot.label)."
                        : feedback.instruction
                if let desired = retakeSlotIndex {
                    let retakeSlot = ScanSlot(ring: desired / 12, sector: desired % 12)
                    let route = MissionRoute.navigateTo(from: feedback.slot, target: retakeSlot)
                    missionNext = "Genfoto: \(retakeSlot.label)"
                    missionNavigation = route.message
                } else if let route = MissionRoute.navigate(from: feedback.slot, covered: capturedSlots) {
                    missionNext = "Næste ledige: \(route.target.label)."
                    missionNavigation = route.message
                } else {
                    missionNext = "Alle 36 positioner registreret – tjek billederne før 3D-behandling."
                    missionNavigation = "Missionen er dækket. Kontrollér fotos for sløring og overlap."
                }
            } else {
                missionReady = false
                guidanceText = "Flyt lidt tilbage fra den låste genstand."
            }
        } else {
            missionReady = false
        }
        if automaticCapture.shouldCapture(enabled: automaticPhotos, running: running,
            suspended: captureSuspended, saving: savingPhoto, ready: missionReady,
            slot: currentSlotIndex, covered: capturedSlots, retake: retakeSlotIndex,
            timestamp: time) {
            captureCurrentFrame()
        }
        let positionString = String(format: "X %.2f · Y %.2f · Z %.2f m", position.x, position.y, position.z)
        let distanceString = depth.map { String(format: "≈ %.2f m", $0) } ?? "Ingen gyldig dybde"
        let moveAdvice: String
        if let d = depth, d < 0.28 { moveAdvice = "Gå lidt længere fra motivet." }
        else if let d = depth, d > 1.6 { moveAdvice = "Gå lidt tættere på motivet." }
        else if depth == nil { moveAdvice = "Ret kameraet mod en synlig, ikke-blank overflade." }
        else { moveAdvice = "God afstand. Gå langsomt rundt og bevar overlap." }
        DispatchQueue.main.async {
            self.distanceText = distanceString
            self.positionText = positionString
            if self.targetPoint == nil { self.guidanceText = moveAdvice }
        }
        // Throttle Vision inference to ~1 frame/s to avoid saturating iPhone CPU/GPU.
        let timestamp = frame.timestamp
        if timestamp - lastVisionTime > 1.0 && !visionBusy {
            lastVisionTime = timestamp
            visionBusy = true
            let image = frame.capturedImage
            visionQueue.async { [weak self] in
                self?.analyze(image: image)
                DispatchQueue.main.async { self?.visionBusy = false }
            }
        }
    }

    /// Center sample, *not* a depth reading of a segmented object or calibrated measurement.
    private static func middleDepth(_ buffer: CVPixelBuffer) -> Float? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let ptr = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size
        let floats = ptr.assumingMemoryBound(to: Float32.self)
        let cx = width / 2, cy = height / 2
        var values: [Float] = []
        for y in max(0,cy-2)...min(height-1,cy+2) {
            for x in max(0,cx-2)...min(width-1,cx+2) {
                let v = floats[y*row+x]
                if v.isFinite && v > 0.05 && v < 10 { values.append(v) }
            }
        }
        if values.isEmpty { return nil }
        values.sort()
        return values[values.count/2]
    }

    private func analyze(image: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .right, options: [:])
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let labels = VNClassifyImageRequest()
        do {
            try handler.perform([foreground, labels])
            let rect = Self.foregroundRect(from: foreground.results?.first)
            // Classification is of the entire image, not guaranteed to be the masked object.
            let possible = labels.results?.first
            let caption: String
            if let possible = possible, possible.confidence >= 0.35 {
                caption = "Muligt motiv: \(possible.identifier) (\(Int(possible.confidence*100)) %)"
            } else {
                caption = rect == nil ? "Intet tydeligt forgrundsobjekt" : "Forgrundsobjekt fundet – ukendt type"
            }
            let orientation: String
            if let r = rect, r.height > r.width*1.3 { orientation = "Lodret (forslag)" }
            else if let r = rect, r.width > r.height*1.3 { orientation = "Vandret (forslag)" }
            else { orientation = "Valgfri" }
            DispatchQueue.main.async {
                self.detectedRect = rect
                self.subjectText = caption
                self.orientationText = orientation
            }
        } catch {
            DispatchQueue.main.async {
                self.subjectText = "Vision kunne ikke analysere billedet. Ret kameraet manuelt."
                self.detectedRect = nil
            }
        }
    }

    /// The low-res instance mask is used to find a rough subject region for a UI hint.
    /// No exact image-aligned overlay is claimed before testing orientation transforms on-device.
    private static func foregroundRect(from observation: VNInstanceMaskObservation?) -> CGRect? {
        guard let obs = observation, !obs.allInstances.isEmpty else { return nil }
        let mask = obs.instanceMask
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in Swift.stride(from: 0, to: h, by: 2) {
            for x in Swift.stride(from: 0, to: w, by: 2) where pixels[y*bytesPerRow+x] != 0 {
                minX = min(minX,x); maxX = max(maxX,x)
                minY = min(minY,y); maxY = max(maxY,y)
            }
        }
        guard maxX > minX && maxY > minY else { return nil }
        return CGRect(x: CGFloat(minX)/CGFloat(w), y: CGFloat(minY)/CGFloat(h),
                      width: CGFloat(maxX-minX)/CGFloat(w), height: CGFloat(maxY-minY)/CGFloat(h))
    }

    /// Save a camera frame and AR position locally; no network request or account required.
    func captureCurrentFrame() {
        guard !savingPhoto, !captureSuspended, running, missionTargetLocked, missionReady,
              let project = activeProject,
              let frame = session?.currentFrame, let target = targetPoint else {
            guidanceText = "Vent på grønt lys og låst genstand, før du tager foto."
            return
        }
        // The camera may move between the last delegate callback and a tap. Re-check
        // the actual frame to prevent mislabeled positions or accidental retakes.
        let tNow = frame.camera.transform.columns.3
        let fNow = frame.camera.transform.columns.2
        let cameraNow = ScanPoint(x:Double(tNow.x), y:Double(tNow.y), z:Double(tNow.z))
        let forwardNow = ScanPoint(x:-Double(fNow.x), y:-Double(fNow.y), z:-Double(fNow.z))
        let trackingGood: Bool
        if case .normal = frame.camera.trackingState { trackingGood = true } else { trackingGood = false }
        let captureFresh = previousTimestamp.map {
            frame.timestamp >= $0 && frame.timestamp-$0 < 0.30
        } ?? false
        let heldSteady = stableSince.map { frame.timestamp-$0 > 0.65 } ?? false
        guard captureFresh, let confirmed = CaptureValidation.approve(
            camera:cameraNow, forward:forwardNow, target:target,
            trackingGood:trackingGood, heldSteady:heldSteady,
            expectedSlot:currentSlotIndex, covered:capturedSlots, retake:retakeSlotIndex) else {
            missionReady = false
            guidanceText = "Telefonen flyttede sig, eller sporingen blev usikker. Hold stille og prøv igen."
            return
        }
        let slotKey = confirmed.slot.index
        let replacement = retakeSlotIndex == slotKey && capturedSlots.contains(slotKey)
        let metadata: [String: Any] = [
                "project_id": project.id.uuidString, "coordinate_space_id": project.coordinateSpaceID.uuidString,
                "replaces_previous_capture": replacement, "timestamp": Date().timeIntervalSince1970,
                "arkit_frame_timestamp": frame.timestamp,
                "arkit_session_position_m": [tNow.x,tNow.y,tNow.z],
                "center_depth_m": frame.smoothedSceneDepth.flatMap { Self.middleDepth($0.depthMap) } as Any? ?? NSNull(),
                "mission_slot_index": slotKey,
                "mission_ring": slotKey / 12,
                "mission_sector": slotKey % 12,
                "locked_target_arkit_world_m": targetPoint.map { [$0.x, $0.y, $0.z] } ?? [],
                "mission_alignment": "approximate, session-relative; not LiDAR-verified object identity",
                "warning": "Relative ARKit coordinates. Not a calibrated object measurement."
        ]
        let roi = CloudVertex(x: Float(target.x), y: Float(target.y), z: Float(target.z))
        let perSlotCloud = PointCollector(resolution: cloud.resolution, maxPoints: 10_000)
        let newPoints = LiDARDepthSampler.sample(frame: frame, into: perSlotCloud, target: roi)
        let samples = perSlotCloud.snapshot()
        var pendingDepth = depthPointsBySlot
        pendingDepth[slotKey] = samples
        let pendingCloud = PointCollector(resolution: cloud.resolution)
        for position in pendingDepth.keys.sorted() {
            for point in pendingDepth[position] ?? [] { pendingCloud.add(point, target: roi) }
        }
        let points = pendingCloud.snapshot()
        savingPhoto = true
        missionReady = false
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let image = CIImage(cvPixelBuffer: frame.capturedImage)
                guard let jpeg = self.ciContext.jpegRepresentation(of: image,
                    colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
                    throw ProjectStoreError.emptyFile
                }
                let saved = try self.projectStore.saveCapture(projectID: project.id, slot: slotKey,
                    jpeg: jpeg, metadata: JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]),
                    thumbnail: Self.thumbnail(jpeg), pointCloud: GeometryExport.ply(points: points))
                guard let capture = saved.currentCaptures.first(where: { $0.slot == slotKey }) else {
                    throw ProjectStoreError.invalidManifest
                }
                let url = try self.projectStore.verifiedURL(capture.photo, projectID: project.id)
                let cloudURL = try self.projectStore.verifiedURL(capture.pointCloud, projectID: project.id)
                DispatchQueue.main.async {
                    self.didSaveCapture(project: saved, slot: slotKey, replacement: replacement,
                        samples: samples, points: points, newPoints: newPoints, photoURL: url, cloudURL: cloudURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.savingPhoto = false
                    self.automaticPhotos = false
                    self.guidanceText = "Foto blev ikke registreret: \(error.localizedDescription). Automatisk foto er sat på pause."
                }
            }
        }
    }

    private static func thumbnail(_ jpeg: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private func didSaveCapture(project: ScanProject, slot: Int, replacement: Bool,
                                samples: [CloudVertex], points: [CloudVertex], newPoints: Int,
                                photoURL: URL, cloudURL: URL) {
            savingPhoto = false
            guard activeProject?.id == project.id else { refreshLibrary(); return }
            activeProject = project
            let slotKey = slot
            capturedSlots.insert(slotKey)
            retakeSlotIndex = nil
            retakeHint = replacement ? "Genfoto gemt. Originalen er bevaret i projektet." : "Vælg en dækket position for at tage billedet om."
            missionCoverage[slotKey] = true
            missionProgress = "\(capturedSlots.count)/36 vinkler"
            missionReady = false
            stableSince = nil
            if let route = MissionRoute.navigate(
                from: ScanSlot(ring:slotKey/12, sector:slotKey%12), covered:capturedSlots) {
                missionNext = "Næste: \(route.target.label)."
                missionNavigation = route.message
            } else {
                missionNext = "36/36 dækket. Gennemgå fotos, før du fortsætter."
                missionNavigation = "Alle 36 positioner dækket. Kontrollér skarphed og overlap."
                stopVideo(reason: "coverageComplete")
            }
            if !replacement { savedCount += 1 }
            // Collect only depth points corresponding to a successfully saved photo.
            // Replacing a slot also replaces its depth samples; old poor readings are not retained.
            depthPointsBySlot[slotKey] = samples
            cloud.clear()
            for point in points { cloud.add(point, target: nil) }
            lidarPointCount = cloud.count
            exportedCloudURL = cloudURL
            // A previous manual mesh export describes an older capture state.
            exportedMeshURL = nil
            exportedTriangleCount = 0
            exportMessage = "LiDAR: \(newPoints) 3D-punkter fra dette foto. Gem som PLY eller OBJ."
            lastPhotoURL = photoURL
            refreshLibrary()
    }
    /// Preserve existing export files even if a new ARKit session starts.
    /// The point cloud is session-relative, approximate and excludes textures.
    func exportPLY() {
        guard !savingPhoto, let project = activeProject, cloud.count > 0 else {
            exportMessage = "Ingen LiDAR-punkter endnu. Lås et mål, og tag fotos med stabil sporing."
            return
        }
        do {
            let url = try projectStore.saveExport(projectID: project.id,
                data: GeometryExport.ply(points: cloud.snapshot()), ext: "ply")
            exportedCloudURL = url
            exportMessage = "PLY eksporteret: \(cloud.count) virkelige LiDAR-punkter."
            refreshLibrary()
        } catch { exportMessage = "PLY kunne ikke gemmes: \(error.localizedDescription)" }
    }

    /// ARKit mesh can include nearby surfaces, even when clipped around a selected target.
    /// Export can contain holes and is not automatically 3D-printable.
    func exportOBJ() {
        guard !savingPhoto, let project = activeProject, let p = targetPoint else {
            exportMessage = "Lås først et mål med LiDAR, før du eksporterer rummets mesh."
            return
        }
        guard hasMeshSupport, let frame = session?.currentFrame else {
            exportMessage = "Ingen ARKit-mesh til rådighed. Bevæg telefonen rundt om objektet."
            return
        }
        let roi = CloudVertex(x:Float(p.x),y:Float(p.y),z:Float(p.z))
        let (data,count) = LiDARSceneMesh.export(frame:frame,target:roi)
        guard count > 0 else {
            exportMessage = "Mesh er endnu ikke opbygget i det låste område. Scan flere sider og prøv igen."
            return
        }
        do {
            let url = try projectStore.saveExport(projectID: project.id, data: data, ext: "obj")
            exportedTriangleCount = count
            exportedMeshURL = url
            exportMessage = "OBJ gemt: \(count) ARKit-trekanter. Mesh kan have huller."
            refreshLibrary()
        } catch { exportMessage = "OBJ kunne ikke gemmes: \(error.localizedDescription)" }
    }

}
