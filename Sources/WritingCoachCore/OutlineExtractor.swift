import Foundation

public struct OutlineNode: Equatable {
    public var level: Int
    public var title: String
    public var range: TextRange

    public init(level: Int, title: String, range: TextRange) {
        self.level = level
        self.title = title
        self.range = range
    }
}

public enum OutlineExtractor {
    public static func extract(from body: String, maxLevel: Int = 4) -> [OutlineNode] {
        let ns = body as NSString
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)

        var out: [OutlineNode] = []
        var offset = 0
        for lineSub in lines {
            let line = String(lineSub)
            let lineLength = (line as NSString).length
            defer { offset += lineLength + 1 }

            guard line.hasPrefix("#") else { continue }
            let hashes = line.prefix { $0 == "#" }.count
            guard hashes >= 1 && hashes <= maxLevel else { continue }

            let afterHashes = line.dropFirst(hashes)
            guard afterHashes.first == " " else { continue }
            let title = afterHashes.dropFirst().trimmingCharacters(in: .whitespaces)
            if title.isEmpty { continue }

            let range = TextRange(start: offset, end: offset + lineLength)
            out.append(.init(level: hashes, title: title, range: range))
        }

        _ = ns
        return out
    }
}

