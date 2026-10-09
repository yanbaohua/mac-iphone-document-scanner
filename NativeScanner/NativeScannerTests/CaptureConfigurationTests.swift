import XCTest
@testable import NativeScanner

final class CaptureConfigurationTests: XCTestCase {
    func testAtomicWritePreservesExistingDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("scan.png")

        try writeAtomicallyWithoutOverwriting(Data("first".utf8), to: destination)

        XCTAssertThrowsError(
            try writeAtomicallyWithoutOverwriting(Data("second".utf8), to: destination)
        )
        XCTAssertEqual(try Data(contentsOf: destination), Data("first".utf8))
    }

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
