import ARKit
import RealityKit
import SwiftUI

/// The same ARView survives layout changes and reports its actual viewport.
final class CaptureARView: ARView {
    weak var scanEngine: ScanEngine?
    override func layoutSubviews() {
        super.layoutSubviews()
        scanEngine?.updateViewport(size:bounds.size,orientation:window?.windowScene?.interfaceOrientation ?? .portrait)
    }
}
struct LiDARCameraView: UIViewRepresentable {
    @ObservedObject var engine: ScanEngine
    func makeUIView(context:Context)->CaptureARView {
        let view=CaptureARView(frame:.zero,cameraMode:.ar,automaticallyConfigureSession:false)
        view.scanEngine=engine
        view.environment.sceneUnderstanding.options=[]
        view.renderOptions=[.disableCameraGrain,.disableMotionBlur,.disableDepthOfField]
        view.debugOptions=engine.showWireframe ? [.showSceneUnderstanding] : []
        DispatchQueue.main.async { [weak engine=engine,weak view] in
            guard let engine,let view else { return }
            engine.start(using:view.session)
        }
        return view
    }
    func updateUIView(_ view:CaptureARView,context:Context) {
        view.debugOptions=engine.showWireframe ? [.showSceneUnderstanding] : []
        engine.updateViewport(size:view.bounds.size,orientation:view.window?.windowScene?.interfaceOrientation ?? .portrait)
    }
    static func dismantleUIView(_ view:CaptureARView,coordinator:()) {
        view.session.pause()
        let session=view.session
        let engine=view.scanEngine
        DispatchQueue.main.async { [weak engine] in if engine?.session === session { engine?.stop() } }
    }
}

private enum Atelier {
    static let ink = Color(red:0.035,green:0.055,blue:0.075)
    static let violet = Color(red:0.39,green:0.77,blue:0.85)
    static let rose = Color(red:0.55,green:0.95,blue:0.82)
    static let cream = Color(red:0.98,green:0.95,blue:1.0)
    static let muted = Color(red:0.77,green:0.73,blue:0.86)
}

struct ContentView: View {
    @StateObject private var engine = ScanEngine()
    @State private var resultSheet = false
    @State private var retakeSheet = false
    @State private var librarySheet = false
    @State private var newTargetConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            CaptureStudioView(engine:engine,size:geometry.size,
                onLibrary:{librarySheet=true;engine.refreshLibrary()},
                onResult:{resultSheet=true},onRetake:{retakeSheet=true},
                onNewTarget:{if engine.missionTargetLocked {newTargetConfirmation=true} else {engine.lockCenteredTarget()}})
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented:$resultSheet) { resultView.presentationDragIndicator(.visible) }
        .sheet(isPresented:$retakeSheet) { retakeView.presentationDragIndicator(.visible) }
        .sheet(isPresented:$librarySheet) { ScanLibraryView(engine: engine) }
        .onAppear { engine.prepareStudioFixtureIfNeeded(); engine.refreshLibrary() }
        .onChange(of:resultSheet) { _,_ in updateCaptureSuspension() }
        .onChange(of:retakeSheet) { _,_ in updateCaptureSuspension() }
        .onChange(of:librarySheet) { _,_ in updateCaptureSuspension() }
        .onChange(of:newTargetConfirmation) { _,_ in updateCaptureSuspension() }
        .onChange(of:engine.automaticVideo) { _,enabled in
            if enabled && engine.missionTargetLocked { engine.startVideo() }
            else if !enabled { engine.stopVideo() }
        }
        .confirmationDialog("Starte en ny scanning?",isPresented:$newTargetConfirmation,titleVisibility:.visible) {
            Button("Lås nyt mål og nulstil mission",role:.destructive) { engine.lockCenteredTarget() }
        } message: {
            Text("Gemte fotos og punktsky bevares i Mine scanninger. Et nyt mål får sit eget projekt.")
        }
        .onChange(of:scenePhase) { _,next in
            updateCaptureSuspension()
            if next == .background { engine.stop() }
        }
        .sensoryFeedback(.success,trigger:engine.savedCount)
    }

    private func updateCaptureSuspension() {
        engine.suspendCapture(scenePhase != .active || resultSheet || retakeSheet || librarySheet || newTargetConfirmation)
    }

    private var resultView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ZStack {
                        RoundedRectangle(cornerRadius:26)
                            .fill(LinearGradient(colors:[Atelier.violet.opacity(0.35),Atelier.ink],startPoint:.topLeading,endPoint:.bottomTrailing))
                        VStack(spacing:14) {
                            Image(systemName:"cube.transparent.fill")
                                .font(.system(size:68,weight:.ultraLight))
                                .foregroundStyle(Atelier.rose)
                            Text("Optagelser og eksport")
                                .font(.title2.bold())
                            Text("\(engine.lidarPointCount) LiDAR-punkter  ·  \(engine.savedCount) fotos")
                                .font(.footnote).foregroundStyle(Atelier.muted)
                        }
                    }.frame(height:235)
                    Text("Eksportér din scanning")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Button { engine.exportPLY() } label: {
                        Label("Gem punktsky som PLY",systemImage:"circle.hexagongrid.fill")
                            .frame(maxWidth:.infinity,minHeight:51)
                    }
                    .buttonStyle(.borderedProminent).tint(Atelier.rose)
                    .disabled(engine.savingPhoto)
                    Button { engine.exportOBJ() } label: {
                        Label("Gem 3D-mesh som OBJ",systemImage:"square.3.layers.3d")
                            .frame(maxWidth:.infinity,minHeight:51)
                    }
                    .buttonStyle(.bordered).tint(Atelier.rose)
                    .disabled(engine.savingPhoto)
                    Text(engine.exportMessage).font(.subheadline).foregroundStyle(Atelier.muted)
                    if let project = engine.projects.first(where: { $0.id == engine.activeProject?.id }),
                       let model = project.exports.last?.file ?? project.captures.last?.pointCloud {
                        NavigationLink {
                            StoredGeometryViewer(file: model, projectID: project.id, store: engine.projectStore)
                        } label: {
                            Label("Se seneste gemte 3D-data", systemImage: "view.3d")
                            .frame(maxWidth: .infinity, minHeight: 51)
                        }.buttonStyle(.bordered).tint(Atelier.rose)
                        SafariProjectShare(project: project, store: engine.projectStore, synthetic: engine.isStudioFixture)
                    }
                    if let file = engine.exportedCloudURL {
                        ShareLink(item:file) { Label("Del PLY-fil",systemImage:"square.and.arrow.up") }
                            .font(.subheadline.bold()).tint(Atelier.rose)
                    }
                    if let file = engine.exportedMeshURL {
                        ShareLink(item:file) { Label("Del OBJ-fil",systemImage:"square.and.arrow.up") }
                            .font(.subheadline.bold()).tint(Atelier.rose)
                    }
                    if let file = engine.lastPhotoURL {
                        ShareLink(item:file) { Label("Del seneste foto",systemImage:"photo") }
                            .tint(Atelier.rose)
                    }
                    Text("PLY indeholder målte LiDAR-punkter. OBJ er ARKits grove omgivelsesmesh beskåret omkring det låste mål. Begge bruger relative koordinater i meter. Filerne er ikke automatisk lukkede, teksturerede eller klar til 3D-print.")
                        .font(.footnote).foregroundStyle(Atelier.muted).fixedSize(horizontal:false,vertical:true)
                }
                .padding(20)
            }
            .background(Atelier.ink)
            .navigationTitle("Resultat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Luk") { resultSheet=false }.foregroundStyle(Atelier.rose) } }
        }
        .preferredColorScheme(.dark)
    }

    private var retakeView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:15) {
                    Text("Vælg en grøn position, hvis du vil tage et foto om. Appen kontrollerer stadig den rigtige ARKit-vinkel.")
                        .font(.subheadline).foregroundStyle(Atelier.muted)
                    ForEach(0..<3,id:\.self) { ring in
                        VStack(alignment:.leading,spacing:12) {
                            Text(["NEDERSTE RUNDE","MIDTERSTE RUNDE","ØVERSTE RUNDE"][ring])
                                .font(.caption.bold()).tracking(1.3).foregroundStyle(Atelier.rose)
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:6),spacing:10) {
                                ForEach(0..<12,id:\.self) { sector in
                                    let index=ring*12+sector
                                    Button("\(sector+1)") {
                                        engine.requestRetake(index)
                                        retakeSheet=false
                                    }
                                    .frame(maxWidth:.infinity,minHeight:49)
                                    .background(engine.missionCoverage[index] ? Atelier.rose : .white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
                                    .foregroundStyle(engine.missionCoverage[index] ? Atelier.ink : Atelier.muted)
                                    .disabled(!engine.missionCoverage[index])
                                }
                            }
                        }.padding(.vertical,10)
                    }
                    Text(engine.retakeHint).font(.footnote).foregroundStyle(Atelier.muted)
                }.padding(20)
            }
            .background(Atelier.ink)
            .navigationTitle("36 vinkler")
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Luk") { retakeSheet=false }.foregroundStyle(Atelier.rose) } }
        }.preferredColorScheme(.dark)
    }
}
