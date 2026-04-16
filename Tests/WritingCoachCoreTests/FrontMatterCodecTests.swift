import XCTest
@testable import WritingCoachCore

final class FrontMatterCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 123)
        let fm = FrontMatter(
            id: "01TESTULID000000000000000000",
            title: "标题",
            createdAt: now,
            updatedAt: now,
            source: "wechat_html",
            voiceProfileId: "vp_default",
            tags: ["A", "B"]
        )
        let doc = DocumentContent(frontMatter: fm, body: "正文\n第二行")
        let encoded = FrontMatterCodec.encodeDocument(doc)
        let decoded = try FrontMatterCodec.decodeDocument(encoded)
        XCTAssertEqual(decoded.frontMatter?.id, fm.id)
        XCTAssertEqual(decoded.frontMatter?.title, fm.title)
        XCTAssertEqual(decoded.frontMatter?.tags.sorted(), fm.tags.sorted())
        XCTAssertEqual(decoded.body.trimmingCharacters(in: .newlines), doc.body)
    }
}

