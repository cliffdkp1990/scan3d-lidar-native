import CryptoKit
import Combine
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
        .accessibilityIdentifier("geometry-scroll")
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
    private var previousTranslation:CGPoint = .zero
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
        // Quick simulator/device swipes can be recognized only at .ended.
        // Prefer the touch displacement, but fall back to UIKit's cumulative translation.
        let touchDelta:CGPoint
        if let previousPoint,let latestPoint {
            touchDelta=CGPoint(x:latestPoint.x-previousPoint.x,y:latestPoint.y-previousPoint.y)
            self.previousPoint=latestPoint
        } else { touchDelta = .zero }
        let current=translation(in:view)
        let translationDelta=CGPoint(x:current.x-previousTranslation.x,y:current.y-previousTranslation.y)
        previousTranslation=current
        if abs(touchDelta.x)+abs(touchDelta.y)>0.5 { return touchDelta }
        return translationDelta
    }
    override func reset() {
        super.reset()
        trackedTouch=nil;previousPoint=nil;latestPoint=nil;previousTranslation = .zero
    }
}

/// Gestures beginning inside the model operate on it; scroll outside it to move the page.
private final class GeometryRenderView:UIView {
    let renderer=ARView(frame:.zero,cameraMode:.nonAR,automaticallyConfigureSession:false)
    var modelGestures:[UIGestureRecognizer]=[] { didSet { prioritizeModelGestures() } }
    private weak var coordinatedScrollView:UIScrollView?
    override init(frame:CGRect) {
        super.init(frame:frame)
        // Keep the live Metal view and its rounded clipping within the same UIKit hierarchy.
        clipsToBounds=true;layer.cornerRadius=20
        backgroundColor = .black
        renderer.isUserInteractionEnabled=false
        renderer.frame=bounds
        renderer.autoresizingMask=[.flexibleWidth,.flexibleHeight]
        addSubview(renderer)
        isMultipleTouchEnabled=true
    }
    required init?(coder:NSCoder) { fatalError("GeometryRenderView is created programmatically") }
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
        renderer.frame=bounds
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
    func makeUIView(context: Context) -> GeometryRenderView {
        let surface=GeometryRenderView(frame:.zero)
        let view=surface.renderer
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
            coordinator.renderSubscription=view.scene.subscribe(to:SceneEvents.Update.self) { [weak coordinator,weak view] _ in
                guard let coordinator,let view else { return }
                coordinator.frameUpdated(view)
            }
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { onFailure(message) }
        }
        let pan=GeometryPanGesture(target:coordinator,action:#selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches=1
        let pinch=UIPinchGestureRecognizer(target:coordinator,action:#selector(Coordinator.pinch(_:)))
        surface.modelGestures=[pan,pinch]
        surface.addGestureRecognizer(pan);surface.addGestureRecognizer(pinch)
        return surface
    }
    func updateUIView(_ surface:GeometryRenderView, context: Context) {
        let view=surface.renderer
        geometryTrace("update view=\(ObjectIdentifier(view)) coordinator=\(ObjectIdentifier(context.coordinator)) light=\(lightBackground) yaw=\(camera.yaw) distance=\(camera.distance)")
        context.coordinator.owner = self
        context.coordinator.renderNeedsUpdate=true
        context.coordinator.updateCamera()
        context.coordinator.updateAppearance(view)
        surface.prioritizeModelGestures()
    }
    static func dismantleUIView(_ surface:GeometryRenderView, coordinator: Coordinator) {
        let view=surface.renderer
        geometryTrace("dismantle view=\(ObjectIdentifier(view)) coordinator=\(ObjectIdentifier(coordinator))")
        coordinator.renderSubscription?.cancel();coordinator.renderSubscription=nil
        view.scene.anchors.removeAll()
    }

    final class Coordinator: NSObject {
        var owner: GeometryViewport
        let cameraEntity = PerspectiveCamera()
        var modelEntity:ModelEntity?
        var renderSubscription:(any Cancellable)?
        var renderNeedsUpdate=true
        private var frameCount=0
        private var appliedLightBackground:Bool?
        init(_ owner: GeometryViewport) { self.owner = owner }
        func updateCamera() {
            cameraEntity.look(at: .zero, from: owner.camera.position, relativeTo: nil)
        }
        func frameUpdated(_ view:ARView) {
            frameCount += 1
            if renderNeedsUpdate {
                // Apply state at the engine's frame boundary as well as the UIKit update.
                updateCamera();updateAppearance(view,force:true);renderNeedsUpdate=false
            }
            if frameCount==1 || frameCount%600==0 {
                geometryTrace("render frame=\(frameCount) attached=\(view.window != nil) active=\(modelEntity?.isActive ?? false) bounds=\(view.bounds)")
            }
        }
        func updateAppearance(_ view:ARView,force:Bool=false) {
            geometryTrace("appearance view=\(ObjectIdentifier(view)) light=\(owner.lightBackground) applied=\(String(describing:appliedLightBackground))")
            guard force || appliedLightBackground != owner.lightBackground else { return }
            appliedLightBackground=owner.lightBackground
            // Fixed canvas colors honor this user choice even when the app chrome uses dark appearance.
            let canvas=owner.lightBackground ? UIColor(white:0.94,alpha:1) : UIColor.black
            view.environment.background = .color(canvas)
            // Mirror the chosen canvas behind the Metal layer so a non-opaque
            // RealityKit frame cannot briefly reveal the stale dark background.
            view.backgroundColor = canvas
            view.superview?.backgroundColor = canvas
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
            renderNeedsUpdate=true
            updateCamera()
            geometryTrace("pan afterYaw=\(owner.camera.yaw)")
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            owner.camera.zoom(by: Float(gesture.scale))
            renderNeedsUpdate=true
            gesture.scale = 1
            updateCamera()
        }
    }
}
