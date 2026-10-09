import AVFoundation
import XCTest
@testable import NativeScanner

final class CaptureConfigurationTests: XCTestCase {
    func testLargestPhotoDimensionReturnsNilForEmptyInput() {
        XCTAssertNil(largestPhotoDimension(in: []))
    }

    func testLargestPhotoDimensionReturnsOnlyDimension() {
        let dimension = CMVideoDimensions(width: 4032, height: 3024)

        assertDimension(largestPhotoDimension(in: [dimension]), equals: dimension)
    }

    func testLargestPhotoDimensionChoosesGreatestPixelCount() {
        let dimensions = [
            CMVideoDimensions(width: 1920, height: 1440),
            CMVideoDimensions(width: 4032, height: 3024),
            CMVideoDimensions(width: 3840, height: 2160),
        ]

        assertDimension(
            largestPhotoDimension(in: dimensions),
            equals: CMVideoDimensions(width: 4032, height: 3024)
        )
    }

    func testLargestPhotoDimensionUsesStableTieBreakers() {
        let dimensions = [
            CMVideoDimensions(width: 3000, height: 4000),
            CMVideoDimensions(width: 6000, height: 2000),
            CMVideoDimensions(width: 2000, height: 6000),
        ]

        assertDimension(
            largestPhotoDimension(in: dimensions),
            equals: CMVideoDimensions(width: 6000, height: 2000)
        )
    }

    func testCaptureDimensionAcceptsOutputMaximumSupportedByActiveFormat() {
        let outputMaximum = CMVideoDimensions(width: 1920, height: 1440)

        assertDimension(
            captureDimension(
                supportedByActiveFormat: [
                    CMVideoDimensions(width: 1920, height: 1080),
                    outputMaximum,
                ],
                outputMaximum: outputMaximum
            ),
            equals: outputMaximum
        )
    }

    func testCaptureDimensionRejectsStaleOutputMaximum() {
        XCTAssertNil(
            captureDimension(
                supportedByActiveFormat: [CMVideoDimensions(width: 1920, height: 1080)],
                outputMaximum: CMVideoDimensions(width: 1920, height: 1440)
            )
        )
    }

    func testPreferredPhotoQualityDoesNotExceedOutputMaximum() {
        XCTAssertEqual(
            clampedPhotoQuality(.quality, maximumSupported: .balanced),
            .balanced
        )
        XCTAssertEqual(
            clampedPhotoQuality(.quality, maximumSupported: .quality),
            .quality
        )
    }

    private func assertDimension(
        _ actual: CMVideoDimensions?,
        equals expected: CMVideoDimensions,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual?.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual?.height, expected.height, file: file, line: line)
    }
}
