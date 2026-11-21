import CryptoKit
import MetalKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Isolated Simulator diagnostics; never records user captures or runs in Release.
#if DEBUG
private let geometryTraceQueue=DispatchQueue(label:"dk.scan3d.synthetic-viewer-trace",qos:.utility)
#endif
private func geometryTrace(_ message:@autoclosure()->String) {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["SCAN3D_STUDIO_FIXTURE"]=="1" else { return }
    let data=Data("\(Date().timeIntervalSince1970) \(message())\n".utf8)
    geometryTraceQueue.async {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("Scan3D-Viewer-Trace.log")
        if let file=try? FileHandle(forWritingTo:url) {
            defer { try? file.close() }
            if let size=try? file.seekToEnd(),size<1024*1024 { try? file.write(contentsOf:data) }
        } else { try? data.write(to:url,options:.atomic) }
    }
    #endif
}

private struct PreparedGeometry {
    let geometry: GeometryPreview
    let positions: [SIMD3<Float>]
    let indices: [UInt32]
    let displayedPoints: Int
    let url: URL
}

/// Opens immutable, hash-checked project data without starting an AR camera session.
struct StoredGeometryViewer: View {
    let file: StoredScanFile
    let projectID: UUID
    let store: ProjectStore
    @State private var prepared: PreparedGeometry?
    @State private var failure: String?
    @State private var renderFailure: String?
    @State private var camera = GeometryCamera()
    @State private var lightBackground = false
    private var cameraAccessibilityValue:String {
        String(format:"Visningszoom %.1f gange. Drejning %.0f grader. Hældning %.0f grader.",
            4.5/camera.distance,camera.yaw*180 / .pi,camera.pitch*180 / .pi)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let prepared, renderFailure == nil {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["SCAN3D_STUDIO_FIXTURE"] == "1" {
                        Label("SIMULATOR — TESTDATA",systemImage:"testtube.2").font(.caption.bold()).foregroundStyle(.orange)
                    }
                    #endif
                    ZStack {
                        GeometryViewport(prepared: prepared, camera: $camera, lightBackground: lightBackground,
                            onFailure: { renderFailure = $0 },
                            onCameraChange: { camera = $0 }).accessibilityHidden(true)
                    }
                        .frame(height: 340)
                        .accessibilityElement(children:.ignore)
                        .accessibilityHidden(false)
                        .accessibilityIdentifier("geometry-viewport")
                        .accessibilityLabel("3D-visning af projektets målte geometri. Brug dreje- og zoomknapperne nedenunder.")
                        .accessibilityValue(cameraAccessibilityValue)
                    HStack(spacing: 10) {
                        Button { camera.rotate(horizontal: -0.3) } label: { Image(systemName: "arrow.left") }
                            .accessibilityLabel("Drej modellen til venstre")
                        Button { camera.rotate(horizontal: 0.3) } label: { Image(systemName: "arrow.right") }
                            .accessibilityLabel("Drej modellen til højre")
                        Button { camera.rotate(horizontal: 0, vertical: 0.2) } label: { Image(systemName: "arrow.up") }
                            .accessibilityLabel("Se modellen mere fra oven")
                        Button { camera.rotate(horizontal: 0, vertical: -0.2) } label: { Image(systemName: "arrow.down") }
                            .accessibilityLabel("Se modellen mere nedefra")
                    }.buttonStyle(.bordered).controlSize(.large)
                    HStack(spacing: 10) {
                        Button { camera.zoom(by: 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                            .accessibilityLabel("Zoom ind")
                        Button { camera.zoom(by: 1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                            .accessibilityLabel("Zoom ud")
                        Button { camera = GeometryCamera() } label: { Image(systemName: "arrow.counterclockwise") }
                            .accessibilityLabel("Nulstil 3D-visning")
                    }.buttonStyle(.bordered).controlSize(.large)
                    Text("Træk for at dreje. Knib for at zoome. Knapperne kan også bruges med VoiceOver.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing:12) {
                        Button { lightBackground=false } label: {
                            Label("Mørk baggrund",systemImage:"moon.fill").frame(maxWidth:.infinity,minHeight:44)
                        }
                        .accessibilityLabel("Mørk baggrund")
                        .accessibilityValue(lightBackground ? "Ikke valgt":"Valgt")
                        .accessibilityIdentifier("geometry-dark-background")
                        .tint(lightBackground ? .gray:.teal)
                        Button { lightBackground=true } label: {
                            Label("Lys baggrund",systemImage:"sun.max.fill").frame(maxWidth:.infinity,minHeight:44)
                        }
                        .accessibilityLabel("Lys baggrund")
                        .accessibilityValue(lightBackground ? "Valgt":"Ikke valgt")
                        .accessibilityIdentifier("geometry-light-background")
                        .tint(lightBackground ? .teal:.gray)
                    }.buttonStyle(.bordered)
                    .onChange(of:lightBackground) { _,value in geometryTrace("toggle light=\(value)") }
                    Text(prepared.geometry.isPointCloud ? "Målte LiDAR-punkter" : "Målt LiDAR-mesh")
                        .font(.title2.bold())
                    if prepared.geometry.isPointCloud {
                        Text("\(prepared.geometry.vertices.count) gemte punkter · \(prepared.displayedPoints) vist. Punkterne vises som små markører, ikke en sammenhængende overflade. Originalfilen ændres ikke.")
                            .font(.subheadline)
                            .accessibilityIdentifier("stored-point-count")
                    } else {
                        Text("\(prepared.geometry.triangles.count / 3) trekanter · \(prepared.geometry.vertices.count) anvendte hjørner")
                            .font(.subheadline)
                    }
                    let size = prepared.geometry.sizeMeters
                    Text(String(format: "Udstrækning i AR-koordinater: %.1f × %.1f × %.1f cm", size.x * 100, size.y * 100, size.z * 100))
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Størrelsen er vejledende LiDAR-data. Visningen tilpasses skærmen; originalens koordinater er i meter. Ingen automatisk objektisolering, tekstur, hulreparation eller garanti for 3D-print.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ShareLink(item: prepared.url) { Label("Del original 3D-fil", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent)
                } else if let error = renderFailure ?? failure {
                    ContentUnavailableView("Kan ikke vise 3D-filen", systemImage: "exclamationmark.triangle",
                        description: Text(error))
                } else {
                    ProgressView("Kontrollerer og åbner 3D-data …").frame(maxWidth: .infinity, minHeight: 240)
                }
            }.padding()
        }
        .navigationTitle("Din scanning i 3D").navigationBarTitleDisplayMode(.inline)
        .task(id: file.sha256) {
            prepared = nil; failure = nil; renderFailure = nil; camera = GeometryCamera()
            let storedFile = file, storedProjectID = projectID, projectStore = store
            let loading = Task.detached(priority: .userInitiated) { () throws -> PreparedGeometry in
                guard storedFile.bytes <= GeometryPreview.maxBytes else { throw GeometryPreviewError.tooLarge }
                let url = try projectStore.fileURL(storedFile, projectID: storedProjectID)
                let data = try GeometryPreview.read(url)
                guard data.count == storedFile.bytes,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == storedFile.sha256 else {
                    throw ProjectStoreError.damagedFile(storedFile.name)
                }
                try Task.checkCancellation()
                let geometry = try GeometryPreview.parse(data, extension: url.pathExtension)
                let mesh = try geometry.displayGeometry()
                return PreparedGeometry(geometry: geometry, positions: mesh.positions, indices: mesh.indices,
                    displayedPoints: mesh.displayedPoints, url: url)
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await loading.value },
                    onCancel: { loading.cancel() })
                guard !Task.isCancelled else { return }
                prepared = result
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }
}

/// A continuous one-finger orbit recognizer. Preserve the initial-to-final delta even
/// when UIKit coalesces a short drag into its last event; two fingers belong to pinch.
private final class GeometryPanGesture: UIGestureRecognizer {
    private var trackedTouch: UITouch?
    private var previousPoint: CGPoint?
    private var latestPoint: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled; return
        }
        trackedTouch = touch
        previousPoint = touch.location(in: view); latestPoint = previousPoint
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        updatePoint(touches)
        guard let previousPoint, let latestPoint else { return }
        if state == .possible {
            if hypot(latestPoint.x-previousPoint.x, latestPoint.y-previousPoint.y) >= 6 { state = .began }
        } else if state == .began || state == .changed { state = .changed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        updatePoint(touches)
        if state == .possible, let previousPoint, let latestPoint,
           hypot(latestPoint.x-previousPoint.x, latestPoint.y-previousPoint.y) >= 6 { state = .began }
        state = state == .began || state == .changed ? .ended : .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }
    private func updatePoint(_ touches: Set<UITouch>) {
        if let touch = trackedTouch, touches.contains(touch) { latestPoint = touch.location(in: view) }
    }
    func consumeDelta() -> CGPoint {
        guard let previousPoint, let latestPoint else { return .zero }
        self.previousPoint = latestPoint
        return CGPoint(x: latestPoint.x-previousPoint.x, y: latestPoint.y-previousPoint.y)
    }
    override func reset() {
        super.reset(); trackedTouch = nil; previousPoint = nil; latestPoint = nil
    }
}

/// Gestures beginning inside the model operate on it; scroll outside it to move the page.
private final class GeometryRenderView: UIView {
    let renderer = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    var modelGestures: [UIGestureRecognizer] = [] { didSet { prioritizeModelGestures() } }
    private weak var coordinatedScrollView: UIScrollView?
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true; layer.cornerRadius = 20
        renderer.isUserInteractionEnabled = false
        renderer.frame = bounds
        renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        renderer.colorPixelFormat = .bgra8Unorm_srgb
        renderer.depthStencilPixelFormat = .depth32Float
        renderer.sampleCount = renderer.device?.supportsTextureSampleCount(4) == true ? 4 : 1
        renderer.isPaused = true; renderer.enableSetNeedsDisplay = true
        renderer.framebufferOnly = true
        addSubview(renderer); isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError("GeometryRenderView is created programmatically") }
    override func didMoveToWindow() {
        super.didMoveToWindow(); prioritizeModelGestures(); renderer.setNeedsDisplay()
    }
    override func didMoveToSuperview() { super.didMoveToSuperview(); prioritizeModelGestures() }
    override func layoutSubviews() {
        super.layoutSubviews(); renderer.frame = bounds
        prioritizeModelGestures(); renderer.setNeedsDisplay()
    }
    func prioritizeModelGestures() {
        guard !modelGestures.isEmpty else { return }
        var ancestor = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                if coordinatedScrollView !== scroll {
                    for gesture in modelGestures { scroll.panGestureRecognizer.require(toFail: gesture) }
                    coordinatedScrollView = scroll
                }
                return
            }
            ancestor = current.superview
        }
        coordinatedScrollView = nil
    }
}

private struct GeometryViewport: UIViewRepresentable {
    let prepared: PreparedGeometry
    @Binding var camera: GeometryCamera
    let lightBackground: Bool
    let onFailure: (String) -> Void
    /// Keep UIKit gesture-driven camera changes in the SwiftUI state owner, too.
    /// This keeps the renderer and VoiceOver's viewport value synchronized.
    let onCameraChange: (GeometryCamera) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> GeometryRenderView {
        let surface = GeometryRenderView(frame: .zero)
        let coordinator = context.coordinator
        do {
            let renderer = try GeometryMetalRenderer(view: surface.renderer,
                positions: prepared.positions, indices: prepared.indices)
            coordinator.renderer = renderer
            surface.renderer.delegate = renderer
            coordinator.surface = surface
            coordinator.updateRenderer()
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { onFailure(message) }
        }
        let pan = GeometryPanGesture(target: coordinator, action: #selector(Coordinator.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
        surface.modelGestures = [pan, pinch]
        surface.addGestureRecognizer(pan); surface.addGestureRecognizer(pinch)
        return surface
    }
    func updateUIView(_ surface: GeometryRenderView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.updateRenderer()
        surface.prioritizeModelGestures()
    }
    static func dismantleUIView(_ surface: GeometryRenderView, coordinator: Coordinator) {
        surface.renderer.delegate = nil; coordinator.renderer = nil
        surface.renderer.releaseDrawables()
    }
    final class Coordinator: NSObject {
        var owner: GeometryViewport
        var renderer: GeometryMetalRenderer?
        weak var surface: GeometryRenderView?
        init(_ owner: GeometryViewport) { self.owner = owner }
        func updateRenderer() {
            renderer?.camera = owner.camera
            renderer?.lightBackground = owner.lightBackground
            surface?.renderer.setNeedsDisplay()
        }
        @objc func pan(_ gesture: GeometryPanGesture) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            let delta = gesture.consumeDelta()
            geometryTrace("orbit state=\(gesture.state.rawValue) delta=\(delta)")
            var next = owner.camera
            next.rotate(horizontal: -Float(delta.x)*0.008, vertical: Float(delta.y)*0.008)
            renderer?.camera = next
            surface?.renderer.setNeedsDisplay()
            owner.onCameraChange(next)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            var next = owner.camera
            next.zoom(by: Float(gesture.scale)); gesture.scale = 1
            gesture.scale = 1
            renderer?.camera = next
            surface?.renderer.setNeedsDisplay()
            owner.onCameraChange(next)
        }
    }
}
