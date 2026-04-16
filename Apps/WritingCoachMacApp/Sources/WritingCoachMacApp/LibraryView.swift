import SwiftUI
import WritingCoachCore

struct LibraryRootView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        if appModel.service == nil {
            VStack(spacing: 12) {
                Text("Choose a Library Folder")
                    .font(.title2)
                Button("Choose Library") {
                    Task { await appModel.chooseLibrary() }
                }
            }
            .frame(minWidth: 520, minHeight: 360)
        } else {
            LibraryView()
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    @State private var query: String = ""
    @State private var docs: [DocumentMeta] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, _ in
                        reload()
                    }

                Button("New") {
                    createDoc()
                }

                Button("Import HTML") {
                    importHTML()
                }

                Spacer()
            }
            .padding(12)

            List(docs, id: \.id) { d in
                Button {
                    openWindow(value: DocumentRoute(id: d.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(d.title ?? d.id)
                                .lineLimit(1)
                            Text(d.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dateString(d.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear { reload() }
    }

    private func reload() {
        guard let service = appModel.service else { return }
        do {
            docs = try service.listDocuments(query: query.isEmpty ? nil : query, tag: nil, limit: 200, offset: 0)
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    private func createDoc() {
        guard let service = appModel.service else { return }
        do {
            let doc = try service.createDocument(title: "Untitled")
            reload()
            openWindow(value: DocumentRoute(id: doc.frontMatter.id))
        } catch {
            loadError = String(describing: error)
        }
    }

    private func importHTML() {
        guard
            let layoutRoot = appModel.libraryRoot,
            let fileStore = appModel.fileStore,
            let indexStore = appModel.indexStore
        else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        panel.prompt = "Import"
        let response = panel.runModal()
        if response != .OK || panel.url == nil { return }

        do {
            let layout = LibraryLayout(root: layoutRoot)
            let importer = WeChatHTMLImporterImpl(
                layout: layout,
                fileStore: fileStore,
                indexStore: indexStore,
                assetStore: AssetStoreImpl(layout: layout)
            )
            let result = try importer.import(htmlFile: panel.url!, voiceProfileId: nil)
            reload()
            openWindow(value: DocumentRoute(id: result.documentId))
        } catch {
            loadError = String(describing: error)
        }
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}

