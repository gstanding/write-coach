import SwiftUI
import WritingCoachCore

@main
struct WritingCoachMacApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Library") {
            LibraryRootView()
                .environmentObject(appModel)
        }
        WindowGroup(for: DocumentRoute.self) { $route in
            if let route {
                EditorView(documentId: route.id)
                    .environmentObject(appModel)
            } else {
                Text("No document")
            }
        }
    }
}

struct DocumentRoute: Hashable, Codable {
    var id: String
}

final class AppModel: ObservableObject {
    @Published var libraryRoot: URL?
    @Published var service: WritingCoachService?
    @Published var indexStore: DocumentIndexStore?
    @Published var fileStore: DocumentFileStore?

    private let bookmarkKey = "writingcoach.library.bookmark"

    init() {
        if let root = loadBookmarkURL() {
            configure(root: root)
        }
    }

    func chooseLibrary() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            saveBookmark(url: url)
            configure(root: url)
        }
    }

    private func configure(root: URL) {
        let layout = LibraryLayout(root: root)
        do {
            try LibraryBootstrapper.ensureInitialized(layout: layout)
            let fileStore = DocumentFileStoreImpl(layout: layout)
            let indexStore = try DocumentIndexStoreImpl(dbURL: layout.indexDB)
            let service = WritingCoachService(layout: layout, fileStore: fileStore, indexStore: indexStore)
            DispatchQueue.main.async {
                self.libraryRoot = root
                self.service = service
                self.indexStore = indexStore
                self.fileStore = fileStore
            }
        } catch {
            DispatchQueue.main.async {
                self.libraryRoot = nil
                self.service = nil
                self.indexStore = nil
                self.fileStore = nil
            }
        }
    }

    private func saveBookmark(url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
        }
    }

    private func loadBookmarkURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
}

