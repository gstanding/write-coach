import XCTest
@testable import WritingCoachCore

final class ULIDTests: XCTestCase {
    func testULIDLexicographicOrderingTracksTime() {
        let a = ULID.generate(now: Date(timeIntervalSince1970: 1))
        let b = ULID.generate(now: Date(timeIntervalSince1970: 2))
        XCTAssertLessThan(a, b)
        XCTAssertEqual(a.count, 26)
        XCTAssertEqual(b.count, 26)
    }
}

