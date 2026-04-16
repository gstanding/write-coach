import SwiftUI
import WritingCoachCore

@main
struct WritingCoachiOSApp: App {
    @StateObject private var model = IOSAppModel()

    var body: some Scene {
        WindowGroup {
            IOSLibraryView()
                .environmentObject(model)
        }
    }
}

final class IOSAppModel: ObservableObject {
    @Published var service: WritingCoachService?

    init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WritingCoachLibrary", isDirectory: true)
        let layout = LibraryLayout(root: root)
        do {
            try LibraryBootstrapper.ensureInitialized(layout: layout)
            let fileStore = DocumentFileStoreImpl(layout: layout)
            let indexStore = try DocumentIndexStoreImpl(dbURL: layout.indexDB)
            service = WritingCoachService(layout: layout, fileStore: fileStore, indexStore: indexStore)
        } catch {
            service = nil
        }
    }
}

