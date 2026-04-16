import Foundation

public protocol Rule {
    var id: String { get }
    func analyze(_ ctx: AnalysisContext) -> [Suggestion]
}

public struct RuleEngine {
    public var rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public static func `default`(lexicon: Lexicon = .default) -> RuleEngine {
        RuleEngine(rules: [
            FillerWordRule(),
            ConnectorDensityRule(),
            SentenceLengthUniformityRule(),
            RepeatedSentenceStartRule(),
            RepeatedPhraseRule(),
            MissingEvidenceHintRule()
        ])
    }

    public func run(ctx: AnalysisContext) -> [Suggestion] {
        var out: [Suggestion] = []
        for r in rules {
            out.append(contentsOf: r.analyze(ctx))
        }
        return out.sorted { $0.range.start < $1.range.start }
    }
}

private enum SuggestionId {
    static func make(docId: String, ruleId: String, range: TextRange, key: String) -> String {
        let s = "\(docId)|\(ruleId)|\(range.start)-\(range.end)|\(key)"
        return WritingCoachHash.sha256Hex(s)
    }
}

public struct FillerWordRule: Rule {
    public let id = "STYLE.FILLER_WORDS"

    public init() {}

    public func analyze(_ ctx: AnalysisContext) -> [Suggestion] {
        guard !ctx.stats.fillerWordHits.isEmpty else { return [] }
        var out: [Suggestion] = []
        for (w, r) in ctx.stats.fillerWordHits.prefix(50) {
            let msg = "出现套话/空泛表达“\(w)”。可以删掉或改成更具体的陈述。"
            let fixes = [
                Fix(title: "删除该表达", range: r, replacement: ""),
                Fix(title: "改成更具体", range: r, replacement: "（这里直接说清楚你的观点/依据）")
            ]
            out.append(.init(
                id: SuggestionId.make(docId: ctx.documentId, ruleId: id, range: r, key: w),
                ruleId: id,
                category: .language,
                severity: .warn,
                range: r,
                message: msg,
                fixes: fixes
            ))
        }
        return out
    }
}

public struct ConnectorDensityRule: Rule {
    public let id = "STYLE.CONNECTOR_DENSITY"

    public init() {}

    public func analyze(_ ctx: AnalysisContext) -> [Suggestion] {
        let hits = ctx.stats.connectorWordHits
        guard !hits.isEmpty else { return [] }
        let ns = ctx.body as NSString
        let totalLen = max(ns.length, 1)
        let per200 = Double(hits.count) / Double(totalLen) * 200.0
        let threshold = 3.5
        guard per200 >= threshold else { return [] }

        let range = TextRange(start: 0, end: min(ns.length, 200))
        let sample = ns.substring(with: NSRange(location: range.start, length: range.length))
        let removed = sample.replacingOccurrences(
            of: "(此外|同时|然后|因此|所以|不过|但是|然而|另外|最后|首先|其次|总之)[，, ]*",
            with: "",
            options: .regularExpression
        )
        let msg = "连接词使用偏密（约每 200 字 \(String(format: "%.1f", per200)) 个）。可以删除部分“此外/同时/然后/因此”等，让转折更自然。"
        let fixes = [
            Fix(title: "删除一批连接词", range: range, replacement: removed),
            Fix(title: "删掉开头连接词", range: range, replacement: removed.trimmingCharacters(in: .whitespacesAndNewlines))
        ]

        return [
            .init(
                id: SuggestionId.make(docId: ctx.documentId, ruleId: id, range: range, key: "density"),
                ruleId: id,
                category: .readability,
                severity: .info,
                range: range,
                message: msg,
                fixes: fixes
            )
        ]
    }
}

public struct SentenceLengthUniformityRule: Rule {
    public let id = "STYLE.SENTENCE_LENGTH_UNIFORMITY"

    public init() {}

    public func analyze(_ ctx: AnalysisContext) -> [Suggestion] {
        let lengths = ctx.stats.sentenceLengths
        guard lengths.count >= 8 else { return [] }

        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let variance = lengths.map { (Double($0) - mean) * (Double($0) - mean) }.reduce(0, +) / Double(lengths.count)
        let std = sqrt(variance)

        let baselineStd = ctx.voice?.sentenceLengthStd ?? 10.0
        let threshold = max(4.0, baselineStd * 0.45)
        guard std < threshold else { return [] }

        guard let first = ctx.sentences.first else { return [] }
        let r = TextRange(start: first.range.start, end: first.range.end)
        let msg = "句子长度分布偏均匀（std≈\(String(format: "%.1f", std))）。可以混入几句更短/更长的句子，节奏会更像人写。"
        let fixes = [
            Fix(title: "把这句拆短", range: r, replacement: first.text.replacingOccurrences(of: "，", with: "。")),
            Fix(title: "加一个个人化补充", range: r, replacement: first.text + "（我自己更倾向于先把关键点说出来。）")
        ]
        return [
            .init(
                id: SuggestionId.make(docId: ctx.documentId, ruleId: id, range: r, key: "uniform"),
                ruleId: id,
                category: .readability,
                severity: .info,
                range: r,
                message: msg,
                fixes: fixes
            )
        ]
    }
}

public struct RepeatedSentenceStartRule: Rule {
    public let id = "STYLE.REPEATED_SENTENCE_START"

    public init() {}

    public func analyze(_ ctx: AnalysisContext) -> [Suggestion] {
        let starts = ctx.sentences.map { sentence -> (String, TextRange) in
            let s = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = String(s.prefix(4))
            return (prefix, sentence.range)
        }

        var counts: [String: [(TextRange)]] = [:]
        for (p, r) in starts {
            if p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            counts[p, default: []].append(r)
        }

        guard let (p, ranges) = counts.max(by: { $0.value.count < $1.value.count }), ranges.count >= 4 else {
            return []
        }

        let r = ranges[0]
        let msg = "多句以相同开头“\(p)”起句（≥\(ranges.count) 次）。可以换一种起句方式或直接删掉起手式。"
        let fixes = [
            Fix(title: "删掉起句前缀", range: TextRange(start: r.start, end: min(r.end, r.start + (p as NSString).length)), replacement: ""),
            Fix(title: "改成更具体的起句", range: TextRange(start: r.start, end: min(r.end, r.start + (p as NSString).length)), replacement: "我更在意的是")
        ]
        return [
            .init(
                id: SuggestionId.make(docId: ctx.documentId, ruleId: id, range: r, key: p),
                ruleId: id,
                category: .language,
                severity: .warn,
                range: r,
                message: msg,
                fixes: fixes
            )
        ]
    }
}

public struct RepeatedPhraseRule: Rule {
    public let id = "STYLE.REPEATED_PHRASE"

    public init() {}

    public func analyze(_ ctx: AnalysisContext) -> [Suggestion] {
        guard let top = ctx.stats.repeatedPhrases.first, top.ranges.count >= 2 else { return [] }
        guard let firstRange = top.ranges.first else { return [] }
        let msg = "出现重复短语“\(top.phrase)”（≥\(top.ranges.count) 次）。可以替换其中几处，或删掉一处避免啰嗦。"
        let fixes = [
            Fix(title: "删除这一处", range: firstRange, replacement: ""),
            Fix(title: "换个说法", range: firstRange, replacement: "（换一种表达）")
        ]
        return [
            .init(
                id: SuggestionId.make(docId: ctx.documentId, ruleId: id, range: firstRange, key: top.phrase),
                ruleId: id,
                category: .language,
                severity: .info,
                range: firstRange,
                message: msg,
                fixes: fixes
            )
        ]
    }
}

public struct MissingEvidenceHintRule: Rule {
    public let id = "STRUCT.MISSING_EVIDENCE_HINT"

    public init() {}

    public func analyze(_ ctx: AnalysisContext) -> [Suggestion] {
        let keywords = ["我认为", "结论是", "总之", "所以", "显然", "本质上"]
        let evidence = ["例如", "比如", "数据", "引用", "案例", "实验", "统计"]
        let ns = ctx.body as NSString
        let body = ctx.body

        let hasClaim = keywords.contains { body.contains($0) }
        let hasEvidence = evidence.contains { body.contains($0) }
        guard hasClaim && !hasEvidence else { return [] }

        let range = TextRange(start: 0, end: min(ns.length, 1))
        let msg = "文本里出现明显结论/判断，但证据或例子偏少。可以补 1 个具体例子、数据或反例，长文逻辑会更扎实。"
        let fixes = [
            Fix(title: "插入一个例子占位", range: range, replacement: "例如：这里补一个具体例子（场景/数字/对比）。\n\n")
        ]
        return [
            .init(
                id: SuggestionId.make(docId: ctx.documentId, ruleId: id, range: range, key: "hint"),
                ruleId: id,
                category: .structure,
                severity: .info,
                range: range,
                message: msg,
                fixes: fixes
            )
        ]
    }
}
