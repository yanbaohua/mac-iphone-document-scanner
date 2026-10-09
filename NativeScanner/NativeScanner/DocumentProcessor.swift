import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct DocumentQuadrilateral: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
}

enum DocumentVariant: String, CaseIterable {
    case original
    case color
    case gray
}

func scanFileNames(timestamp: String) -> [DocumentVariant: String] {
    Dictionary(uniqueKeysWithValues: DocumentVariant.allCases.map { variant in
        (variant, "scan_\(timestamp)_\(variant.rawValue).png")
    })
}

struct ProcessedDocument {
    let width: Int
    let height: Int
    let pngData: [DocumentVariant: Data]
}

final class DocumentProcessor: @unchecked Sendable {
    private let context = CIContext()

    func detectQuadrilateral(in image: CGImage) throws -> DocumentQuadrilateral? {
        let documentRequest = VNDetectDocumentSegmentationRequest()
        let documentHandler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try documentHandler.perform([documentRequest])
        if let observation = documentRequest.results?.first {
            let quadrilateral = Self.quadrilateral(from: observation)
            if isUsableDocumentQuadrilateral(quadrilateral) {
                return quadrilateral
            }
        }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 3
        request.minimumConfidence = 0.40
        request.minimumAspectRatio = 0.25
        request.minimumSize = 0.15
        request.quadratureTolerance = 35

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        return request.results?
            .map(Self.quadrilateral)
            .first(where: isUsableDocumentQuadrilateral)
    }

    private static func quadrilateral(from observation: VNRectangleObservation) -> DocumentQuadrilateral {
        DocumentQuadrilateral(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
        )
    }

    func process(
        image: CGImage,
        quadrilateral: DocumentQuadrilateral
    ) throws -> ProcessedDocument {
        let outputSize = documentOutputSize(
            for: quadrilateral,
            imageWidth: image.width,
            imageHeight: image.height
        )
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        guard width > 1, height > 1 else {
            throw DocumentProcessingError.invalidDocumentSize
        }

        let input = CIImage(cgImage: image)
        let corrected = try perspectiveCorrect(
            input,
            quadrilateral: quadrilateral,
            imageWidth: image.width,
            imageHeight: image.height
        )
        let normalized = corrected.transformed(
            by: CGAffineTransform(
                translationX: -corrected.extent.minX,
                y: -corrected.extent.minY
            )
        )
        let target = CGRect(x: 0, y: 0, width: width, height: height)

        let original = normalized.cropped(to: target)
        let color = try applyFilters(
            to: original,
            steps: [
                ("CIHighlightShadowAdjust", ["inputShadowAmount": 0.20, "inputHighlightAmount": 0.90]),
                ("CIColorControls", [kCIInputSaturationKey: 1.0, kCIInputContrastKey: 1.08, kCIInputBrightnessKey: 0.01]),
                ("CISharpenLuminance", [kCIInputSharpnessKey: 0.35]),
            ]
        )
        let gray = try applyFilters(
            to: original,
            steps: [
                ("CIColorControls", [kCIInputSaturationKey: 0.0, kCIInputContrastKey: 1.15, kCIInputBrightnessKey: 0.02]),
                ("CISharpenLuminance", [kCIInputSharpnessKey: 0.40]),
            ]
        )

        return ProcessedDocument(
            width: width,
            height: height,
            pngData: [
                .original: try pngData(for: original, bounds: target),
                .color: try pngData(for: color, bounds: target),
                .gray: try pngData(for: gray, bounds: target),
            ]
        )
    }

    private func perspectiveCorrect(
        _ image: CIImage,
        quadrilateral: DocumentQuadrilateral,
        imageWidth: Int,
        imageHeight: Int
    ) throws -> CIImage {
        func vector(_ point: CGPoint) -> CIVector {
            CIVector(
                x: point.x * CGFloat(imageWidth),
                y: point.y * CGFloat(imageHeight)
            )
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw DocumentProcessingError.filterUnavailable("CIPerspectiveCorrection")
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(vector(quadrilateral.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(quadrilateral.topRight), forKey: "inputTopRight")
        filter.setValue(vector(quadrilateral.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vector(quadrilateral.bottomLeft), forKey: "inputBottomLeft")
        guard let output = filter.outputImage else {
            throw DocumentProcessingError.filterFailed("CIPerspectiveCorrection")
        }
        return output
    }

    private func applyFilters(
        to input: CIImage,
        steps: [(name: String, parameters: [String: Any])]
    ) throws -> CIImage {
        try steps.reduce(input) { image, step in
            guard let filter = CIFilter(name: step.name) else {
                throw DocumentProcessingError.filterUnavailable(step.name)
            }
            filter.setValue(image, forKey: kCIInputImageKey)
            step.parameters.forEach { filter.setValue($0.value, forKey: $0.key) }
            guard let output = filter.outputImage else {
                throw DocumentProcessingError.filterFailed(step.name)
            }
            return output
        }
    }

    private func pngData(for image: CIImage, bounds: CGRect) throws -> Data {
        guard let rendered = context.createCGImage(image, from: bounds) else {
            throw DocumentProcessingError.renderFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DocumentProcessingError.pngDestinationFailed
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DocumentProcessingError.pngEncodingFailed
        }
        return data as Data
    }
}

func isUsableDocumentQuadrilateral(_ quadrilateral: DocumentQuadrilateral) -> Bool {
    let points = [
        quadrilateral.topLeft,
        quadrilateral.topRight,
        quadrilateral.bottomRight,
        quadrilateral.bottomLeft,
    ]
    var twiceArea = CGFloat.zero
    for index in points.indices {
        let next = points[(index + 1) % points.count]
        twiceArea += points[index].x * next.y - next.x * points[index].y
    }
    // shortcut: 文档需占画面至少 20%，若要支持远距离小票再联合边缘质量判定。
    return abs(twiceArea) / 2 >= 0.20
}

enum DocumentProcessingError: LocalizedError {
    case invalidDocumentSize
    case filterUnavailable(String)
    case filterFailed(String)
    case renderFailed
    case pngDestinationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidDocumentSize:
            return "检测到的文档区域尺寸无效。"
        case .filterUnavailable(let name):
            return "系统图像滤镜不可用：\(name)。"
        case .filterFailed(let name):
            return "系统图像滤镜处理失败：\(name)。"
        case .renderFailed:
            return "无法渲染校正后的文档图像。"
        case .pngDestinationFailed:
            return "无法创建 PNG 编码目标。"
        case .pngEncodingFailed:
            return "PNG 编码失败。"
        }
    }
}

func sharpnessScore(
    lumaPixels: [UInt8],
    width: Int,
    height: Int,
    bytesPerRow: Int
) -> Double {
    guard width > 1, height > 1, bytesPerRow >= width,
          lumaPixels.count >= bytesPerRow * height else {
        return 0
    }

    var differenceTotal = 0
    var comparisonCount = 0
    for y in 0..<height {
        let row = y * bytesPerRow
        for x in 0..<width {
            let value = Int(lumaPixels[row + x])
            if x + 1 < width {
                differenceTotal += abs(value - Int(lumaPixels[row + x + 1]))
                comparisonCount += 1
            }
            if y + 1 < height {
                differenceTotal += abs(value - Int(lumaPixels[row + bytesPerRow + x]))
                comparisonCount += 1
            }
        }
    }

    guard comparisonCount > 0 else { return 0 }
    return Double(differenceTotal) / Double(comparisonCount)
}

func documentOutputSize(
    for quadrilateral: DocumentQuadrilateral,
    imageWidth: Int,
    imageHeight: Int
) -> CGSize {
    guard imageWidth > 0, imageHeight > 0 else { return .zero }

    func pixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1) * CGFloat(imageWidth),
            y: min(max(point.y, 0), 1) * CGFloat(imageHeight)
        )
    }

    func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    let topLeft = pixelPoint(quadrilateral.topLeft)
    let topRight = pixelPoint(quadrilateral.topRight)
    let bottomRight = pixelPoint(quadrilateral.bottomRight)
    let bottomLeft = pixelPoint(quadrilateral.bottomLeft)

    let width = min(
        CGFloat(imageWidth),
        max(distance(topLeft, topRight), distance(bottomLeft, bottomRight)).rounded()
    )
    let height = min(
        CGFloat(imageHeight),
        max(distance(topLeft, bottomLeft), distance(topRight, bottomRight)).rounded()
    )
    return CGSize(width: max(width, 1), height: max(height, 1))
}
