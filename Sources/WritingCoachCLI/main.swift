import Foundation
import WritingCoachCore

enum CLIError: Error, CustomStringConvertible {
    case invalidArgs
    case missingRoot

    var description: String {
        switch self {
        case .invalidArgs: return "invalid_args"
        case .missingRoot: return "missing_root"
        }
    }
}

struct CLI {
    static func run() throws {
        var args = CommandLine.arguments
        _ = args.removeFirst()
        guard let command = args.first else {
            print(usage())
            return
        }
        _ = args.removeFirst()

        let root = try parseOption(&args, name: "--root") ?? ""
        if root.isEmpty {
            throw CLIError.missingRoot
        }
        let layout = LibraryLayout(root: URL(fileURLWithPath: root, isDirectory: true))
        try LibraryBootstrapper.ensureInitialized(layout: layout)

        let fileStore = DocumentFileStoreImpl(layout: layout)
        let indexStore = try DocumentIndexStoreImpl(dbURL: layout.indexDB)
        let service = WritingCoachService(layout: layout, fileStore: fileStore, indexStore: indexStore)

        switch command {
        case "init":
            print("ok")

        case "new":
            let title = try parseOption(&args, name: "--title")
            let content = try service.createDocument(title: title)
            print(content.frontMatter.id)

        case "list":
            let query = try parseOption(&args, name: "--query")
            let docs = try service.listDocuments(query: query, tag: nil, limit: 50, offset: 0)
            for d in docs {
                print("\(d.id)\t\(d.title ?? "")\t\(ISO8601DateFormatter().string(from: d.updatedAt))")
            }

        case "import-wechat-html":
            guard let path = try parseOption(&args, name: "--file") else { throw CLIError.invalidArgs }
            let assetStore = AssetStoreImpl(layout: layout)
            let importer = WeChatHTMLImporterImpl(layout: layout, fileStore: fileStore, indexStore: indexStore, assetStore: assetStore)
            let result = try importer.import(htmlFile: URL(fileURLWithPath: path), voiceProfileId: nil)
            print(result.documentId)

        case "analyze":
            guard let id = try parseOption(&args, name: "--id") else { throw CLIError.invalidArgs }
            let suggestions = try service.analyzeDocument(id: id)
            for s in suggestions {
                print("[\(s.severity.rawValue)] \(s.ruleId) \(s.range.start)-\(s.range.end) \(s.message)")
            }

        default:
            print(usage())
        }
    }

    private static func parseOption(_ args: inout [String], name: String) throws -> String? {
        if let idx = args.firstIndex(of: name) {
            if idx + 1 >= args.count { throw CLIError.invalidArgs }
            let v = args[idx + 1]
            args.removeSubrange(idx...(idx + 1))
            return v
        }
        return nil
    }

    private static func usage() -> String {
        """
        writingcoach --root <libraryRoot> <command> [options]

        commands:
          init
          new --title <title?>
          list [--query <q>]
          import-wechat-html --file <path>
          analyze --id <docId>
        """
    }
}

do {
    try CLI.run()
} catch {
    let data = Data("error: \(error)\n".utf8)
    try? FileHandle.standardError.write(contentsOf: data)
    exit(1)
}
