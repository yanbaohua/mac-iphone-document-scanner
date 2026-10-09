import AppKit
import XCTest
@testable import NativeScanner

final class OCRProcessorTests: XCTestCase {
    func testPreferredLanguagesKeepOnlySupportedLanguagesInPreferredOrder() throws {
        XCTAssertEqual(
            try preferredOCRLanguages(supported: ["en-US", "fr-FR", "zh-Hans"]),
            ["zh-Hans", "en-US"]
        )
        XCTAssertThrowsError(try preferredOCRLanguages(supported: ["fr-FR"]))
    }

    func testVisionBoundingBoxConvertsToTopLeftPixelCoordinates() {
        let box = pixelBoundingBox(
            from: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40),
            imageWidth: 1_000,
            imageHeight: 500
        )

        XCTAssertEqual(box.x, 100, accuracy: 0.001)
        XCTAssertEqual(box.y, 200, accuracy: 0.001)
        XCTAssertEqual(box.width, 300, accuracy: 0.001)
        XCTAssertEqual(box.height, 200, accuracy: 0.001)
    }

    func testExportSortsTextAndKeepsTXTConsistentWithJSON() throws {
        let export = try makeOCRExport(
            sourceImage: "scan_20261009_101112_123456_original.png",
            imageWidth: 1_000,
            imageHeight: 500,
            languages: ["zh-Hans", "en-US"],
            candidates: [
                OCRCandidate(
                    text: "右侧",
                    confidence: 0.80,
                    boundingBox: CGRect(x: 0.60, y: 0.60, width: 0.20, height: 0.10)
                ),
                OCRCandidate(
                    text: "下一行",
                    confidence: 0.70,
                    boundingBox: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.10)
                ),
                OCRCandidate(
                    text: "左侧",
                    confidence: 0.90,
                    boundingBox: CGRect(x: 0.10, y: 0.60, width: 0.20, height: 0.10)
                ),
            ]
        )

        XCTAssertEqual(String(data: export.textData, encoding: .utf8), "左侧\n右侧\n下一行\n")
        let decoded = try JSONDecoder().decode(OCRDocument.self, from: export.jsonData)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.coordinateSystem, "pixel-top-left")
        XCTAssertEqual(decoded.plainText, "左侧\n右侧\n下一行\n")
        XCTAssertEqual(decoded.observations.map(\.text), ["左侧", "右侧", "下一行"])
        XCTAssertEqual(decoded.observations.map(\.index), [0, 1, 2])
    }

    func testEmptyCandidatesProduceEmptyTXTAndValidJSON() throws {
        let export = try makeOCRExport(
            sourceImage: "scan_original.png",
            imageWidth: 800,
            imageHeight: 600,
            languages: ["zh-Hans", "en-US"],
            candidates: []
        )

        XCTAssertTrue(export.textData.isEmpty)
        let decoded = try JSONDecoder().decode(OCRDocument.self, from: export.jsonData)
        XCTAssertEqual(decoded.plainText, "")
        XCTAssertTrue(decoded.observations.isEmpty)
    }

    func testVisionRecognizesSyntheticEnglishText() throws {
        let pngData = try makeTextPNG("TEST 123")

        let export = try OCRProcessor().recognize(
            pngData: pngData,
            sourceImage: "synthetic_original.png"
        )

        XCTAssertFalse(export.document.observations.isEmpty)
    }

    private func makeTextPNG(_ text: String) throws -> Data {
        let image = NSImage(size: NSSize(width: 600, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        (text as NSString).draw(
            at: NSPoint(x: 40, y: 50),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SyntheticImageError.encodingFailed
        }
        return png
    }
}

private enum SyntheticImageError: Error {
    case encodingFailed
}
