import Foundation

public protocol AssetStore {
    func put(data: Data, ext: String, documentId: String) throws -> URL
    func relativePath(from root: URL, assetURL: URL) -> String
}

public struct AssetStoreImpl: AssetStore {
    public var layout: LibraryLayout

    public init(layout: LibraryLayout) {
        self.layout = layout
    }

    public func put(data: Data, ext: String, documentId: String) throws -> URL {
        let dir = layout.assetDir(documentId: documentId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let digest = SHA256Hasher.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let file = dir.appendingPathComponent("\(hex).\(ext)", isDirectory: false)
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file, options: .atomic)
        }
        return file
    }

    public func relativePath(from root: URL, assetURL: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let assetPath = assetURL.standardizedFileURL.path
        if assetPath.hasPrefix(rootPath + "/") {
            return String(assetPath.dropFirst(rootPath.count + 1))
        }
        return assetURL.path
    }
}
