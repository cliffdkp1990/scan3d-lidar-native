import CryptoKit
import RealityKit
import SwiftUI
import UIKit

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
                            onFailure: { renderFailure = $0 }).accessibilityHidden(true)
                    }
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .accessibilityElement(children:.ignore)
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
                let mesh = try geometry.displayMesh()
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

/// Keep the finger's initial position even when recognition is delayed until the last move.
/// Simulator traces exposed a quick gesture with only .began/.ended and zero UIKit translation.
private final class GeometryPanGesture:UIPanGestureRecognizer {
    private var trackedTouch:UITouch?
    private var previousPoint:CGPoint?
    private var latestPoint:CGPoint?
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
        if trackedTouch == nil,let touch=touches.first {
            trackedTouch=touch
            let point=touch.location(in:view)
            previousPoint=point;latestPoint=point
            geometryTrace("pan touch origin=\(point)")
        }
        super.touchesBegan(touches,with:event)
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
        updatePoint(touches)
        super.touchesMoved(touches,with:event)
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
        updatePoint(touches)
        super.touchesEnded(touches,with:event)
    }
    private func updatePoint(_ touches:Set<UITouch>) {
        if let touch=trackedTouch,touches.contains(touch) { latestPoint=touch.location(in:view) }
    }
    func consumeDelta()->CGPoint {
        guard let previousPoint,let latestPoint else { return .zero }
        self.previousPoint=latestPoint
        return CGPoint(x:latestPoint.x-previousPoint.x,y:latestPoint.y-previousPoint.y)
    }
    override func reset() {
        super.reset()
        trackedTouch=nil;previousPoint=nil;latestPoint=nil
    }
}

/// Gestures beginning inside the model operate on it; scroll outside it to move the page.
private final class GeometryARView:ARView {
    var modelGestures:[UIGestureRecognizer]=[] { didSet { prioritizeModelGestures() } }
    private weak var coordinatedScrollView:UIScrollView?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        prioritizeModelGestures()
    }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        prioritizeModelGestures()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        prioritizeModelGestures()
    }
    func prioritizeModelGestures() {
        guard !modelGestures.isEmpty else { return }
        var ancestor=superview
        while let current=ancestor {
            if let scroll=current as? UIScrollView {
                if coordinatedScrollView !== scroll {
                    for gesture in modelGestures { scroll.panGestureRecognizer.require(toFail:gesture) }
                    coordinatedScrollView=scroll
                }
                return
            }
            ancestor=current.superview
        }
        coordinatedScrollView=nil
    }
}

private struct GeometryViewport: UIViewRepresentable {
    let prepared: PreparedGeometry
    @Binding var camera: GeometryCamera
    let lightBackground: Bool
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ARView {
        let view = GeometryARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions=[.disableCameraGrain,.disableMotionBlur,.disableDepthOfField]
        let coordinator = context.coordinator
        geometryTrace("make view=\(ObjectIdentifier(view)) coordinator=\(ObjectIdentifier(coordinator)) inputLight=\(lightBackground) ownerLight=\(coordinator.owner.lightBackground)")
        let anchor = AnchorEntity(world: .zero)
        do {
            var descriptor = MeshDescriptor(name: "Scan3D stored geometry")
            descriptor.positions = MeshBuffers.Positions(prepared.positions)
            descriptor.primitives = .triangles(prepared.indices)
            let mesh = try MeshResource.generate(from: [descriptor])
            let model=ModelEntity(mesh:mesh,materials:[])
            coordinator.modelEntity=model
            coordinator.updateAppearance(view)
            anchor.addChild(model)
            let light = DirectionalLight()
            light.light.intensity = 2500
            light.look(at: .zero, from: [2,3,4], relativeTo: nil)
            anchor.addChild(light)
            let fill = DirectionalLight()
            fill.light.intensity = 1200
            fill.look(at: .zero, from: [-3,1,-2], relativeTo: nil)
            anchor.addChild(fill)
            coordinator.cameraEntity.camera.fieldOfViewInDegrees = 50
            coordinator.cameraEntity.camera.near = 0.01
            coordinator.cameraEntity.camera.far = 50
            anchor.addChild(coordinator.cameraEntity)
            view.scene.addAnchor(anchor)
            coordinator.updateCamera()
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { onFailure(message) }
        }
        let pan=GeometryPanGesture(target:coordinator,action:#selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches=1
        let pinch=UIPinchGestureRecognizer(target:coordinator,action:#selector(Coordinator.pinch(_:)))
        view.modelGestures=[pan,pinch]
        view.addGestureRecognizer(pan);view.addGestureRecognizer(pinch)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        geometryTrace("update view=\(ObjectIdentifier(view)) coordinator=\(ObjectIdentifier(context.coordinator)) light=\(lightBackground) yaw=\(camera.yaw) distance=\(camera.distance)")
        context.coordinator.owner = self
        context.coordinator.updateCamera()
        context.coordinator.updateAppearance(view)
        (view as? GeometryARView)?.prioritizeModelGestures()
    }
    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        geometryTrace("dismantle view=\(ObjectIdentifier(view)) coordinator=\(ObjectIdentifier(coordinator))")
        view.scene.anchors.removeAll()
    }

    final class Coordinator: NSObject {
        var owner: GeometryViewport
        let cameraEntity = PerspectiveCamera()
        var modelEntity:ModelEntity?
        private var appliedLightBackground:Bool?
        init(_ owner: GeometryViewport) { self.owner = owner }
        func updateCamera() {
            cameraEntity.look(at: .zero, from: owner.camera.position, relativeTo: nil)
        }
        func updateAppearance(_ view:ARView) {
            geometryTrace("appearance view=\(ObjectIdentifier(view)) light=\(owner.lightBackground) applied=\(String(describing:appliedLightBackground))")
            guard appliedLightBackground != owner.lightBackground else { return }
            appliedLightBackground=owner.lightBackground
            // Fixed canvas colors honor this user choice even when the app chrome uses dark appearance.
            view.environment.background = .color(owner.lightBackground ? UIColor(white:0.94,alpha:1):UIColor.black)
            let tint=owner.lightBackground ? UIColor(red:0.04,green:0.35,blue:0.41,alpha:1):UIColor.systemTeal
            if owner.prepared.geometry.isPointCloud {
                modelEntity?.model?.materials=[UnlitMaterial(color:tint)]
            } else {
                var material=PhysicallyBasedMaterial()
                material.baseColor = .init(tint:tint)
                material.roughness = .init(floatLiteral:0.8)
                material.faceCulling = .none
                modelEntity?.model?.materials=[material]
            }
        }
        @objc func pan(_ gesture: GeometryPanGesture) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            let delta=gesture.consumeDelta()
            geometryTrace("pan state=\(gesture.state.rawValue) delta=\(delta) beforeYaw=\(owner.camera.yaw)")
            owner.camera.rotate(horizontal: -Float(delta.x) * 0.008, vertical: Float(delta.y) * 0.008)
            updateCamera()
            geometryTrace("pan afterYaw=\(owner.camera.yaw)")
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            owner.camera.zoom(by: Float(gesture.scale))
            gesture.scale = 1
            updateCamera()
        }
    }
}
