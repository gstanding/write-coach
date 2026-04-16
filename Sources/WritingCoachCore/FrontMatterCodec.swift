import Foundation

public enum FrontMatterCodec {
    public struct DecodeResult: Equatable {
        public var frontMatter: FrontMatter?
        public var body: String
    }

    public enum CodecError: Error, CustomStringConvertible {
        case invalidFrontMatter
        case missingRequiredField(String)
        case invalidDate(String)

        public var description: String {
            switch self {
            case .invalidFrontMatter:
                return "invalid_front_matter"
            case .missingRequiredField(let k):
                return "missing_required_field:\(k)"
            case .invalidDate(let s):
                return "invalid_date:\(s)"
            }
        }
    }

    public static func decodeDocument(_ markdown: String) throws -> DecodeResult {
        let trimmed = markdown
        guard trimmed.hasPrefix("---") else {
            return .init(frontMatter: nil, body: markdown)
        }

        let ns = trimmed as NSString
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3 else { throw CodecError.invalidFrontMatter }
        guard lines.first == "---" else { throw CodecError.invalidFrontMatter }

        var endLineIndex: Int?
        for i in 1..<lines.count {
            if lines[i] == "---" {
                endLineIndex = i
                break
            }
        }
        guard let endIdx = endLineIndex else { throw CodecError.invalidFrontMatter }

        let fmLines = lines[1..<endIdx].map(String.init)
        let bodyLines = lines[(endIdx + 1)...].map(String.init)
        let body = bodyLines.joined(separator: "\n").dropLeadingNewlines()

        let map = try parseYAMLSubset(fmLines)
        let frontMatter = try frontMatter(from: map)
        _ = ns
        return .init(frontMatter: frontMatter, body: body)
    }

    public static func encodeDocument(_ content: DocumentContent) -> String {
        let fm = encodeFrontMatter(content.frontMatter)
        let body = content.body.trimmingCharacters(in: .newlines)
        return "---\n\(fm)\n---\n\n\(body)\n"
    }

    public static func encodeFrontMatter(_ fm: FrontMatter) -> String {
        let f = makeFormatter()
        var lines: [String] = []
        lines.append("id: \"\(escape(fm.id))\"")
        if let title = fm.title, !title.isEmpty {
            lines.append("title: \"\(escape(title))\"")
        }
        lines.append("createdAt: \"\(f.string(from: fm.createdAt))\"")
        lines.append("updatedAt: \"\(f.string(from: fm.updatedAt))\"")
        if let source = fm.source, !source.isEmpty {
            lines.append("source: \"\(escape(source))\"")
        }
        if let vp = fm.voiceProfileId, !vp.isEmpty {
            lines.append("voiceProfileId: \"\(escape(vp))\"")
        }
        if fm.tags.isEmpty {
            lines.append("tags: []")
        } else {
            let joined = fm.tags.map { "\"\(escape($0))\"" }.joined(separator: ", ")
            lines.append("tags: [\(joined)]")
        }
        return lines.joined(separator: "\n")
    }

    private static func frontMatter(from map: YAMLMap) throws -> FrontMatter {
        guard let id = map.scalars["id"] else { throw CodecError.missingRequiredField("id") }
        guard let createdAtString = map.scalars["createdAt"] else { throw CodecError.missingRequiredField("createdAt") }
        guard let updatedAtString = map.scalars["updatedAt"] else { throw CodecError.missingRequiredField("updatedAt") }

        let f = makeFormatter()
        guard let createdAt = f.date(from: createdAtString) else {
            throw CodecError.invalidDate(createdAtString)
        }
        guard let updatedAt = f.date(from: updatedAtString) else {
            throw CodecError.invalidDate(updatedAtString)
        }

        let title = map.scalars["title"]
        let source = map.scalars["source"]
        let voiceProfileId = map.scalars["voiceProfileId"]
        let tags = map.arrays["tags"] ?? []

        return FrontMatter(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: source,
            voiceProfileId: voiceProfileId,
            tags: tags
        )
    }

    private static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}

private struct YAMLMap: Equatable {
    var scalars: [String: String] = [:]
    var arrays: [String: [String]] = [:]
}

private func parseYAMLSubset(_ lines: [String]) throws -> YAMLMap {
    var map = YAMLMap()

    var i = 0
    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            i += 1
            continue
        }

        if line.hasPrefix("#") {
            i += 1
            continue
        }

        if let colon = line.firstIndex(of: ":") {
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if rest == "" {
                var items: [String] = []
                var j = i + 1
                while j < lines.count {
                    let raw = lines[j]
                    if raw.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                        let v = raw.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)
                        items.append(unquote(String(v)))
                        j += 1
                        continue
                    }
                    break
                }
                map.arrays[key] = items
                i = j
                continue
            }

            if rest.hasPrefix("[") && rest.hasSuffix("]") {
                let inner = rest.dropFirst().dropLast()
                let parts = inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                map.arrays[key] = parts.filter { !$0.isEmpty }
                i += 1
                continue
            }

            map.scalars[key] = unquote(rest)
            i += 1
            continue
        }

        throw FrontMatterCodec.CodecError.invalidFrontMatter
    }

    return map
}

private func unquote(_ s: String) -> String {
    var v = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 {
        v = String(v.dropFirst().dropLast())
    }
    v = v.replacingOccurrences(of: "\\\"", with: "\"")
    v = v.replacingOccurrences(of: "\\\\", with: "\\")
    return v
}

private extension String {
    func dropLeadingNewlines() -> String {
        var s = self
        while s.hasPrefix("\n") {
            s.removeFirst()
        }
        return s
    }
}
