import Foundation

public protocol DocumentFileStore {
    func load(documentId: String) throws -> DocumentContent
    func save(_ content: DocumentContent) throws
    func path(for documentId: String) -> URL
    func createNew(title: String?, source: String?, voiceProfileId: String?) throws -> DocumentContent
}

public struct DocumentFileStoreImpl: DocumentFileStore {
    public var layout: LibraryLayout

    public init(layout: LibraryLayout) {
        self.layout = layout
    }

    public func path(for documentId: String) -> URL {
        layout.docPath(id: documentId)
    }

    public func load(documentId: String) throws -> DocumentContent {
        let url = path(for: documentId)
        let data = try Data(contentsOf: url)
        let markdown = String(decoding: data, as: UTF8.self)
        let decoded = try FrontMatterCodec.decodeDocument(markdown)
        if let fm = decoded.frontMatter {
            return .init(frontMatter: fm, body: decoded.body)
        }

        let now = Date()
        let fm = FrontMatter(id: documentId, title: nil, createdAt: now, updatedAt: now, source: nil, voiceProfileId: nil, tags: [])
        return .init(frontMatter: fm, body: decoded.body)
    }

    public func save(_ content: DocumentContent) throws {
        let url = path(for: content.frontMatter.id)
        let encoded = FrontMatterCodec.encodeDocument(content)
        guard let data = encoded.data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
    }

    public func createNew(title: String?, source: String?, voiceProfileId: String?) throws -> DocumentContent {
        let id = ULID.generate()
        let now = Date()
        let fm = FrontMatter(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            source: source,
            voiceProfileId: voiceProfileId,
            tags: []
        )
        let content = DocumentContent(frontMatter: fm, body: "")
        try save(content)
        return content
    }
}
