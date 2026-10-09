import CoreGraphics
import Foundation
import ImageIO
import Vision

struct OCRBoundingBox: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct OCRObservation: Codable, Equatable {
    let index: Int
    let text: String
    let confidence: Float
    let boundingBox: OCRBoundingBox
}

struct OCRDocument: Codable, Equatable {
    let schemaVersion: Int
    let sourceImage: String
    let imageWidth: Int
    let imageHeight: Int
    let coordinateSystem: String
    let recognitionLanguages: [String]
    let plainText: String
    let observations: [OCRObservation]
}

struct OCRExport {
    let document: OCRDocument
    let textData: Data
    let jsonData: Data
}

struct OCRFileNames {
    let text: String
    let json: String
}

struct OCRCandidate {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

func ocrFileNames(timestamp: String) -> OCRFileNames {
    OCRFileNames(
        text: "scan_\(timestamp)_ocr.txt",
        json: "scan_\(timestamp)_ocr.json"
    )
}

@discardableResult
func writeOCRFileGroup(
    _ export: OCRExport,
    timestamp: String,
    to directory: URL
) throws -> [URL] {
    let names = ocrFileNames(timestamp: timestamp)
    let files = [
        (name: names.text, data: export.textData),
        (name: names.json, data: export.jsonData),
    ]
    var writtenURLs: [URL] = []
    do {
        for file in files {
            let destination = directory.appendingPathComponent(file.name)
            try writeAtomicallyWithoutOverwriting(file.data, to: destination)
            writtenURLs.append(destination)
        }
        return writtenURLs
    } catch {
        for url in writtenURLs {
            try? FileManager.default.removeItem(at: url)
        }
        throw error
    }
}

func preferredOCRLanguages(supported: [String]) throws -> [String] {
    let supportedSet = Set(supported)
    let languages = ["zh-Hans", "en-US"].filter(supportedSet.contains)
    guard !languages.isEmpty else {
        throw OCRProcessingError.noSupportedLanguages
    }
    return languages
}

func pixelBoundingBox(
    from normalizedBox: CGRect,
    imageWidth: Int,
    imageHeight: Int
) -> OCRBoundingBox {
    OCRBoundingBox(
        x: normalizedBox.minX * Double(imageWidth),
        y: (1 - normalizedBox.maxY) * Double(imageHeight),
        width: normalizedBox.width * Double(imageWidth),
        height: normalizedBox.height * Double(imageHeight)
    )
}

func makeOCRExport(
    sourceImage: String,
    imageWidth: Int,
    imageHeight: Int,
    languages: [String],
    candidates: [OCRCandidate]
) throws -> OCRExport {
    guard imageWidth > 0, imageHeight > 0 else {
        throw OCRProcessingError.invalidImage
    }

    let positioned = candidates.map { candidate in
        (
            candidate: candidate,
            box: pixelBoundingBox(
                from: candidate.boundingBox,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        )
    }
    let sorted = positioned.sorted { left, right in
        if left.box.y != right.box.y {
            return left.box.y < right.box.y
        }
        return left.box.x < right.box.x
    }
    let observations = sorted.enumerated().map { index, item in
        OCRObservation(
            index: index,
            text: item.candidate.text,
            confidence: item.candidate.confidence,
            boundingBox: item.box
        )
    }
    let plainText = observations.isEmpty
        ? ""
        : observations.map(\.text).joined(separator: "\n") + "\n"
    let document = OCRDocument(
        schemaVersion: 1,
        sourceImage: sourceImage,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        coordinateSystem: "pixel-top-left",
        recognitionLanguages: languages,
        plainText: plainText,
        observations: observations
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return OCRExport(
        document: document,
        textData: Data(plainText.utf8),
        jsonData: try encoder.encode(document)
    )
}

final class OCRProcessor {
    func recognize(pngData: Data, sourceImage: String) throws -> OCRExport {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRProcessingError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            let languages = try preferredOCRLanguages(
                supported: request.supportedRecognitionLanguages()
            )
            request.recognitionLanguages = languages
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([request])
            let candidates = (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { recognized in
                    OCRCandidate(
                        text: recognized.string,
                        confidence: recognized.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
            }
            return try makeOCRExport(
                sourceImage: sourceImage,
                imageWidth: image.width,
                imageHeight: image.height,
                languages: languages,
                candidates: candidates
            )
        } catch let error as OCRProcessingError {
            throw error
        } catch {
            throw OCRProcessingError.recognitionFailed(error.localizedDescription)
        }
    }
}

enum OCRProcessingError: LocalizedError {
    case invalidImage
    case noSupportedLanguages
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取用于文字识别的原始矫正图。"
        case .noSupportedLanguages:
            return "当前系统不支持简体中文或英文文字识别。"
        case .recognitionFailed(let detail):
            return "本地文字识别失败：\(detail)"
        }
    }
}
