import Foundation

public struct WritingCoachService {
    public var layout: LibraryLayout
    public var fileStore: DocumentFileStore
    public var indexStore: DocumentIndexStore

    public init(layout: LibraryLayout, fileStore: DocumentFileStore, indexStore: DocumentIndexStore) {
        self.layout = layout
        self.fileStore = fileStore
        self.indexStore = indexStore
    }

    public func createDocument(title: String?, source: String? = "local", voiceProfileId: String? = nil) throws -> DocumentContent {
        let content = try fileStore.createNew(title: title, source: source, voiceProfileId: voiceProfileId)
        try indexContent(content)
        return content
    }

    public func saveDocument(_ content: DocumentContent) throws {
        try fileStore.save(content)
        try indexContent(content)
    }

    public func loadDocument(id: String) throws -> DocumentContent {
        try fileStore.load(documentId: id)
    }

    public func analyzeDocument(id: String, lexicon: Lexicon = .default, voice: VoiceProfile? = nil, engine: RuleEngine = .default()) throws -> [Suggestion] {
        let content = try loadDocument(id: id)
        let ctx = Analyzer.analyze(documentId: id, body: content.body, lexicon: lexicon, voice: voice)
        return engine.run(ctx: ctx)
    }

    public func listDocuments(query: String? = nil, tag: String? = nil, limit: Int = 50, offset: Int = 0) throws -> [DocumentMeta] {
        try indexStore.fetchList(query: query, tag: tag, limit: limit, offset: offset)
    }

    private func indexContent(_ content: DocumentContent) throws {
        let bodyHash = WritingCoachHash.sha256Hex(content.body)
        let meta = DocumentMeta(
            id: content.frontMatter.id,
            path: "docs/\(content.frontMatter.id).md",
            title: content.frontMatter.title,
            createdAt: content.frontMatter.createdAt,
            updatedAt: content.frontMatter.updatedAt,
            source: content.frontMatter.source,
            voiceProfileId: content.frontMatter.voiceProfileId,
            bodyHash: bodyHash
        )
        try indexStore.upsert(meta: meta)
        try indexStore.setTags(documentId: meta.id, tagNames: content.frontMatter.tags)
    }
}

