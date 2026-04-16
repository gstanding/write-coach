import Foundation

public struct LibraryLayout: Equatable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public var docsDir: URL { root.appendingPathComponent("docs", isDirectory: true) }
    public var assetsDir: URL { root.appendingPathComponent("assets", isDirectory: true) }
    public var indexDB: URL { root.appendingPathComponent("index.sqlite", isDirectory: false) }
    public var settingsJSON: URL { root.appendingPathComponent("settings.json", isDirectory: false) }

    public func docPath(id: String) -> URL {
        docsDir.appendingPathComponent("\(id).md", isDirectory: false)
    }

    public func assetDir(documentId: String) -> URL {
        assetsDir.appendingPathComponent(documentId, isDirectory: true)
    }
}

public enum LibraryBootstrapper {
    public static func ensureInitialized(layout: LibraryLayout) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: layout.docsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.assetsDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: layout.indexDB.path) {
            fm.createFile(atPath: layout.indexDB.path, contents: nil)
        }
        if !fm.fileExists(atPath: layout.settingsJSON.path) {
            let data = Data("{\"version\":1}\n".utf8)
            fm.createFile(atPath: layout.settingsJSON.path, contents: data)
        }
    }
}

