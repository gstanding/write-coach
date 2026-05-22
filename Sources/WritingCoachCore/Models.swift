import Foundation

public struct DocumentContent: Equatable {
    public var frontMatter: FrontMatter
    public var body: String

    public init(frontMatter: FrontMatter, body: String) {
        self.frontMatter = frontMatter
        self.body = body
    }
}

public struct FrontMatter: Equatable, Codable {
    public var id: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var source: String?
    public var voiceProfileId: String?
    public var tags: [String]

    public init(
        id: String,
        title: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        source: String? = nil,
        voiceProfileId: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.voiceProfileId = voiceProfileId
        self.tags = tags
    }
}

public enum SuggestionCategory: String, Codable, Sendable {
    case structure
    case language
    case consistency
    case readability
}

public enum SuggestionSeverity: String, Codable, Sendable {
    case info
    case warn
    case error
}

public struct TextRange: Hashable, Codable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var length: Int { end - start }
}

public struct Fix: Hashable, Codable, Sendable {
    public var title: String
    public var range: TextRange
    public var replacement: String

    public init(title: String, range: TextRange, replacement: String) {
        self.title = title
        self.range = range
        self.replacement = replacement
    }
}

public struct Suggestion: Hashable, Codable, Sendable {
    public var id: String
    public var ruleId: String
    public var category: SuggestionCategory
    public var severity: SuggestionSeverity
    public var range: TextRange
    public var message: String
    public var fixes: [Fix]

    public init(
        id: String,
        ruleId: String,
        category: SuggestionCategory,
        severity: SuggestionSeverity,
        range: TextRange,
        message: String,
        fixes: [Fix]
    ) {
        self.id = id
        self.ruleId = ruleId
        self.category = category
        self.severity = severity
        self.range = range
        self.message = message
        self.fixes = fixes
    }
}

