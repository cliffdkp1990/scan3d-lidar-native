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
    let onDiagnostics:()->Void
    let onRetake:()->Void
    let onNewTarget:()->Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                header
                if let issue=engine.cameraIssue {
                    VStack(alignment:.leading,spacing:12) {
                        Label(issue,systemImage:"exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                        if engine.cameraPermissionDenied {
                            Button("Åbn kameraindstillinger") {
                                if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(.bordered)
                        }
                    }.padding().frame(maxWidth:.infinity,alignment:.leading)
                        .background(Studio.panel,in:RoundedRectangle(cornerRadius:18))
                }
                if engine.cameraAvailable {
                    surfaceModePicker
                    let contentWidth=max(1,size.width-32)
                    let wide=size.width > size.height && contentWidth >= 650 && !typeSize.isAccessibilitySize
                    let layout=wide ? AnyLayout(HStackLayout(alignment:.top,spacing:20)) : AnyLayout(VStackLayout(spacing:20))
                    layout {
                        cameraStage.frame(width:wide ? (contentWidth-20)*0.48 : contentWidth,
                            height:wide ? max(260,min(400,size.height-110)) : max(280,min(520,size.height*0.5)))
                        VStack(spacing:18) {
                            if typeSize.isAccessibilitySize { accessibleCameraFacts }
                            guidance; captureDock; quality; coverage
                        }.frame(maxWidth:.infinity)
                    }
                    options
                } else {
                    ContentUnavailableView("Kamera med LiDAR kræves",systemImage:"iphone.radiowaves.left.and.right",
                        description:Text("Optagelse kræver en iPhone med LiDAR, eksempelvis iPhone 14 Pro Max. Du kan stadig åbne dine gemte scanninger."))
                    Button("Åbn mine scanninger",action:onLibrary).buttonStyle(.borderedProminent)
                }
            }.frame(width:max(1,size.width-32)).padding(16).padding(.bottom,22)
        }
        .frame(width:size.width,height:size.height)
        // Keep scrolled accessibility text out of the system status/home-indicator areas.
        .clipped()
        .accessibilityIdentifier("studio-scroll")
        .background(Studio.ink.ignoresSafeArea()).tint(Studio.mint)
    }

    private var header:some View {
        let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:14)) : AnyLayout(HStackLayout(spacing:12))
        return layout {
            VStack(alignment:.leading,spacing:4) {
                Text("SCAN3D STUDIO").font(.caption.weight(.heavy)).tracking(typeSize.isAccessibilitySize ? 0:2).foregroundStyle(Studio.mint)
                Text("Indfang formen.").font(.title2.bold()).foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:10) {
                Button(action:onLibrary) { Image(systemName:"square.stack.3d.up").font(.system(size:21)).frame(width:48,height:48).background(Studio.mint.opacity(0.15),in:Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Mine scanninger")
                Button(action:onResult) { Image(systemName:"cube.transparent").font(.system(size:21)).frame(width:48,height:48).background(Studio.mint.opacity(0.15),in:Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Resultat og eksport")
            }
        }
    }

    private var surfaceModePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("3D-visning", selection: $engine.surfaceMode) {
                ForEach(SurfaceVisualizationMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("studio-surface-mode")
            if engine.surfaceMode == .wireframe {
                Text("Diagnosevisning · ARKit-trådnet er ikke den naturlige overflade.")
                    .font(.caption).foregroundStyle(Studio.muted)
            }
        }
        .padding(.horizontal, 2)
    }

    private var cameraStage:some View {
        GeometryReader { cameraSize in
            ZStack {
                if engine.isStudioFixture {
                    StudioFixtureBackdrop()
                } else { LiDARCameraView(engine:engine) }
                if engine.surfaceMode == .surfaces && !engine.isStudioFixture {
                    SurfacePreviewOverlay(preview: engine.surfacePreview)
                }
                LinearGradient(colors:[.black.opacity(0.5),.clear,.clear,.black.opacity(0.6)],startPoint:.top,endPoint:.bottom)
                    .allowsHitTesting(false)
                focusOverlay(size:cameraSize.size)
                if !typeSize.isAccessibilitySize { VStack {
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
                }.padding(16) }
            }
            .clipShape(RoundedRectangle(cornerRadius:30,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:30).strokeBorder(.white.opacity(0.13)))
        }
        .accessibilityElement(children:.contain)
        .accessibilityLabel("Kameravisning")
        .accessibilityIdentifier("studio-camera")
    }

    /// At large text sizes camera facts leave the image; they may grow and scroll normally.
    private var accessibleCameraFacts:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(engine.isStudioFixture ? "SIMULATOR" : engine.running ? "LIVE" : "PAUSE")
                .font(.headline).foregroundStyle(Studio.mint).fixedSize(horizontal:false,vertical:true)
            Text("Afstand: \(engine.distanceText)").font(.body.monospacedDigit()).fixedSize(horizontal:false,vertical:true)
                .accessibilityIdentifier("studio-distance")
            Text(engine.highResolutionSupported && engine.preferHighResolution ? "HQ-foto" : "Foto").font(.body)
            if engine.isStudioFixture {
                Text("TESTMOTIV · INGEN KAMERA ELLER LIDAR").font(.caption.bold()).fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("studio-fixture-label")
            } else {
                Text(engine.missionTargetLocked ? "Målet følger AR-koordinaterne" : "Centrér genstanden i søgeren")
                    .font(.body).fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
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
                Text(engine.cameraIssue != nil ? "KAMERA KRÆVER HANDLING" : !engine.running ? "KAMERA PÅ PAUSE" : engine.savingPhoto ? "GEMMER OPTAGELSEN" : engine.missionReady ? "KLAR TIL FOTO" : engine.missionTargetLocked ? "FØLG DEN NÆSTE VINKEL" : "VÆLG DIN GENSTAND")
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
            if engine.surfaceMode == .surfaces {
                Text(engine.surfacePreview.isEmpty
                    ? "Flader vises, når målet er låst og ARKit har registreret mesh."
                    : "Grøn toning viser registrerede fladers retning. Kanter er vejledende, ikke præcisionsmål.")
                    .font(.caption).foregroundStyle(Studio.muted).fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private var captureDock:some View {
        VStack(spacing:14) {
            if !engine.missionTargetLocked {
                if !engine.running {
                    Button("Start kamera") { if let session=engine.session { engine.start(using:session) } }
                        .buttonStyle(.borderedProminent).disabled(engine.savingPhoto || engine.isStudioFixture)
                }
                Button(action:onNewTarget) { Label("Lås genstanden",systemImage:"scope").frame(maxWidth:.infinity,minHeight:48) }
                    .buttonStyle(.borderedProminent).foregroundStyle(Studio.ink)
                    .disabled(!engine.running || engine.savingPhoto || engine.videoBusy)
            } else {
                let dockLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:20)) : AnyLayout(HStackLayout(spacing:24))
                dockLayout {
                    Button(action:onLibrary) {
                        VStack(spacing:6) { Image(systemName:"photo.stack").font(.system(size:24));Text("Bibliotek").font(.caption).fixedSize(horizontal:false,vertical:true) }
                            .frame(minWidth:64,minHeight:64)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength:0) }
                    Button { engine.captureCurrentFrame() } label: {
                        ZStack {
                            Circle().stroke(Studio.mint.opacity(0.35),lineWidth:3).frame(width:80,height:80)
                            Circle().fill(engine.missionReady ? Studio.mint : .white.opacity(0.18)).frame(width:66,height:66)
                            if engine.savingPhoto { ProgressView().tint(.white) }
                            else { Image(systemName:"camera.fill").font(.system(size:24)).foregroundStyle(engine.missionReady ? Studio.ink : .white.opacity(0.55)) }
                        }
                    }.disabled(!engine.missionReady || engine.savingPhoto || engine.isStudioFixture)
                        .accessibilityLabel(engine.retakeSlotIndex == nil ? "Tag foto nu" : "Tag foto om")
                        .accessibilityIdentifier("capture-photo")
                    if !typeSize.isAccessibilitySize { Spacer(minLength:0) }
                    Button {
                        if engine.videoState == .recording { engine.stopVideo() } else { engine.startVideo() }
                    } label: {
                        VStack(spacing:6) { Image(systemName:engine.videoState == .recording ? "stop.circle.fill" : "video").font(.system(size:24));Text(engine.videoState == .recording ? "Stop" : "Video").font(.caption).fixedSize(horizontal:false,vertical:true) }.frame(minWidth:64,minHeight:64)
                    }.disabled(engine.videoState == .preparing || engine.videoState == .finishing || !engine.running || engine.isStudioFixture)
                        .tint(engine.videoState == .recording ? .red : Studio.mint)
                        .accessibilityLabel(engine.videoState == .recording ? "Stop og gem video" : "Start video")
                }
                Text(engine.automaticPhotos ? "Foto tages automatisk, når vinkel, ro, lys og dybde passer." : "Manuelt foto · vent på godkendt vinkel og billedkontrol.")
                    .font(.footnote).foregroundStyle(Studio.muted).multilineTextAlignment(.center)
                Text(engine.videoMessage).font(.caption).foregroundStyle(Studio.muted).multilineTextAlignment(.center)
                HStack {
                    Button(engine.running ? "Pause kamera" : "Genstart kamera") {
                        if engine.running { engine.stop() } else if let session=engine.session { engine.start(using:session) }
                    }.disabled(engine.savingPhoto || engine.videoState == .preparing || engine.videoState == .finishing || engine.isStudioFixture)
                    Spacer()
                    Button("Nyt mål",action:onNewTarget).disabled(engine.savingPhoto || engine.videoBusy || engine.isStudioFixture)
                }.font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
                if !engine.running {
                    Text("Kameraet starter i et nyt 3D-koordinatsystem. Lås genstanden igen. Allerede gemte fotos og punktskyer bevares i Mine scanninger.")
                        .font(.footnote).foregroundStyle(Studio.muted)
                        .fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("camera-restart-guidance")
                }
            }
            if engine.retakeSlotIndex != nil { Button("Annuller genfoto") { engine.cancelRetake() }.buttonStyle(.bordered) }
        }
    }

    private var quality:some View {
        VStack(spacing:10) {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:10)],spacing:10) {
                indicator("BILLEDE",value:engine.focusAdjusting ? "Fokuserer" : engine.photoCondition.title,icon:"camera.aperture",good:engine.photoCondition == .ready && !engine.focusAdjusting)
                indicator("LIDAR",value:engine.depthSupport,icon:"cube.transparent",good:engine.depthReliable)
                indicator("SPORING",value:engine.trackingNormal ? "Stabil" : "Afventer",icon:"viewfinder",good:engine.trackingNormal)
            }
            Button(action:onDiagnostics) {
                Label("Test min LiDAR",systemImage:"stethoscope")
                    .frame(maxWidth:.infinity,minHeight:48)
            }
            .buttonStyle(.bordered)
            .disabled(engine.savingPhoto || engine.videoBusy)
            .accessibilityIdentifier("lidar-selftest-button")
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
                Text("Vælg Naturlig, Flader eller diagnostisk Trådnet over kameraet. Flader viser kun observeret ARKit-geometri og ændrer ikke gemte scanninger.").font(.footnote).foregroundStyle(Studio.muted)
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
