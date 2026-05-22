import Foundation

public struct Sentence: Equatable, Sendable {
    public var text: String
    public var range: TextRange

    public init(text: String, range: TextRange) {
        self.text = text
        self.range = range
    }
}

public struct Paragraph: Equatable, Sendable {
    public var text: String
    public var range: TextRange

    public init(text: String, range: TextRange) {
        self.text = text
        self.range = range
    }
}

public enum TextSegmenter {
    public static func paragraphs(body: String) -> [Paragraph] {
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        var out: [Paragraph] = []

        var currentStart: Int? = nil
        var i = 0
        while i <= ns.length {
            let isEnd = i == ns.length
            let ch: unichar? = isEnd ? nil : ns.character(at: i)

            let isNewline = ch == 10
            if currentStart == nil {
                if isEnd { break }
                if isNewline {
                    i += 1
                    continue
                }
                currentStart = i
                i += 1
                continue
            }

            if isEnd {
                let start = currentStart!
                let range = NSRange(location: start, length: ns.length - start)
                let text = ns.substring(with: range).trimmingCharacters(in: .newlines)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(.init(text: text, range: .init(start: range.location, end: range.location + range.length)))
                }
                break
            }

            if isNewline {
                let nextIsNewline = (i + 1 < ns.length) ? ns.character(at: i + 1) == 10 : false
                if nextIsNewline {
                    let start = currentStart!
                    let end = i
                    let range = NSRange(location: start, length: end - start)
                    let text = ns.substring(with: range).trimmingCharacters(in: .newlines)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        out.append(.init(text: text, range: .init(start: range.location, end: range.location + range.length)))
                    }
                    currentStart = nil
                    i += 2
                    continue
                }
            }

            i += 1
        }

        _ = full
        return out
    }

    public static func sentences(body: String) -> [Sentence] {
        let ns = body as NSString
        var out: [Sentence] = []

        let delimiters: Set<unichar> = [0x3002, 0xff01, 0xff1f, 0xff1b, 0x2026, 0x002e, 0x003f, 0x0021, 0x003b]

        var start = 0
        var i = 0
        while i < ns.length {
            let ch = ns.character(at: i)
            if delimiters.contains(ch) {
                let end = i + 1
                let range = NSRange(location: start, length: end - start)
                let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    out.append(.init(text: text, range: .init(start: range.location, end: range.location + range.length)))
                }
                start = end
            }
            i += 1
        }

        if start < ns.length {
            let range = NSRange(location: start, length: ns.length - start)
            let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                out.append(.init(text: text, range: .init(start: range.location, end: range.location + range.length)))
            }
        }

        return out
    }
}

