import Foundation

public struct TextStats {
    public var fillerWordHits: [(word: String, range: TextRange)]
    public var connectorWordHits: [(word: String, range: TextRange)]
    public var sentenceLengths: [Int]
    public var repeatedPhrases: [(phrase: String, ranges: [TextRange])]

    public init(
        fillerWordHits: [(word: String, range: TextRange)] = [],
        connectorWordHits: [(word: String, range: TextRange)] = [],
        sentenceLengths: [Int] = [],
        repeatedPhrases: [(phrase: String, ranges: [TextRange])] = []
    ) {
        self.fillerWordHits = fillerWordHits
        self.connectorWordHits = connectorWordHits
        self.sentenceLengths = sentenceLengths
        self.repeatedPhrases = repeatedPhrases
    }
}

public struct AnalysisContext {
    public var documentId: String
    public var body: String
    public var sentences: [Sentence]
    public var paragraphs: [Paragraph]
    public var outline: [OutlineNode]
    public var stats: TextStats
    public var voice: VoiceProfile?

    public init(
        documentId: String,
        body: String,
        sentences: [Sentence],
        paragraphs: [Paragraph],
        outline: [OutlineNode],
        stats: TextStats,
        voice: VoiceProfile?
    ) {
        self.documentId = documentId
        self.body = body
        self.sentences = sentences
        self.paragraphs = paragraphs
        self.outline = outline
        self.stats = stats
        self.voice = voice
    }
}

public enum Analyzer {
    public static func analyze(
        documentId: String,
        body: String,
        lexicon: Lexicon = .default,
        voice: VoiceProfile? = nil
    ) -> AnalysisContext {
        let sentences = TextSegmenter.sentences(body: body)
        let paragraphs = TextSegmenter.paragraphs(body: body)
        let outline = OutlineExtractor.extract(from: body)
        let stats = TextStatsBuilder.build(body: body, sentences: sentences, lexicon: lexicon)
        return .init(
            documentId: documentId,
            body: body,
            sentences: sentences,
            paragraphs: paragraphs,
            outline: outline,
            stats: stats,
            voice: voice
        )
    }
}

public struct Lexicon: Equatable, Codable, Sendable {
    public var fillerWords: [String]
    public var connectorWords: [String]

    public init(fillerWords: [String], connectorWords: [String]) {
        self.fillerWords = fillerWords
        self.connectorWords = connectorWords
    }

    public static let `default` = Lexicon(
        fillerWords: [
            "值得注意的是",
            "不难发现",
            "显而易见",
            "毋庸置疑",
            "总的来说",
            "综上所述",
            "从某种意义上",
            "在某种程度上",
            "有效提升",
            "显著提升",
            "深入推进",
            "赋能"
        ],
        connectorWords: [
            "此外",
            "同时",
            "然后",
            "因此",
            "所以",
            "不过",
            "但是",
            "然而",
            "另外",
            "最后",
            "首先",
            "其次",
            "总之"
        ]
    )
}

public enum TextStatsBuilder {
    public static func build(body: String, sentences: [Sentence], lexicon: Lexicon) -> TextStats {
        let ns = body as NSString
        var fillerHits: [(String, TextRange)] = []
        var connectorHits: [(String, TextRange)] = []

        for w in lexicon.fillerWords {
            for r in ns.ranges(of: w) {
                fillerHits.append((w, TextRange(start: r.location, end: r.location + r.length)))
            }
        }
        for w in lexicon.connectorWords {
            for r in ns.ranges(of: w) {
                connectorHits.append((w, TextRange(start: r.location, end: r.location + r.length)))
            }
        }

        let sentenceLengths = sentences.map { ($0.text as NSString).length }
        let repeatedPhrases = RepetitionDetector.detectRepeatedPhrases(body: body)

        return .init(
            fillerWordHits: fillerHits.sorted { $0.1.start < $1.1.start },
            connectorWordHits: connectorHits.sorted { $0.1.start < $1.1.start },
            sentenceLengths: sentenceLengths,
            repeatedPhrases: repeatedPhrases
        )
    }
}

private enum RepetitionDetector {
    static func detectRepeatedPhrases(body: String) -> [(phrase: String, ranges: [TextRange])] {
        let normalized = body.replacingOccurrences(of: "\n", with: " ")
        let n = (normalized as NSString).length
        if n < 20 { return [] }

        let window = 6
        var map: [String: [Int]] = [:]
        var i = 0
        while i + window <= n {
            let slice = (normalized as NSString).substring(with: NSRange(location: i, length: window))
            if slice.trimmingCharacters(in: .whitespacesAndNewlines).count < window { i += 1; continue }
            map[slice, default: []].append(i)
            i += 1
        }

        var out: [(String, [TextRange])] = []
        for (phrase, positions) in map {
            if positions.count < 2 { continue }
            if phrase.contains(" ") { continue }
            let ranges = positions.prefix(6).map { pos in
                let r = NSRange(location: pos, length: window)
                return TextRange(start: r.location, end: r.location + r.length)
            }
            out.append((phrase, ranges))
        }

        out.sort { $0.1.count > $1.1.count }
        return Array(out.prefix(10))
    }
}

private extension NSString {
    func ranges(of substring: String) -> [NSRange] {
        if substring.isEmpty { return [] }
        var out: [NSRange] = []
        var searchRange = NSRange(location: 0, length: length)
        while true {
            let found = range(of: substring, options: [], range: searchRange)
            if found.location == NSNotFound { break }
            out.append(found)
            let nextLoc = found.location + max(found.length, 1)
            if nextLoc >= length { break }
            searchRange = NSRange(location: nextLoc, length: length - nextLoc)
        }
        return out
    }
}
