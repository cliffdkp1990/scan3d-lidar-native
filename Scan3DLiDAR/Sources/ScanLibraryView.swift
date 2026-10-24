import AVKit
import SwiftUI
import UIKit

struct ScanLibraryView: View {
    @ObservedObject var engine: ScanEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !engine.libraryMessage.isEmpty {
                        Text(engine.libraryMessage).foregroundStyle(.orange)
                    }
                    if engine.projects.isEmpty {
                        ContentUnavailableView("Dine scanninger", systemImage: "photo.stack",
                            description: Text("Lås et objekt på kameraskærmen. Godkendte fotos og 3D-punkter gemmes automatisk her."))
                    }
                    ForEach(engine.projects) { project in
                        NavigationLink {
                            ScanProjectView(project: project, engine: engine)
                        } label: {
                            HStack(spacing: 16) {
                                if let cover = project.currentCaptures.first {
                                    StoredPhotoView(file: cover.thumbnail ?? cover.photo,
                                        projectID: project.id, store: engine.projectStore)
                                        .frame(width: 100, height: 100).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                } else {
                                    Image(systemName: "camera").font(.largeTitle)
                                        .frame(width: 100, height: 100).background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(project.title).font(.headline)
                                    Text("\(project.currentCaptures.count)/36 fotos · \(project.savedVideos.count) videoer")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(project.updatedAt, format: .dateTime.day().month().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }.padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                    Text("Ældre optagelser fra før projektbiblioteket ligger fortsat i Filer → Scan3D → Scan3DPhotos / Scan3DLiDARExports. De er ikke ændret eller automatisk blandet med nye projekter.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Mine scanninger")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Luk") { dismiss() } } }
            .refreshable { engine.refreshLibrary() }
        }.preferredColorScheme(.dark)
    }
}

private struct ScanProjectView: View {
    @State var project: ScanProject
    @ObservedObject var engine: ScanEngine
    private var store: ProjectStore { engine.projectStore }
    @State private var integrity = ""
    @State private var checking = false
    @State private var recovering: UUID?
    @State private var recoveryMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(project.currentCaptures.count) fotovinkler · \(project.captures.count) optagelser inklusive genfoto")
                    .font(.headline)
                Text("Gemte optagelser. En ny scanning starter med et nyt koordinatsystem; dette projekt føres ikke automatisk videre efter genstart.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !project.savedVideos.isEmpty { Text("Video").font(.title2.bold()) }
                ForEach(project.savedVideos) { video in
                    NavigationLink {
                        StoredVideoPlayer(video: video, projectID: project.id, store: store)
                    } label: {
                        Label("Video · \(Int(video.details.duration.rounded())) sekunder", systemImage: "play.rectangle.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
                ForEach(project.unfinishedVideos) { pending in
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Afbrudt eller igangværende video", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(pending.failure ?? "Filen er endnu ikke godkendt. En optagelse må først gendannes, når den er stoppet.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(recovering == pending.id ? "Kontrollerer …" : "Kontrollér og gendan video") { recover(pending) }
                            .disabled(recovering != nil || (engine.videoBusy && engine.activeProject?.id == project.id))
                    }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                }
                if !recoveryMessage.isEmpty { Text(recoveryMessage).font(.footnote) }
                if let latest = project.captures.last {
                    VerifiedScanShare(file: latest.pointCloud, projectID: project.id, store: store, title: "Senest gemte 3D-punktsky (PLY)")
                }
                ForEach(project.exports) { exported in
                    VerifiedScanShare(file: exported.file, projectID: project.id, store: store,
                        title: "Del \(exported.file.name.pathExtension.uppercased()) · \(exported.createdAt.formatted(date: .omitted, time: .shortened))")
                }
                Button(checking ? "Kontrollerer …" : "Kontrollér alle projektfiler") {
                    checking = true
                    let verificationStore = store
                    let verificationProject = project
                    Task {
                        let result = await Task.detached(priority: .userInitiated) { () -> String in
                            do { try verificationStore.verify(verificationProject); return "Alle \(verificationProject.allFiles.count) registrerede filer har korrekt størrelse og SHA-256." }
                            catch { return error.localizedDescription }
                        }.value
                        integrity = result
                        checking = false
                    }
                }.disabled(checking).buttonStyle(.bordered)
                if !integrity.isEmpty { Text(integrity).font(.footnote) }
                Text("Fotos").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16) {
                    ForEach(project.currentCaptures) { capture in
                        NavigationLink {
                            ScrollView {
                                VStack(spacing: 20) {
                                    StoredPhotoView(file: capture.photo, projectID: project.id, store: store)
                                        .frame(minHeight: 300)
                                    VerifiedScanShare(file: capture.photo, projectID: project.id, store: store, title: "Del foto")
                                    Text("Originalen bevares ved genfoto. Historiske filer og metadata ligger i projektets mappe i Filer.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }.padding()
                            }.navigationTitle("Position \(capture.slot + 1)")
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                StoredPhotoView(file: capture.thumbnail ?? capture.photo, projectID: project.id, store: store)
                                    .frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                                Text("Position \(capture.slot + 1)").font(.subheadline.bold())
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding()
        }.navigationTitle(project.title).navigationBarTitleDisplayMode(.inline)
            .onReceive(engine.$projects) { updated in
                if let current = updated.first(where: { $0.id == project.id }) { project = current }
            }
    }

    private func recover(_ pending: PendingVideo) {
        recovering = pending.id
        let recoveryStore = store
        let projectID = project.id
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ScanProject, Error> in
                do {
                    let url = try recoveryStore.pendingVideoURL(projectID: projectID, videoID: pending.id)
                    let checked = try await VideoFileInspector.inspect(url)
                    _ = try recoveryStore.finishVideo(projectID: projectID, videoID: pending.id,
                        details: VideoDetails(width: checked.width, height: checked.height, duration: checked.duration,
                            frames: nil, firstARTimestamp: nil, orientation: "movieTrack", stopReason: "recovered"))
                    return .success(try recoveryStore.load(projectID))
                } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let updated): project = updated; recoveryMessage = "Videoen er kontrolleret og gendannet."; engine.refreshLibrary()
            case .failure(let error): recoveryMessage = "Kan ikke gendannes: \(error.localizedDescription). Originalen er bevaret."
            }
            recovering = nil
        }
    }
}

private struct StoredVideoPlayer: View {
    let video: StoredVideo
    let projectID: UUID
    let store: ProjectStore
    @State private var player: AVPlayer?
    @State private var failure: String?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let player = player { VideoPlayer(player: player).frame(height: 340) }
                else if let failure = failure { Label(failure, systemImage: "exclamationmark.triangle").padding() }
                else { ProgressView("Kontrollerer video …").frame(height: 200) }
                Text("Kameravideo uden lyd. Videoen indeholder ikke en færdig 3D-model.")
                    .font(.subheadline).foregroundStyle(.secondary)
                VerifiedScanShare(file: video.file, projectID: projectID, store: store, title: "Del video")
            }.padding()
        }
        .navigationTitle("Video")
        .onDisappear { player?.pause() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
        .task(id: video.id) {
            let videoStore = store
            let videoFile = video.file
            let videoProjectID = projectID
            let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                do {
                    let url = try videoStore.verifiedURL(videoFile, projectID: videoProjectID)
                    _ = try await VideoFileInspector.inspect(url)
                    return .success(url)
                } catch { return .failure(error) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let url): player = AVPlayer(url: url)
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}

private struct StoredPhotoView: View {
    let file: StoredScanFile
    let projectID: UUID
    let store: ProjectStore
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image = image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Label("Billedet kan ikke læses", systemImage: "photo.badge.exclamationmark")
                    .font(.caption).multilineTextAlignment(.center).padding(8)
            } else { ProgressView() }
        }
        .accessibilityLabel(failed ? "Billedfil mangler eller er beskadiget" : "Foto af den scannede genstand")
        .task(id: file.sha256) {
            let imageStore = store
            let imageFile = file
            let imageProjectID = projectID
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let url = try? imageStore.verifiedURL(imageFile, projectID: imageProjectID) else { return nil }
                return UIImage(contentsOfFile: url.path)
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }
}

private struct VerifiedScanShare: View {
    let file: StoredScanFile
    let projectID: UUID
    let store: ProjectStore
    let title: String
    @State private var url: URL?
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = url {
                ShareLink(item: url) { Label(title, systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
            } else if let failure = failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            } else { ProgressView("Kontrollerer fil …") }
        }
        .task(id: file.sha256) {
            let shareStore = store
            let shareFile = file
            let shareProjectID = projectID
            let result = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
                Result { try shareStore.verifiedURL(shareFile, projectID: shareProjectID) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let valid): url = valid
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}

private extension String {
    var pathExtension: String { (self as NSString).pathExtension }
}
