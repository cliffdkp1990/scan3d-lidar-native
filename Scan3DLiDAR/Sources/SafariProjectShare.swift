import SwiftUI

struct SafariProjectShare: View {
    let project: ScanProject
    let store: ProjectStore
    let synthetic: Bool
    @State private var url: URL?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let model = project.safariModel {
                if let url {
                    ShareLink(item: url) { Label("Del Safari-projektfil", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered).accessibilityIdentifier("safari-project-share")
                    Text("3D-kopien er klar. Vælg Gem i Filer, og derefter Importér projekt i webversionen. Fotos og video bliver i native-projektet.")
                        .font(.footnote).accessibilityIdentifier("safari-project-help")
                } else if let failure {
                    Text(failure).font(.footnote).foregroundStyle(.orange)
                } else { ProgressView("Klargør 3D-kopi til Safari …") }
                Text(synthetic ? "Syntetisk testmodel — ingen målte LiDAR-data." : "LiDAR optages i native-appen på understøttede enheder. Safari viser kun den gemte model.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("safari-project-scope")
                    .task(id: "\(project.id)-\(model.sha256)-\(project.updatedAt.timeIntervalSince1970)-\(synthetic)") {
                        url = nil; failure = nil
                        let projectID = project.id, shareStore = store, fixture = synthetic
                        let task = Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                            Result { try SafariProjectArchive.prepare(projectID: projectID, file: model,
                                store: shareStore, synthetic: fixture) }
                        }
                        let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
                        guard !Task.isCancelled else { return }
                        switch result {
                        case .success(let ready): url = ready
                        case .failure(let error): failure = error.localizedDescription
                        }
                    }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
