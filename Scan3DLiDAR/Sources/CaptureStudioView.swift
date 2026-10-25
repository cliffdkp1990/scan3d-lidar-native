import ARKit
import RealityKit
import SwiftUI

private enum Studio {
    static let ink=Color(red:0.035,green:0.055,blue:0.075)
    static let panel=Color(red:0.065,green:0.09,blue:0.12)
    static let mint=Color(red:0.55,green:0.95,blue:0.82)
    static let muted=Color(red:0.65,green:0.73,blue:0.78)
}

/// Full camera, concise guidance, measured indicators; graphics are never saved into photos.
struct CaptureStudioView: View {
    @ObservedObject var engine:ScanEngine
    let size:CGSize
    let onLibrary:()->Void
    let onResult:()->Void
    let onRetake:()->Void
    let onNewTarget:()->Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                header
                if engine.cameraAvailable {
                    let wide=size.width > size.height && !typeSize.isAccessibilitySize
                    let layout=wide ? AnyLayout(HStackLayout(alignment:.top,spacing:20)) : AnyLayout(VStackLayout(spacing:20))
                    layout {
                        cameraStage.frame(width:wide ? max(280,size.width*0.52) : nil,
                            height:wide ? 340 : max(300,min(580,size.height*0.55)))
                        VStack(spacing:18) { guidance; captureDock; quality; coverage }.frame(maxWidth:.infinity)
                    }
                    options
                } else {
                    ContentUnavailableView("Kamera med LiDAR kræves",systemImage:"iphone.radiowaves.left.and.right",
                        description:Text("Optagelse kræver en iPhone med LiDAR, eksempelvis iPhone 14 Pro Max. Du kan stadig åbne dine gemte scanninger."))
                    Button("Åbn mine scanninger",action:onLibrary).buttonStyle(.borderedProminent)
                }
            }.padding(16).padding(.bottom,22)
        }
        .background(Studio.ink.ignoresSafeArea()).tint(Studio.mint)
    }

    private var header:some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                Text("SCAN3D STUDIO").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Studio.mint)
                Text("Indfang formen.").font(.title2.bold()).foregroundStyle(.white)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Button(action:onLibrary) { Image(systemName:"square.stack.3d.up").frame(width:48,height:48) }
                .buttonStyle(.bordered).clipShape(Circle()).accessibilityLabel("Mine scanninger")
            Button(action:onResult) { Image(systemName:"cube.transparent").frame(width:48,height:48) }
                .buttonStyle(.bordered).clipShape(Circle()).accessibilityLabel("Resultat og eksport")
        }
    }

    private var cameraStage:some View {
        GeometryReader { cameraSize in
            ZStack {
                if engine.isStudioFixture {
                    StudioFixtureBackdrop()
                } else { LiDARCameraView(engine:engine) }
                LinearGradient(colors:[.black.opacity(0.5),.clear,.clear,.black.opacity(0.6)],startPoint:.top,endPoint:.bottom)
                    .allowsHitTesting(false)
                focusOverlay(size:cameraSize.size)
                VStack {
                    HStack(alignment:.top) {
                        Label(engine.isStudioFixture ? "SIMULATOR" : engine.running ? "LIVE" : "PAUSE",systemImage:"circle.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(engine.trackingNormal ? Studio.mint : .orange)
                            .padding(.horizontal,12).padding(.vertical,9).background(.ultraThinMaterial,in:Capsule())
                        Spacer(minLength:8)
                        VStack(alignment:.trailing,spacing:5) {
                            Text(engine.distanceText).font(.headline.monospacedDigit())
                            Text(engine.highResolutionSupported && engine.preferHighResolution ? "HQ-foto" : "Foto")
                                .font(.caption.weight(.semibold)).foregroundStyle(Studio.mint)
                        }.padding(10).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14))
                    }
                    Spacer()
                    if engine.isStudioFixture {
                        Text("TESTMOTIV · INGEN KAMERA ELLER LIDAR").font(.caption2.bold()).padding(9)
                            .background(.black.opacity(0.7),in:Capsule()).accessibilityIdentifier("studio-fixture-label")
                    } else {
                        HStack(spacing:8) {
                            Image(systemName:engine.missionTargetLocked ? "scope" : "viewfinder")
                            Text(engine.missionTargetLocked ? "Målet følger AR-koordinaterne" : "Centrér genstanden i søgeren")
                                .font(.caption.weight(.medium)).fixedSize(horizontal:false,vertical:true)
                        }.padding(12).background(.ultraThinMaterial,in:Capsule())
                    }
                }.padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius:30,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:30).strokeBorder(.white.opacity(0.13)))
        }
        .accessibilityElement(children:.contain)
        .accessibilityLabel("Kameravisning")
    }

    private func focusOverlay(size:CGSize)->some View {
        let raw=engine.targetScreenPoint ?? CGPoint(x:0.5,y:0.5)
        let x=min(0.86,max(0.14,raw.x)), y=min(0.84,max(0.16,raw.y))
        let tint:Color=engine.missionReady ? Studio.mint : .white.opacity(0.85)
        return ZStack {
            if engine.targetScreenPoint != nil && !engine.targetOutsideView {
                Path { path in path.move(to:CGPoint(x:size.width/2,y:size.height/2));path.addLine(to:CGPoint(x:x*size.width,y:y*size.height)) }
                    .stroke(Studio.mint.opacity(0.45),style:StrokeStyle(lineWidth:1,dash:[3,5]))
            }
            FocusBrackets().stroke(tint,style:StrokeStyle(lineWidth:2.5,lineCap:.round)).frame(width:96,height:96)
                .position(x:x*size.width,y:y*size.height)
            Image(systemName:engine.targetOutsideView ? "arrow.right" : engine.missionReady ? "checkmark" : "plus")
                .font(.title3.weight(.light)).foregroundStyle(tint)
                .rotationEffect(engine.targetOutsideView ? .radians(atan2(raw.y-0.5,raw.x-0.5)) : .zero)
                .position(x:x*size.width,y:y*size.height)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private var guidance:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack {
                Text(engine.savingPhoto ? "GEMMER OPTAGELSEN" : engine.missionReady ? "KLAR TIL FOTO" : engine.missionTargetLocked ? "FØLG DEN NÆSTE VINKEL" : "VÆLG DIN GENSTAND")
                    .font(.caption.weight(.heavy)).tracking(1).foregroundStyle(engine.missionReady ? Studio.mint : Studio.muted)
                Spacer()
                if engine.videoState == .recording { Label("VIDEO",systemImage:"record.circle.fill").font(.caption.bold()).foregroundStyle(.red) }
            }
            Text(engine.savingPhoto ? "Hold kameraet roligt et øjeblik." : engine.guidanceText)
                .font(.headline).foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)
                .accessibilityIdentifier("capture-guidance")
            if engine.missionTargetLocked {
                Text(engine.missionNavigation).font(.subheadline).foregroundStyle(Studio.muted).fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private var captureDock:some View {
        VStack(spacing:14) {
            if !engine.missionTargetLocked {
                Button(action:onNewTarget) { Label("Lås genstanden",systemImage:"scope").frame(maxWidth:.infinity,minHeight:48) }
                    .buttonStyle(.borderedProminent).foregroundStyle(Studio.ink)
                    .disabled(!engine.running || engine.savingPhoto || engine.videoBusy)
            } else {
                HStack(spacing:24) {
                    Button(action:onLibrary) { VStack(spacing:6) { Image(systemName:"photo.stack").font(.title2);Text("Bibliotek").font(.caption) }.frame(minWidth:64,minHeight:64) }
                    Spacer(minLength:0)
                    Button { engine.captureCurrentFrame() } label: {
                        ZStack {
                            Circle().stroke(Studio.mint.opacity(0.35),lineWidth:3).frame(width:80,height:80)
                            Circle().fill(engine.missionReady ? Studio.mint : .white.opacity(0.18)).frame(width:66,height:66)
                            if engine.savingPhoto { ProgressView().tint(.white) }
                            else { Image(systemName:"camera.fill").font(.title2).foregroundStyle(engine.missionReady ? Studio.ink : .white.opacity(0.55)) }
                        }
                    }.disabled(!engine.missionReady || engine.savingPhoto || engine.isStudioFixture)
                        .accessibilityLabel(engine.retakeSlotIndex == nil ? "Tag foto nu" : "Tag foto om")
                    Spacer(minLength:0)
                    Button {
                        if engine.videoState == .recording { engine.stopVideo() } else { engine.startVideo() }
                    } label: {
                        VStack(spacing:6) { Image(systemName:engine.videoState == .recording ? "stop.circle.fill" : "video").font(.title2);Text(engine.videoState == .recording ? "Stop" : "Video").font(.caption) }.frame(minWidth:64,minHeight:64)
                    }.disabled(engine.videoState == .preparing || engine.videoState == .finishing || !engine.running || engine.isStudioFixture)
                        .tint(engine.videoState == .recording ? .red : Studio.mint)
                        .accessibilityLabel(engine.videoState == .recording ? "Stop og gem video" : "Start video")
                }
                Text(engine.automaticPhotos ? "Foto tages automatisk, når vinkel, ro, lys og dybde passer." : "Manuelt foto · vent på godkendt vinkel og billedkontrol.")
                    .font(.footnote).foregroundStyle(Studio.muted).multilineTextAlignment(.center)
                Text(engine.videoMessage).font(.caption).foregroundStyle(Studio.muted).multilineTextAlignment(.center)
                HStack {
                    Button(engine.running ? "Pause scanning" : "Fortsæt scanning") {
                        if engine.running { engine.stop() } else if let session=engine.session { engine.start(using:session) }
                    }.disabled(engine.savingPhoto || engine.videoState == .preparing || engine.videoState == .finishing || engine.isStudioFixture)
                    Spacer()
                    Button("Nyt mål",action:onNewTarget).disabled(engine.savingPhoto || engine.videoBusy || engine.isStudioFixture)
                }.font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
            }
            if engine.retakeSlotIndex != nil { Button("Annuller genfoto") { engine.cancelRetake() }.buttonStyle(.bordered) }
        }
    }

    private var quality:some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:10)],spacing:10) {
            indicator("BILLEDE",value:engine.photoCondition.title,icon:"camera.aperture",good:engine.photoCondition == .ready)
            indicator("LIDAR",value:engine.depthSupport,icon:"cube.transparent",good:engine.depthReliable)
            indicator("SPORING",value:engine.trackingNormal ? "Stabil" : "Afventer",icon:"viewfinder",good:engine.trackingNormal)
        }
    }
    private func indicator(_ title:String,value:String,icon:String,good:Bool)->some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:icon).font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(Studio.muted)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(good ? Studio.mint : .orange).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
            .background(Studio.panel,in:RoundedRectangle(cornerRadius:17))
            .accessibilityElement(children:.combine)
    }

    private var coverage:some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { Text("Formens dækning").font(.headline);Spacer();Text(engine.missionProgress).font(.subheadline.monospacedDigit()).foregroundStyle(Studio.mint) }
            ForEach(0..<3,id:\.self) { ring in
                HStack(spacing:10) {
                    Text(["Lav","Midt","Høj"][ring]).font(.caption).foregroundStyle(Studio.muted).frame(width:40,alignment:.leading)
                    HStack(spacing:4) {
                        ForEach(0..<12,id:\.self) { sector in
                            let index=ring*12+sector
                            Capsule().fill(engine.missionCoverage[index] ? Studio.mint : .white.opacity(0.12)).frame(minWidth:3,minHeight:8,maxHeight:8)
                        }
                    }
                }.accessibilityElement(children:.ignore)
                    .accessibilityLabel("\(["Lav","Midterste","Høj"][ring]) runde: \(engine.missionCoverage[(ring*12)..<(ring*12+12)].filter{$0}.count) af 12 vinkler")
            }
            Text("Vinklerne viser registrerede fotos, ikke en garanti for en komplet overflade.").font(.caption).foregroundStyle(Studio.muted)
            Button("Se vinkler og tag om",action:onRetake).buttonStyle(.bordered).disabled(!engine.missionTargetLocked || engine.savingPhoto)
        }.padding(18).background(Studio.panel,in:RoundedRectangle(cornerRadius:22))
    }

    private var options:some View {
        DisclosureGroup("Optagelsesvalg og målegrundlag") {
            VStack(alignment:.leading,spacing:15) {
                Toggle("Automatisk foto",isOn:$engine.automaticPhotos)
                Toggle("Start video automatisk",isOn:$engine.automaticVideo)
                Toggle("Højopløsningsfoto",isOn:$engine.preferHighResolution).disabled(!engine.highResolutionSupported || engine.savingPhoto)
                Toggle("Vis LiDAR-mesh i kameraet",isOn:$engine.showWireframe)
                Toggle("Motivforslag",isOn:$engine.analyzeSubject)
                if engine.analyzeSubject { Text(engine.subjectText).font(.footnote).foregroundStyle(Studio.muted) }
                Text("Kamerastream: \(engine.liveResolution). Fotoopløsning vælges af ARKit og registreres ved lagring. Video er fortsat 1280 px / 15 billeder pr. sekund uden lyd.")
                    .font(.footnote).foregroundStyle(Studio.muted)
                Text("Lys og konturer er vejledende billedkontrol, ikke en kalibreret fokusmåling. Tættere punkter betyder ikke millimeterpræcision. Råfilerne ændres ikke af søgergrafikken.")
                    .font(.footnote).foregroundStyle(Studio.muted)
            }.padding(.top,14)
        }.padding(18).background(Studio.panel,in:RoundedRectangle(cornerRadius:22))
    }
}

private struct FocusBrackets:Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        let length=rect.width*0.22
        let corners:[(CGFloat,CGFloat,CGFloat,CGFloat)]=[(rect.minX,rect.minY,1,1),(rect.maxX,rect.minY,-1,1),(rect.minX,rect.maxY,1,-1),(rect.maxX,rect.maxY,-1,-1)]
        for (x,y,sx,sy) in corners {
            path.move(to:CGPoint(x:x,y:y+length*sy));path.addLine(to:CGPoint(x:x,y:y));path.addLine(to:CGPoint(x:x+length*sx,y:y))
        }
        return path
    }
}
