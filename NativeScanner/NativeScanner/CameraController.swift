import AVFoundation
import Combine
import CoreImage
import Foundation

struct RecentBestBuffer<Value> {
    private let capacity: Int
    private var items: [(value: Value, score: Double)] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { items.count }

    var best: Value? {
        var selection: (value: Value, score: Double)?
        for item in items {
            if selection.map({ item.score >= $0.score }) ?? true {
                selection = item
            }
        }
        return selection?.value
    }

    mutating func append(_ value: Value, score: Double) {
        items.append((value, score))
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
    }
}

func writeAtomicallyWithoutOverwriting(_ data: Data, to destination: URL) throws {
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
        ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
    )
    do {
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.moveItem(at: temporary, to: destination)
    } catch {
        try? FileManager.default.removeItem(at: temporary)
        throw error
    }
}

final class CameraController: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var statusMessage = "尚未连接 iPhone 连续互通相机。"
    @Published private(set) var isReady = false
    @Published private(set) var isProcessing = false
    @Published private(set) var hasDocumentCandidate = false
    @Published private(set) var documentQuadrilateral: DocumentQuadrilateral?
    @Published private(set) var previewSize = "—"

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.yanbaohua.NativeScanner.capture-session")
    private let analysisQueue = DispatchQueue(label: "com.yanbaohua.NativeScanner.analysis")
    private let processingQueue = DispatchQueue(label: "com.yanbaohua.NativeScanner.processing", qos: .userInitiated)
    private let frameContext = CIContext()
    private let processor = DocumentProcessor()
    private let ocrProcessor = OCRProcessor()
    private var candidates = RecentBestBuffer<FrameCandidate>(capacity: 8)
    private var lastAnalysisTime = 0.0
    private var lastDetectionTime = 0.0
    private var smoothedQuadrilateral: DocumentQuadrilateral?
    private var captureDevice: AVCaptureDevice?
    private var isConfigured = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureDeviceDisconnected(_:)),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        publish(status: "正在检查相机权限…", ready: false)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureSession()
                } else {
                    self?.publishFailure(ScannerError.permissionDenied)
                }
            }
        case .denied, .restricted:
            publishFailure(ScannerError.permissionDenied)
        @unknown default:
            publishFailure(ScannerError.permissionUnavailable)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    func scan(to directory: URL) {
        guard !isProcessing else {
            publishFailure(ScannerError.processingInProgress)
            return
        }
        publish(status: "正在选择最清晰画面、透视裁边、增强并识别文字…", processing: true)

        analysisQueue.async { [weak self] in
            guard let self else { return }
            guard let candidate = self.candidates.best else {
                self.publishFailure(ScannerError.noDocumentCandidate)
                return
            }
            self.processingQueue.async { [weak self] in
                self?.process(candidate, to: directory)
            }
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isConfigured {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                self.publish(status: "iPhone 相机已连接，请将文档放入绿色框。", ready: true)
                return
            }

            do {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.continuityCamera],
                    mediaType: .video,
                    position: .unspecified
                )
                guard let device = discovery.devices.first else {
                    throw ScannerError.noContinuityCamera
                }
                self.captureDevice = device

                self.captureSession.beginConfiguration()
                do {
                    if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                        self.captureSession.sessionPreset = .hd1920x1080
                    } else {
                        self.captureSession.sessionPreset = .high
                    }

                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.captureSession.canAddInput(input) else {
                        throw ScannerError.cannotAddCameraInput
                    }
                    self.captureSession.addInput(input)

                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String:
                            Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                    ]
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                    guard self.captureSession.canAddOutput(self.videoOutput) else {
                        throw ScannerError.cannotAddVideoOutput
                    }
                    self.captureSession.addOutput(self.videoOutput)
                    self.captureSession.commitConfiguration()
                } catch {
                    self.captureSession.commitConfiguration()
                    throw error
                }

                self.captureSession.startRunning()
                let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                self.isConfigured = true
                self.publish(
                    status: "iPhone 相机已连接，请将文档放入绿色框。",
                    ready: true,
                    previewSize: "\(dimensions.width)×\(dimensions.height)"
                )
            } catch {
                self.publishFailure(error)
            }
        }
    }

    private func process(_ candidate: FrameCandidate, to directory: URL) {
        let didAccessSecurityScope = directory.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        var writtenURLs: [URL] = []
        do {
            let document = try processor.process(
                image: candidate.image,
                quadrilateral: candidate.quadrilateral
            )
            let timestamp = Self.timestamp()
            let names = scanFileNames(timestamp: timestamp)

            for variant in DocumentVariant.allCases {
                guard let name = names[variant], let data = document.pngData[variant] else {
                    throw ScannerError.missingProcessedVariant(variant.rawValue)
                }
                let destination = directory.appendingPathComponent(name)
                try writeAtomicallyWithoutOverwriting(data, to: destination)
                writtenURLs.append(destination)
            }

            do {
                guard let originalName = names[.original],
                      let originalData = document.pngData[.original] else {
                    throw ScannerError.missingProcessedVariant(DocumentVariant.original.rawValue)
                }
                let export = try ocrProcessor.recognize(
                    pngData: originalData,
                    sourceImage: originalName
                )
                try writeOCRFileGroup(export, timestamp: timestamp, to: directory)
                let ocrStatus = export.document.observations.isEmpty
                    ? "未识别到文字"
                    : "OCR 识别 \(export.document.observations.count) 条"
                publish(
                    status: "扫描完成：源帧 \(candidate.image.width)×\(candidate.image.height)，裁边后 \(document.width)×\(document.height)，\(ocrStatus)，已保存到 \(directory.path)",
                    processing: false
                )
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                publish(
                    status: "图像已保存：源帧 \(candidate.image.width)×\(candidate.image.height)，裁边后 \(document.width)×\(document.height)，但 OCR 失败：\(message)",
                    processing: false
                )
            }
        } catch {
            for url in writtenURLs {
                try? FileManager.default.removeItem(at: url)
            }
            publishFailure(error)
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
        analysisQueue.async { [weak self] in self?.clearDocumentCandidate() }
        publishFailure(ScannerError.sessionFailed(detail ?? "未知错误"), ready: false)
    }

    @objc private func captureDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device === captureDevice else { return }
        analysisQueue.async { [weak self] in self?.clearDocumentCandidate() }
        publishFailure(ScannerError.deviceDisconnected, ready: false)
    }

    private func publish(
        status: String? = nil,
        ready: Bool? = nil,
        processing: Bool? = nil,
        hasCandidate: Bool? = nil,
        quadrilateral: DocumentQuadrilateral?? = nil,
        previewSize: String? = nil
    ) {
        let update = { [weak self] in
            guard let self else { return }
            if let status { self.statusMessage = status }
            if let ready { self.isReady = ready }
            if let processing { self.isProcessing = processing }
            if let hasCandidate { self.hasDocumentCandidate = hasCandidate }
            if let quadrilateral { self.documentQuadrilateral = quadrilateral }
            if let previewSize { self.previewSize = previewSize }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func publishFailure(_ error: any Error, ready: Bool? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        publish(status: "错误：\(message)", ready: ready, processing: false)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSSSSS"
        return formatter.string(from: Date())
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard presentationTime.isFinite,
              presentationTime - lastAnalysisTime >= 0.20,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lastAnalysisTime = presentationTime

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = frameContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        do {
            if let detected = try processor.detectQuadrilateral(in: image) {
                let smoothed = smooth(previous: smoothedQuadrilateral, current: detected)
                smoothedQuadrilateral = smoothed
                lastDetectionTime = presentationTime
                candidates.append(
                    FrameCandidate(image: image, quadrilateral: detected),
                    score: sharpnessScore(of: pixelBuffer)
                )
                publish(
                    hasCandidate: true,
                    quadrilateral: .some(smoothed)
                )
            } else if presentationTime - lastDetectionTime > 0.50 {
                clearDocumentCandidate()
            }
        } catch {
            if presentationTime - lastDetectionTime > 0.50 {
                clearDocumentCandidate()
            }
        }
    }

    private func clearDocumentCandidate() {
        smoothedQuadrilateral = nil
        candidates = RecentBestBuffer(capacity: 8)
        publish(hasCandidate: false, quadrilateral: .some(nil))
    }

    private func sharpnessScore(of pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
              let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return 0
        }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let step = 4
        var total = 0
        var count = 0

        for y in stride(from: 0, to: height - step, by: step) {
            for x in stride(from: 0, to: width - step, by: step) {
                let value = Int(pixels[y * bytesPerRow + x])
                total += abs(value - Int(pixels[y * bytesPerRow + x + step]))
                total += abs(value - Int(pixels[(y + step) * bytesPerRow + x]))
                count += 2
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count)
    }

    private func smooth(
        previous: DocumentQuadrilateral?,
        current: DocumentQuadrilateral
    ) -> DocumentQuadrilateral {
        guard let previous else { return current }
        let newWeight = 0.30
        func blend(_ old: CGPoint, _ new: CGPoint) -> CGPoint {
            CGPoint(
                x: old.x * (1 - newWeight) + new.x * newWeight,
                y: old.y * (1 - newWeight) + new.y * newWeight
            )
        }
        return DocumentQuadrilateral(
            topLeft: blend(previous.topLeft, current.topLeft),
            topRight: blend(previous.topRight, current.topRight),
            bottomRight: blend(previous.bottomRight, current.bottomRight),
            bottomLeft: blend(previous.bottomLeft, current.bottomLeft)
        )
    }
}

private struct FrameCandidate: @unchecked Sendable {
    let image: CGImage
    let quadrilateral: DocumentQuadrilateral
}

private enum ScannerError: LocalizedError {
    case permissionDenied
    case permissionUnavailable
    case noContinuityCamera
    case cannotAddCameraInput
    case cannotAddVideoOutput
    case noDocumentCandidate
    case processingInProgress
    case missingProcessedVariant(String)
    case sessionFailed(String)
    case deviceDisconnected

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有相机权限。请到“系统设置 → 隐私与安全性 → 相机”允许本应用。"
        case .permissionUnavailable:
            return "当前系统无法判定相机权限。"
        case .noContinuityCamera:
            return "未发现 iPhone 连续互通相机。请确认两台设备蓝牙、Wi-Fi 和连续互通相机均已开启。"
        case .cannotAddCameraInput:
            return "无法把 iPhone 相机加入拍摄会话。"
        case .cannotAddVideoOutput:
            return "无法读取 iPhone 实时画面。"
        case .noDocumentCandidate:
            return "还没有识别到清晰文档。请让纸张尽量填满画面并等待绿色框稳定。"
        case .processingInProgress:
            return "上一张扫描仍在处理，请稍后再试。"
        case .missingProcessedVariant(let variant):
            return "缺少处理结果：\(variant)。"
        case .sessionFailed(let detail):
            return "相机会话中断：\(detail)。请重新连接 iPhone 并重启应用。"
        case .deviceDisconnected:
            return "iPhone 相机已断开。请重新连接 iPhone 并重启应用。"
        }
    }
}
