import XCTest
@testable import NativeScanner

final class CaptureConfigurationTests: XCTestCase {
    func testRecentBestBufferKeepsOnlyNewestCandidatesAndSelectsHighestScore() {
        var buffer = RecentBestBuffer<String>(capacity: 3)
        buffer.append("old-best", score: 100)
        buffer.append("new-low", score: 10)
        buffer.append("new-best", score: 30)
        buffer.append("new-mid", score: 20)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.best, "new-best")
    }

    func testScanFileNamesShareTimestampAndUseExpectedVariants() {
        let names = scanFileNames(timestamp: "20261009_101112_123456")

        XCTAssertEqual(names[.original], "scan_20261009_101112_123456_original.png")
        XCTAssertEqual(names[.color], "scan_20261009_101112_123456_color.png")
        XCTAssertEqual(names[.gray], "scan_20261009_101112_123456_gray.png")
    }
}
