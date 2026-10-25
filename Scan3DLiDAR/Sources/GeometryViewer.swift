import CryptoKit
import RealityKit
import SwiftUI
import UIKit

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let prepared, renderFailure == nil {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["SCAN3D_STUDIO_FIXTURE"] == "1" {
                        Label("SIMULATOR — TESTDATA",systemImage:"testtube.2").font(.caption.bold()).foregroundStyle(.orange)
                    }
                    #endif
                    GeometryViewport(prepared: prepared, camera: $camera, lightBackground: lightBackground,
                        onFailure: { renderFailure = $0 })
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
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
                    Toggle("Lys baggrund", isOn: $lightBackground)
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
        view.accessibilityLabel = "3D-visning af projektets målte geometri. Brug dreje- og zoomknapperne nedenunder."
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "geometry-viewport"
        let coordinator = context.coordinator
        coordinator.renderView=view
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
        let pan=UIPanGestureRecognizer(target:coordinator,action:#selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches=1
        let pinch=UIPinchGestureRecognizer(target:coordinator,action:#selector(Coordinator.pinch(_:)))
        view.modelGestures=[pan,pinch]
        view.addGestureRecognizer(pan);view.addGestureRecognizer(pinch)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.updateCamera()
        context.coordinator.updateAppearance(view)
        (view as? GeometryARView)?.prioritizeModelGestures()
    }
    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) { view.scene.anchors.removeAll() }

    final class Coordinator: NSObject {
        var owner: GeometryViewport
        let cameraEntity = PerspectiveCamera()
        weak var renderView:ARView?
        var modelEntity:ModelEntity?
        private var appliedLightBackground:Bool?
        init(_ owner: GeometryViewport) { self.owner = owner }
        func updateCamera() {
            cameraEntity.look(at: .zero, from: owner.camera.position, relativeTo: nil)
            // Keep the UIKit bridge's semantics stable across SwiftUI updates and direct gestures.
            renderView?.isAccessibilityElement=true
            renderView?.accessibilityIdentifier="geometry-viewport"
            renderView?.accessibilityLabel="3D-visning af projektets målte geometri. Brug dreje- og zoomknapperne nedenunder."
            renderView?.accessibilityValue=String(format:"Visningszoom %.1f gange. Drejning %.0f grader. Hældning %.0f grader.",
                4.5/owner.camera.distance,owner.camera.yaw*180 / .pi,owner.camera.pitch*180 / .pi)
        }
        func updateAppearance(_ view:ARView) {
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
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            let delta = gesture.translation(in: gesture.view)
            owner.camera.rotate(horizontal: -Float(delta.x) * 0.008, vertical: Float(delta.y) * 0.008)
            gesture.setTranslation(.zero, in: gesture.view)
            updateCamera()
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
            owner.camera.zoom(by: Float(gesture.scale))
            gesture.scale = 1
            updateCamera()
        }
    }
}
