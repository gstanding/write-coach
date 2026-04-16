import Foundation

public struct ImportResult: Equatable {
    public var documentId: String
    public var markdown: String
    public var assetCount: Int
    public var title: String?

    public init(documentId: String, markdown: String, assetCount: Int, title: String?) {
        self.documentId = documentId
        self.markdown = markdown
        self.assetCount = assetCount
        self.title = title
    }
}

public protocol WeChatHTMLImporter {
    func `import`(htmlFile: URL, voiceProfileId: String?) throws -> ImportResult
}

public struct WeChatHTMLImporterImpl: WeChatHTMLImporter {
    public var layout: LibraryLayout
    public var fileStore: DocumentFileStore
    public var indexStore: DocumentIndexStore
    public var assetStore: AssetStore

    public init(layout: LibraryLayout, fileStore: DocumentFileStore, indexStore: DocumentIndexStore, assetStore: AssetStore) {
        self.layout = layout
        self.fileStore = fileStore
        self.indexStore = indexStore
        self.assetStore = assetStore
    }

    public func `import`(htmlFile: URL, voiceProfileId: String?) throws -> ImportResult {
        let data = try Data(contentsOf: htmlFile)
        let html = String(decoding: data, as: UTF8.self)
        let blocks = HTMLToBlocks.convert(html: html)
        let title = blocks.compactMap { block -> String? in
            if case let .heading(level, text) = block, level <= 2 { return text }
            return nil
        }.first

        let doc = try fileStore.createNew(title: title, source: "wechat_html", voiceProfileId: voiceProfileId)
        let docId = doc.frontMatter.id

        var assetCount = 0
        let md = try MarkdownRenderer.render(blocks: blocks, documentId: docId, baseURL: htmlFile.deletingLastPathComponent(), assetStore: assetStore, libraryRoot: layout.root, assetCount: &assetCount)
        var content = doc
        content.frontMatter.updatedAt = Date()
        content.body = md.trimmingCharacters(in: .whitespacesAndNewlines)
        try fileStore.save(content)

        let bodyHash = WritingCoachHash.sha256Hex(content.body)
        let meta = DocumentMeta(
            id: docId,
            path: "docs/\(docId).md",
            title: content.frontMatter.title,
            createdAt: content.frontMatter.createdAt,
            updatedAt: content.frontMatter.updatedAt,
            source: content.frontMatter.source,
            voiceProfileId: content.frontMatter.voiceProfileId,
            bodyHash: bodyHash
        )
        try indexStore.upsert(meta: meta)
        try indexStore.setTags(documentId: docId, tagNames: content.frontMatter.tags)

        return .init(documentId: docId, markdown: md, assetCount: assetCount, title: title)
    }
}

enum SemanticBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case quote(text: String)
    case list(items: [String], ordered: Bool)
    case code(language: String?, code: String)
    case image(alt: String?, src: String)
    case horizontalRule
}

private enum HTMLToBlocks {
    static func convert(html: String) -> [SemanticBlock] {
        let tokens = HTMLTokenizer.tokenize(html)
        var blocks: [SemanticBlock] = []

        var currentText = ""
        var currentTag: String? = nil

        var listOrdered: Bool? = nil
        var listItems: [String] = []
        var currentListItem = ""
        var inListItem = false

        func flushCurrentText() {
            let t = currentText.cleanedInline()
            guard let tag = currentTag else {
                currentText = ""
                return
            }
            if t.isEmpty {
                currentText = ""
                currentTag = nil
                return
            }
            switch tag {
            case "p", "div":
                blocks.append(.paragraph(text: t))
            case "blockquote":
                blocks.append(.quote(text: t))
            case "h1":
                blocks.append(.heading(level: 1, text: t))
            case "h2":
                blocks.append(.heading(level: 2, text: t))
            case "h3":
                blocks.append(.heading(level: 3, text: t))
            case "h4":
                blocks.append(.heading(level: 4, text: t))
            case "pre":
                blocks.append(.code(language: nil, code: currentText.trimCode()))
            default:
                break
            }
            currentText = ""
            currentTag = nil
        }

        func flushListIfNeeded() {
            guard let ordered = listOrdered else { return }
            let items = listItems.map { $0.cleanedInline() }.filter { !$0.isEmpty }
            if !items.isEmpty {
                blocks.append(.list(items: items, ordered: ordered))
            }
            listOrdered = nil
            listItems = []
            currentListItem = ""
        }

        for token in tokens {
            switch token {
            case .start(let name, let attrs, let selfClosing):
                if name == "img" {
                    let src = attrs["src"]
                    let alt = attrs["alt"]
                    if let src, !src.isEmpty {
                        blocks.append(.image(alt: alt, src: src))
                    }
                    continue
                }

                if name == "hr" {
                    blocks.append(.horizontalRule)
                    continue
                }

                if name == "ul" {
                    flushCurrentText()
                    flushListIfNeeded()
                    listOrdered = false
                    continue
                }
                if name == "ol" {
                    flushCurrentText()
                    flushListIfNeeded()
                    listOrdered = true
                    continue
                }
                if name == "li" {
                    currentListItem = ""
                    inListItem = true
                    continue
                }

                if ["p", "blockquote", "h1", "h2", "h3", "h4", "pre"].contains(name) {
                    flushCurrentText()
                    currentTag = name
                    currentText = ""
                }

                if selfClosing {
                    continue
                }

            case .end(let name):
                if name == "li" {
                    if listOrdered != nil {
                        let v = currentListItem.cleanedInline()
                        if !v.isEmpty { listItems.append(v) }
                        currentListItem = ""
                    }
                    inListItem = false
                    continue
                }
                if name == "ul" || name == "ol" {
                    flushListIfNeeded()
                    continue
                }
                if name == currentTag {
                    flushCurrentText()
                }

            case .text(let t):
                if listOrdered != nil && inListItem {
                    currentListItem += t
                } else if currentTag != nil {
                    currentText += t
                } else {
                    currentText += t
                }
            }
        }

        flushCurrentText()
        flushListIfNeeded()

        return blocks
            .map { block in
                switch block {
                case .paragraph(let t) where t.hasPrefix("var ") || t.hasPrefix("window."):
                    return .paragraph(text: "")
                default:
                    return block
                }
            }
            .filter { block in
                switch block {
                case .paragraph(let t):
                    return !t.isEmptyOrWhitespace
                default:
                    return true
                }
            }
    }
}

private enum MarkdownRenderer {
    static func render(blocks: [SemanticBlock], documentId: String, baseURL: URL, assetStore: AssetStore, libraryRoot: URL, assetCount: inout Int) throws -> String {
        var out: [String] = []
        for b in blocks {
            switch b {
            case .heading(let level, let text):
                let hashes = String(repeating: "#", count: max(1, min(level, 6)))
                out.append("\(hashes) \(text)")
                out.append("")
            case .paragraph(let text):
                out.append(text)
                out.append("")
            case .quote(let text):
                let lines = text.split(separator: "\n").map { "> \($0)" }
                out.append(contentsOf: lines)
                out.append("")
            case .list(let items, let ordered):
                for (idx, item) in items.enumerated() {
                    if ordered {
                        out.append("\(idx + 1). \(item)")
                    } else {
                        out.append("- \(item)")
                    }
                }
                out.append("")
            case .code(let language, let code):
                out.append("```\(language ?? "")")
                out.append(code.trimCode())
                out.append("```")
                out.append("")
            case .image(let alt, let src):
                let resolved = resolveImage(src: src, baseURL: baseURL)
                if let resolved, resolved.isFileURL, let data = try? Data(contentsOf: resolved) {
                    let ext = resolved.pathExtension.isEmpty ? "png" : resolved.pathExtension
                    let saved = try assetStore.put(data: data, ext: ext, documentId: documentId)
                    let rel = assetStore.relativePath(from: libraryRoot, assetURL: saved)
                    assetCount += 1
                    out.append("![\(alt ?? "")](\(rel))")
                    out.append("")
                } else {
                    out.append("![\(alt ?? "")](\(src))")
                    out.append("")
                }
            case .horizontalRule:
                out.append("---")
                out.append("")
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func resolveImage(src: String, baseURL: URL) -> URL? {
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            return URL(string: src)
        }
        if src.hasPrefix("file://") {
            return URL(string: src)
        }
        return baseURL.appendingPathComponent(src)
    }
}

private enum HTMLToken: Equatable {
    case start(name: String, attrs: [String: String], selfClosing: Bool)
    case end(name: String)
    case text(String)
}

private enum HTMLTokenizer {
    static func tokenize(_ html: String) -> [HTMLToken] {
        let s = html
        var tokens: [HTMLToken] = []
        var i = s.startIndex

        func emitText(_ t: String) {
            let decoded = HTMLEntities.decode(t)
            if !decoded.isEmpty {
                tokens.append(.text(decoded))
            }
        }

        var textBuffer = ""
        while i < s.endIndex {
            let ch = s[i]
            if ch == "<" {
                if !textBuffer.isEmpty {
                    emitText(textBuffer)
                    textBuffer = ""
                }
                guard let close = s[i...].firstIndex(of: ">") else { break }
                let raw = String(s[s.index(after: i)..<close])
                i = s.index(after: close)

                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("!--") { continue }
                if trimmed.hasPrefix("!") { continue }
                if trimmed.hasPrefix("?") { continue }

                if trimmed.hasPrefix("/") {
                    let name = trimmed.dropFirst().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? ""
                    if !name.isEmpty {
                        tokens.append(.end(name: name.lowercased()))
                    }
                    continue
                }

                let selfClosing = trimmed.hasSuffix("/")
                let cleaned = selfClosing ? String(trimmed.dropLast()) : trimmed
                let parts = cleaned.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                guard let first = parts.first else { continue }
                let name = first.lowercased()
                let attrsString = cleaned.dropFirst(first.count)
                let attrs = HTMLAttributes.parse(String(attrsString))
                tokens.append(.start(name: name, attrs: attrs, selfClosing: selfClosing || name == "img" || name == "br" || name == "hr"))
                continue
            }
            textBuffer.append(ch)
            i = s.index(after: i)
        }

        if !textBuffer.isEmpty {
            emitText(textBuffer)
        }

        return tokens
    }
}

private enum HTMLAttributes {
    static func parse(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        var i = s.startIndex

        func skipSpaces() {
            while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
        }

        while i < s.endIndex {
            skipSpaces()
            if i >= s.endIndex { break }
            let keyStart = i
            while i < s.endIndex, !s[i].isWhitespace, s[i] != "=" { i = s.index(after: i) }
            let key = s[keyStart..<i].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            skipSpaces()
            if i < s.endIndex, s[i] == "=" {
                i = s.index(after: i)
                skipSpaces()
                if i >= s.endIndex { break }
                let quote = s[i]
                if quote == "\"" || quote == "'" {
                    i = s.index(after: i)
                    let valueStart = i
                    while i < s.endIndex, s[i] != quote { i = s.index(after: i) }
                    let value = String(s[valueStart..<i])
                    if i < s.endIndex { i = s.index(after: i) }
                    if !key.isEmpty { out[key] = value }
                } else {
                    let valueStart = i
                    while i < s.endIndex, !s[i].isWhitespace { i = s.index(after: i) }
                    let value = String(s[valueStart..<i])
                    if !key.isEmpty { out[key] = value }
                }
            } else {
                if !key.isEmpty { out[key] = "true" }
            }
        }
        return out
    }
}

private enum HTMLEntities {
    static func decode(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&nbsp;", with: " ")
        out = out.replacingOccurrences(of: "&lt;", with: "<")
        out = out.replacingOccurrences(of: "&gt;", with: ">")
        out = out.replacingOccurrences(of: "&amp;", with: "&")
        out = out.replacingOccurrences(of: "&quot;", with: "\"")
        out = out.replacingOccurrences(of: "&#39;", with: "'")
        out = decodeNumeric(out)
        return out
    }

    private static func decodeNumeric(_ s: String) -> String {
        let pattern = "&#(\\d+);"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return s }
        var result = s
        for m in matches.reversed() {
            guard m.numberOfRanges == 2 else { continue }
            let numStr = ns.substring(with: m.range(at: 1))
            guard let num = Int(numStr), let scalar = UnicodeScalar(num) else { continue }
            let ch = String(Character(scalar))
            let r = Range(m.range, in: result)!
            result.replaceSubrange(r, with: ch)
        }
        return result
    }
}

private extension String {
    var isEmptyOrWhitespace: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func cleanedInline() -> String {
        let replaced = replacingOccurrences(of: "\u{00a0}", with: " ")
        let collapsed = replaced.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trimCode() -> String {
        trimmingCharacters(in: .newlines)
    }
}
