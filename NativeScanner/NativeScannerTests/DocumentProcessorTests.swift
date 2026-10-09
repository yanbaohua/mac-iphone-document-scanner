import CoreGraphics
import ImageIO
import XCTest
@testable import NativeScanner

final class DocumentProcessorTests: XCTestCase {
    func testSharpnessScoreIsZeroForUniformPixels() {
        let pixels = [UInt8](repeating: 128, count: 16)

        XCTAssertEqual(
            sharpnessScore(lumaPixels: pixels, width: 4, height: 4, bytesPerRow: 4),
            0
        )
    }

    func testSharpnessScoreRewardsVisibleEdges() {
        let pixels: [UInt8] = [
            0, 0, 255, 255,
            0, 0, 255, 255,
            255, 255, 0, 0,
            255, 255, 0, 0,
        ]

        XCTAssertGreaterThan(
            sharpnessScore(lumaPixels: pixels, width: 4, height: 4, bytesPerRow: 4),
            0
        )
    }

    func testSharpnessScoreRejectsInvalidBufferShape() {
        XCTAssertEqual(
            sharpnessScore(lumaPixels: [0, 255], width: 4, height: 4, bytesPerRow: 4),
            0
        )
    }

    func testDocumentOutputSizeUsesLongestOpposingEdgesWithoutUpscaling() {
        let quadrilateral = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.10, y: 0.90),
            topRight: CGPoint(x: 0.90, y: 0.90),
            bottomRight: CGPoint(x: 0.90, y: 0.10),
            bottomLeft: CGPoint(x: 0.10, y: 0.10)
        )

        let size = documentOutputSize(
            for: quadrilateral,
            imageWidth: 1_000,
            imageHeight: 800
        )

        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 640)
        XCTAssertLessThanOrEqual(size.width, 1_000)
        XCTAssertLessThanOrEqual(size.height, 800)
    }

    func testProcessingProducesThreeDecodablePNGsAtNaturalSize() throws {
        let image = try makeTestImage(width: 100, height: 80)
        let quadrilateral = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.10, y: 0.90),
            topRight: CGPoint(x: 0.90, y: 0.90),
            bottomRight: CGPoint(x: 0.90, y: 0.10),
            bottomLeft: CGPoint(x: 0.10, y: 0.10)
        )

        let result = try DocumentProcessor().process(
            image: image,
            quadrilateral: quadrilateral
        )

        XCTAssertEqual(result.width, 80)
        XCTAssertEqual(result.height, 64)
        XCTAssertEqual(Set(result.pngData.keys), Set(DocumentVariant.allCases))
        for data in result.pngData.values {
            let source = CGImageSourceCreateWithData(data as CFData, nil)
            let decoded = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            XCTAssertEqual(decoded?.width, 80)
            XCTAssertEqual(decoded?.height, 64)
        }
    }

    func testDetectQuadrilateralFindsHighContrastDocument() throws {
        let image = try makeDocumentImage(width: 400, height: 300)

        let quadrilateral = try DocumentProcessor().detectQuadrilateral(in: image)

        XCTAssertNotNil(quadrilateral)
    }

    func testDocumentCandidateRejectsSmallRectangularObjects() {
        let smallObject = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.10, y: 0.30),
            topRight: CGPoint(x: 0.30, y: 0.30),
            bottomRight: CGPoint(x: 0.30, y: 0.10),
            bottomLeft: CGPoint(x: 0.10, y: 0.10)
        )

        XCTAssertFalse(isUsableDocumentQuadrilateral(smallObject))
    }

    func testDocumentCandidateAcceptsPageFillingFrame() {
        let page = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.10, y: 0.90),
            topRight: CGPoint(x: 0.90, y: 0.90),
            bottomRight: CGPoint(x: 0.90, y: 0.10),
            bottomLeft: CGPoint(x: 0.10, y: 0.10)
        )

        XCTAssertTrue(isUsableDocumentQuadrilateral(page))
    }

    func testFullHDDocumentDetectionCompletesWithinPreviewBudget() throws {
        let image = try makeDocumentImage(width: 1_920, height: 1_080)
        let start = CFAbsoluteTimeGetCurrent()

        let quadrilateral = try DocumentProcessor().detectQuadrilateral(in: image)

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertNotNil(quadrilateral)
        XCTAssertLessThan(elapsed, 0.50, "1080p 文档检测耗时 \(elapsed) 秒")
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 10, y: 8, width: 80, height: 64))
        guard let image = context.makeImage() else {
            throw TestImageError.imageCreationFailed
        }
        return image
    }

    private func makeDocumentImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }
        context.setFillColor(CGColor(gray: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(
            CGRect(
                x: CGFloat(width) * 0.125,
                y: CGFloat(height) * 0.133,
                width: CGFloat(width) * 0.75,
                height: CGFloat(height) * 0.733
            )
        )
        guard let image = context.makeImage() else {
            throw TestImageError.imageCreationFailed
        }
        return image
    }
}

private enum TestImageError: Error {
    case contextCreationFailed
    case imageCreationFailed
}
