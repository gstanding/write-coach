import XCTest
@testable import WritingCoachCore

final class ImporterTests: XCTestCase {
    func testWeChatHTMLImportCreatesMarkdownAndAssets() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("writingcoach-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let layout = LibraryLayout(root: tmp)
        try LibraryBootstrapper.ensureInitialized(layout: layout)
        let fileStore = DocumentFileStoreImpl(layout: layout)
        let indexStore = try DocumentIndexStoreImpl(dbURL: layout.indexDB)
        let assetStore = AssetStoreImpl(layout: layout)

        let imgPath = tmp.appendingPathComponent("cover.png", isDirectory: false)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imgPath)

        let html = """
        <html><body>
        <h2>标题</h2>
        <p>第一段。</p>
        <img src="cover.png" alt="封面" />
        </body></html>
        """
        let htmlFile = tmp.appendingPathComponent("a.html", isDirectory: false)
        try html.data(using: .utf8)!.write(to: htmlFile)

        let importer = WeChatHTMLImporterImpl(layout: layout, fileStore: fileStore, indexStore: indexStore, assetStore: assetStore)
        let result = try importer.import(htmlFile: htmlFile, voiceProfileId: nil)
        XCTAssertFalse(result.documentId.isEmpty)
        XCTAssertTrue(result.markdown.contains("#"))
        XCTAssertTrue(result.markdown.contains("第一段"))
        XCTAssertEqual(result.assetCount, 1)

        let docURL = layout.docPath(id: result.documentId)
        let saved = String(decoding: try Data(contentsOf: docURL), as: UTF8.self)
        XCTAssertTrue(saved.contains("source: \"wechat_html\""))
        XCTAssertTrue(saved.contains("![]") || saved.contains("![封面]"))
    }
}

