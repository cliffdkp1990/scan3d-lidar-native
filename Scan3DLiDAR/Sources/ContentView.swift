import ARKit
import RealityKit
import SwiftUI

/// Camera remains native: ARView displays the live camera and optional LiDAR mesh.
struct LiDARCameraView: UIViewRepresentable {
    @ObservedObject var engine: ScanEngine

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame:.zero,cameraMode:.ar,automaticallyConfigureSession:false)
        view.environment.sceneUnderstanding.options = []
        view.debugOptions = engine.showWireframe ? [.showSceneUnderstanding] : []
        engine.start(using:view.session)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        view.debugOptions = engine.showWireframe ? [.showSceneUnderstanding] : []
    }
    static func dismantleUIView(_ view:ARView, coordinator:()) {
        view.session.pause()
    }
}

private enum Atelier {
    static let ink = Color(red:0.035,green:0.026,blue:0.085)
    static let violet = Color(red:0.66,green:0.47,blue:0.96)
    static let rose = Color(red:0.95,green:0.67,blue:0.82)
    static let cream = Color(red:0.98,green:0.95,blue:1.0)
    static let muted = Color(red:0.77,green:0.73,blue:0.86)
}

struct ContentView: View {
    @StateObject private var engine = ScanEngine()
    @State private var resultSheet = false
    @State private var retakeSheet = false
    @State private var librarySheet = false
    @State private var newTargetConfirmation = false
    @State private var floatReticle = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geom in
            ZStack {
                Atelier.ink.ignoresSafeArea()
                LinearGradient(colors:[Atelier.violet.opacity(0.27),.clear,Atelier.ink],startPoint:.topLeading,endPoint:.bottomTrailing)
                    .ignoresSafeArea().allowsHitTesting(false)
                ScrollView {
                  VStack(spacing:0) {
                    header
                    if ScanEngine.supportsLiDAR {
                        ZStack {
                            LiDARCameraView(engine:engine)
                            LinearGradient(colors:[.black.opacity(0.30),.clear,.black.opacity(0.60)],startPoint:.top,endPoint:.bottom)
                                .allowsHitTesting(false)
                            orbitalGuide
                            VStack {
                                HStack(spacing:7) {
                                    Circle().fill(engine.running ? Color.green : Color.orange).frame(width:7,height:7)
                                    Text(engine.running ? "LIDAR AKTIV" : "KAMERA SAT PÅ PAUSE")
                                        .font(.system(size:10,weight:.heavy,design:.rounded)).tracking(1.1)
                                    Spacer()
                                    Text(engine.distanceText)
                                        .font(.system(size:13,weight:.bold,design:.rounded)).monospacedDigit()
                                }
                                .padding(.horizontal,14).padding(.vertical,12)
                                .background(.ultraThinMaterial,in:Capsule())
                                Spacer()
                                VStack(alignment:.leading,spacing:7) {
                                    Text(engine.missionReady ? "KLAR TIL FOTO" : (engine.missionTargetLocked ? "FØLG GUIDEN" : "VÆLG DIN GENSTAND"))
                                        .font(.system(size:10,weight:.heavy)).tracking(1.5)
                                        .foregroundStyle(engine.missionReady ? .green : Atelier.rose)
                                    Text(engine.missionTargetLocked ? engine.missionNavigation : "Peg på objektet, og lås målet")
                                        .font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(.white)
                                        .fixedSize(horizontal:false,vertical:true)
                                    Text(engine.subjectText)
                                        .font(.system(size:12)).foregroundStyle(Atelier.cream.opacity(0.8))
                                        .lineLimit(2)
                                }
                                .frame(maxWidth:.infinity,alignment:.leading)
                                .padding(17)
                                .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:22))
                            }
                            .padding(14)
                        }
                        .frame(maxWidth:.infinity)
                        .frame(height:max(260,min(540,geom.size.height * 0.56)))
                        .clipShape(RoundedRectangle(cornerRadius:26))
                        .overlay(RoundedRectangle(cornerRadius:26).strokeBorder(Atelier.violet.opacity(0.55),lineWidth:1))
                        .padding(.horizontal,13)
                    } else {
                        unsupportedView.frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                    if ScanEngine.supportsLiDAR { controls }
                    Spacer(minLength:0)
                  }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented:$resultSheet) { resultView.presentationDragIndicator(.visible) }
        .sheet(isPresented:$retakeSheet) { retakeView.presentationDragIndicator(.visible) }
        .sheet(isPresented:$librarySheet) { ScanLibraryView(engine: engine) }
        .onAppear { engine.refreshLibrary() }
        .onChange(of:resultSheet) { _,_ in updateCaptureSuspension() }
        .onChange(of:retakeSheet) { _,_ in updateCaptureSuspension() }
        .onChange(of:librarySheet) { _,_ in updateCaptureSuspension() }
        .onChange(of:newTargetConfirmation) { _,_ in updateCaptureSuspension() }
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

    private var header: some View {
        HStack {
            VStack(alignment:.leading,spacing:3) {
                HStack(spacing:6) {
                    Image(systemName:"sparkle").foregroundStyle(Atelier.rose)
                    Text("SCAN3D STUDIO").font(.system(size:10,weight:.heavy)).tracking(2.3)
                        .foregroundStyle(Atelier.cream)
                }
                Text("LiDAR \u{00b7} Atelier")
                    .font(.system(size:28,weight:.bold,design:.rounded))
                    .tracking(-0.7).foregroundStyle(.white)
            }
            Spacer()
            Button { librarySheet = true; engine.refreshLibrary() } label: {
                Image(systemName:"photo.stack").font(.system(size:19,weight:.medium))
                    .foregroundStyle(Atelier.cream).frame(width:48,height:48)
                    .background(.white.opacity(0.11),in:Circle())
            }.accessibilityLabel("Mine scanninger")
            Button { resultSheet = true } label: {
                Image(systemName:"square.3.layers.3d").font(.system(size:19,weight:.medium))
                    .foregroundStyle(Atelier.cream).frame(width:48,height:48)
                    .background(.white.opacity(0.11),in:Circle())
            }.accessibilityLabel("Resultat og eksport")
        }
        .padding(.horizontal,21).padding(.top,10).padding(.bottom,16)
    }

    private var orbitalGuide: some View {
        ZStack {
            ForEach(0..<36,id:\.self) { index in
                let ring=index/12
                let sector=index%12
                let angle=Double(sector)*Double.pi/6-Double.pi/2
                let r=CGFloat(66+ring*25)
                Circle()
                    .fill(engine.missionCoverage[index] ? Atelier.rose : (engine.missionTargetLocked && index==engine.retakeSlotIndex ? .orange : .white.opacity(0.35)))
                    .frame(width:6,height:6)
                    .offset(x:r*CGFloat(cos(angle)),y:r*CGFloat(sin(angle)))
            }
            Circle().stroke(Atelier.cream.opacity(0.68),lineWidth:1.4)
                .frame(width:154,height:154)
                .scaleEffect(floatReticle ? 1.035:0.97)
            Image(systemName:engine.missionReady ? "checkmark" : "plus")
                .font(.system(size:28,weight:.ultraLight))
                .foregroundStyle(engine.missionReady ? Color.green : Atelier.cream)
            VStack {
                Spacer()
                Text(engine.missionProgress)
                    .font(.system(size:12,weight:.heavy,design:.rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal,14).padding(.vertical,8)
                    .background(.black.opacity(0.45),in:Capsule())
            }.offset(y:140)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration:2.4).repeatForever(autoreverses:true)) {
                floatReticle = true
            }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Scanningsmission: \(engine.missionProgress)")
    }

    private var controls: some View {
        VStack(spacing:12) {
            Toggle(isOn: $engine.automaticPhotos) {
                Label("Automatisk foto", systemImage:"camera.badge.ellipsis")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Atelier.rose)
            Text(engine.savingPhoto ? "Gemmer foto og 3D-punkter …" : engine.guidanceText)
                .font(.footnote).foregroundStyle(Atelier.muted)
                .frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:9) {
                Button { if engine.missionTargetLocked { newTargetConfirmation = true } else { engine.lockCenteredTarget() } } label: {
                    Label(engine.missionTargetLocked ? "Nyt mål" : "Lås objekt", systemImage:"scope")
                        .font(.system(size:14,weight:.bold)).frame(maxWidth:.infinity,minHeight:49)
                }
                .buttonStyle(.bordered).tint(Atelier.rose)
                .disabled(!engine.running || engine.savingPhoto)
                Button { engine.captureCurrentFrame() } label: {
                    Label(engine.savingPhoto ? "Gemmer …" : (engine.retakeSlotIndex == nil ? "Tag foto" : "Tag om"),systemImage:"camera.fill")
                        .font(.system(size:15,weight:.heavy)).frame(maxWidth:.infinity,minHeight:49)
                }
                .buttonStyle(.borderedProminent).tint(Atelier.rose).foregroundStyle(Atelier.ink)
                .disabled(!engine.missionReady || engine.savingPhoto)
            }
            HStack(spacing:9) {
                Button {
                    if engine.running { engine.stop() }
                    else if let session = engine.session { engine.start(using:session) }
                } label: {
                    Label(engine.running ? "Pause" : "Fortsæt",systemImage:engine.running ? "pause.fill" : "play.fill")
                        .font(.system(size:12,weight:.semibold))
                }
                .tint(Atelier.violet)
                .disabled(engine.savingPhoto)
                Button { engine.showWireframe.toggle() } label: {
                    Label("Vis 3D-mesh",systemImage:"cube.transparent")
                        .font(.system(size:12,weight:.semibold))
                }
                .tint(Atelier.violet)
                .accessibilityValue(engine.showWireframe ? "Til" : "Fra")
                Spacer()
                Button { retakeSheet = true } label: {
                    Label("Vinkler",systemImage:"circle.hexagongrid")
                        .font(.system(size:12,weight:.semibold))
                }
                .tint(Atelier.violet)
                Spacer()
                Button { resultSheet = true } label: {
                    Label("Eksport",systemImage:"square.and.arrow.up")
                        .font(.system(size:12,weight:.semibold))
                }
                .tint(Atelier.violet)
            }.buttonStyle(.bordered)
            HStack(spacing:8) {
                Image(systemName:"cube.transparent")
                    .foregroundStyle(Atelier.rose)
                Text("\(engine.lidarPointCount) 3D-punkter")
                Spacer()
                Text(engine.trackingText).lineLimit(1)
            }
            .font(.system(size:11,weight:.medium))
            .foregroundStyle(Atelier.muted)
        }
        .padding(.horizontal,20).padding(.top,14).padding(.bottom,12)
    }

    private var unsupportedView: some View {
        VStack(spacing:18) {
            Image(systemName:"iphone.radiowaves.left.and.right")
                .font(.system(size:54)).foregroundStyle(Atelier.violet)
            Text("LiDAR er ikke tilgængelig")
                .font(.title2.bold()).foregroundStyle(.white)
            Text("Denne app kræver en iPhone med ARKit og LiDAR, eksempelvis iPhone 14 Pro Max. Simulation kan ikke levere ægte dybdemålinger.")
                .multilineTextAlignment(.center).foregroundStyle(Atelier.muted)
                .padding(.horizontal,30)
        }.padding()
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
                    Text("Vælg en rosa position, hvis du vil tage et foto om. Appen kontrollerer stadig den rigtige ARKit-vinkel.")
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
