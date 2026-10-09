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

    func testOCRFileNamesShareScanTimestamp() {
        let names = ocrFileNames(timestamp: "20261009_101112_123456")

        XCTAssertEqual(names.text, "scan_20261009_101112_123456_ocr.txt")
        XCTAssertEqual(names.json, "scan_20261009_101112_123456_ocr.json")
    }

    func testOCRFileGroupWritesTextAndJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let timestamp = "20261009_101112_123456"
        let names = ocrFileNames(timestamp: timestamp)
        let export = try makeOCRExport(
            sourceImage: "scan_\(timestamp)_original.png",
            imageWidth: 800,
            imageHeight: 600,
            languages: ["zh-Hans", "en-US"],
            candidates: []
        )

        let written = try writeOCRFileGroup(export, timestamp: timestamp, to: directory)

        XCTAssertEqual(Set(written.map(\.lastPathComponent)), Set([names.text, names.json]))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(names.text)), export.textData)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(names.json)), export.jsonData)
    }

    func testOCRWriteFailureCleansNewOCRFilesAndPreservesImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let timestamp = "20261009_101112_123456"
        let imageURL = directory.appendingPathComponent("scan_\(timestamp)_original.png")
        let names = ocrFileNames(timestamp: timestamp)
        let textURL = directory.appendingPathComponent(names.text)
        let jsonURL = directory.appendingPathComponent(names.json)
        try Data("image".utf8).write(to: imageURL)
        try Data("existing-json".utf8).write(to: jsonURL)
        let export = try makeOCRExport(
            sourceImage: imageURL.lastPathComponent,
            imageWidth: 800,
            imageHeight: 600,
            languages: ["zh-Hans", "en-US"],
            candidates: []
        )

        XCTAssertThrowsError(
            try writeOCRFileGroup(export, timestamp: timestamp, to: directory)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: textURL.path))
        XCTAssertEqual(try Data(contentsOf: jsonURL), Data("existing-json".utf8))
        XCTAssertEqual(try Data(contentsOf: imageURL), Data("image".utf8))
    }
}
