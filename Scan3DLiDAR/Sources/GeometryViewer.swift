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

private struct GeometryViewport: UIViewRepresentable {
    let prepared: PreparedGeometry
    @Binding var camera: GeometryCamera
    let lightBackground: Bool
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(lightBackground ? .systemGray6 : .black)
        view.accessibilityLabel = "3D-visning af projektets målte geometri. Brug dreje- og zoomknapperne nedenunder."
        view.isAccessibilityElement = true
        let coordinator = context.coordinator
        let anchor = AnchorEntity(world: .zero)
        do {
            var descriptor = MeshDescriptor(name: "Scan3D stored geometry")
            descriptor.positions = MeshBuffers.Positions(prepared.positions)
            descriptor.primitives = .triangles(prepared.indices)
            let mesh = try MeshResource.generate(from: [descriptor])
            if prepared.geometry.isPointCloud {
                anchor.addChild(ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .systemTeal)]))
            } else {
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: .systemTeal)
                material.roughness = .init(floatLiteral: 0.8)
                material.faceCulling = .none
                anchor.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
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
        view.addGestureRecognizer(UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:))))
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.updateCamera()
        view.environment.background = .color(lightBackground ? .systemGray6 : .black)
    }
    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) { view.scene.anchors.removeAll() }

    final class Coordinator: NSObject {
        var owner: GeometryViewport
        let cameraEntity = PerspectiveCamera()
        init(_ owner: GeometryViewport) { self.owner = owner }
        func updateCamera() { cameraEntity.look(at: .zero, from: owner.camera.position, relativeTo: nil) }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let delta = gesture.translation(in: gesture.view)
            owner.camera.rotate(horizontal: -Float(delta.x) * 0.008, vertical: Float(delta.y) * 0.008)
            gesture.setTranslation(.zero, in: gesture.view)
            updateCamera()
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            owner.camera.zoom(by: Float(gesture.scale))
            gesture.scale = 1
            updateCamera()
        }
    }
}
