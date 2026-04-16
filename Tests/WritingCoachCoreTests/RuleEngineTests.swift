import XCTest
@testable import WritingCoachCore

final class RuleEngineTests: XCTestCase {
    func testFillerWordRuleProducesSuggestion() {
        let body = "值得注意的是，这里有套话。此外，我们再加一点。\n\n我认为结论是这样。"
        let ctx = Analyzer.analyze(documentId: "doc", body: body, lexicon: .default, voice: nil)
        let suggestions = RuleEngine.default().run(ctx: ctx)
        XCTAssertTrue(suggestions.contains(where: { $0.ruleId == "STYLE.FILLER_WORDS" }))
        XCTAssertTrue(suggestions.contains(where: { $0.ruleId == "STRUCT.MISSING_EVIDENCE_HINT" }))
    }
}

