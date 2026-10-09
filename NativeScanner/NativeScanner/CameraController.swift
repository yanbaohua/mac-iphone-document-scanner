import AVFoundation
import Combine
import Foundation

func largestPhotoDimension(in dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
    dimensions.max { lhs, rhs in
        let lhsPixels = Int64(lhs.width) * Int64(lhs.height)
        let rhsPixels = Int64(rhs.width) * Int64(rhs.height)
        if lhsPixels != rhsPixels {
            return lhsPixels < rhsPixels
        }

        let lhsLongEdge = max(lhs.width, lhs.height)
        let rhsLongEdge = max(rhs.width, rhs.height)
        if lhsLongEdge != rhsLongEdge {
            return lhsLongEdge < rhsLongEdge
        }

        return lhs.width < rhs.width
    }
}

func captureDimension(
    supportedByActiveFormat dimensions: [CMVideoDimensions],
    outputMaximum: CMVideoDimensions
) -> CMVideoDimensions? {
    dimensions.first {
        $0.width == outputMaximum.width && $0.height == outputMaximum.height
    }
}

func clampedPhotoQuality(
    _ desired: AVCapturePhotoOutput.QualityPrioritization,
    maximumSupported: AVCapturePhotoOutput.QualityPrioritization
) -> AVCapturePhotoOutput.QualityPrioritization {
    desired.rawValue <= maximumSupported.rawValue ? desired : maximumSupported
}

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    @Published private(set) var statusMessage = "尚未连接 iPhone 连续互通相机。"
    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var logLines: [String] = []

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.yanbaohua.NativeScanner.capture-session")
    private let pendingLock = NSLock()
    private var pendingCapture: PendingCapture?
    private var captureDevice: AVCaptureDevice?
    private var selectedDimension: CMVideoDimensions?
    private var selectedCodec: AVVideoCodecType?
    private var isConfigured = false

    func start() {
        publish(status: "正在检查相机权限…", ready: false)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureSession()
                } else {
                    self.publishFailure(ProbeError.permissionDenied)
                }
            }
        case .denied, .restricted:
            publishFailure(ProbeError.permissionDenied)
        @unknown default:
            publishFailure(ProbeError.permissionUnavailable)
        }
    }

    func capture(to directory: URL) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isConfigured, self.session.isRunning,
                  let device = self.captureDevice,
                  let outputMaximum = self.selectedDimension,
                  let codec = self.selectedCodec else {
                self.publishFailure(ProbeError.sessionNotReady)
                return
            }
            guard self.photoOutput.connection(with: .video) != nil else {
                self.publishFailure(ProbeError.photoConnectionUnavailable)
                return
            }
            let captureTimeDimensions = device.activeFormat.supportedMaxPhotoDimensions
            guard let dimension = captureDimension(
                supportedByActiveFormat: captureTimeDimensions,
                outputMaximum: outputMaximum
            ) else {
                self.publish(log: "拍摄前活动格式支持：\(captureTimeDimensions.map(Self.describe).joined(separator: ", "))；已配置输出：\(Self.describe(outputMaximum))")
                self.publishFailure(ProbeError.activePhotoFormatChanged)
                return
            }

            self.pendingLock.lock()
            let alreadyCapturing = self.pendingCapture != nil
            self.pendingLock.unlock()
            guard !alreadyCapturing else {
                self.publishFailure(ProbeError.captureInProgress)
                return
            }

            let didAccessSecurityScope = directory.startAccessingSecurityScopedResource()
            let fileExtension = codec == .hevc ? "heic" : "jpg"
            let destination = directory.appendingPathComponent(
                "native_probe_\(Self.timestamp()).\(fileExtension)"
            )

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
            settings.maxPhotoDimensions = dimension
            settings.photoQualityPrioritization = clampedPhotoQuality(
                .quality,
                maximumSupported: self.photoOutput.maxPhotoQualityPrioritization
            )

            self.pendingLock.lock()
            self.pendingCapture = PendingCapture(
                destination: destination,
                requestedDimension: dimension,
                didAccessSecurityScope: didAccessSecurityScope
            )
            self.pendingLock.unlock()

            self.publish(
                status: "正在拍摄原始静态照片…",
                capturing: true,
                log: "请求照片尺寸：\(Self.describe(dimension))，编码：\(codec.rawValue)"
            )
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let pending = takePendingCapture()
        defer {
            if pending?.didAccessSecurityScope == true {
                pending?.destination.deletingLastPathComponent().stopAccessingSecurityScopedResource()
            }
        }

        guard let pending else {
            publishFailure(ProbeError.missingCaptureDestination)
            return
        }
        if let error {
            publishFailure(ProbeError.photoProcessingFailed(error.localizedDescription))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            publishFailure(ProbeError.noPhotoData)
            return
        }

        do {
            try data.write(to: pending.destination, options: .atomic)
            let actual = photo.resolvedSettings.photoDimensions
            let fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            let summary = "实际输出：\(Self.describe(actual))，\(fileSize)"
            publish(
                status: "已保存原始照片：\(pending.destination.path)",
                capturing: false,
                log: summary
            )
            publish(log: "请求/实际：\(Self.describe(pending.requestedDimension)) → \(Self.describe(actual))")
            print("[NativeScanner] \(summary)")
            print("[NativeScanner] 已保存：\(pending.destination.path)")
        } catch {
            publishFailure(ProbeError.saveFailed(error.localizedDescription))
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isConfigured {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.publish(status: "iPhone 连续互通相机已就绪。", ready: true)
                return
            }

            do {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.continuityCamera],
                    mediaType: .video,
                    position: .unspecified
                )
                guard let device = discovery.devices.first else {
                    throw ProbeError.noContinuityCamera
                }

                let candidates = device.formats.flatMap { format in
                    format.supportedMaxPhotoDimensions.map { (format: format, dimension: $0) }
                }
                guard let dimension = largestPhotoDimension(in: candidates.map(\.dimension)),
                      let selectedFormat = candidates.first(where: {
                          $0.dimension.width == dimension.width && $0.dimension.height == dimension.height
                      })?.format else {
                    throw ProbeError.noPhotoDimensions
                }

                let uniqueDimensions = Self.uniqueSortedDimensions(candidates.map(\.dimension))
                self.session.beginConfiguration()
                do {
                    self.session.sessionPreset = .photo

                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        throw ProbeError.cannotAddCameraInput
                    }
                    self.session.addInput(input)

                    guard self.session.canAddOutput(self.photoOutput) else {
                        throw ProbeError.cannotAddPhotoOutput
                    }
                    self.session.addOutput(self.photoOutput)

                    try device.lockForConfiguration()
                    device.activeFormat = selectedFormat
                    device.unlockForConfiguration()
                    self.session.commitConfiguration()
                } catch {
                    self.session.commitConfiguration()
                    throw error
                }

                let committedFormat = device.activeFormat
                let committedDimensions = committedFormat.supportedMaxPhotoDimensions
                guard let committedDimension = largestPhotoDimension(in: committedDimensions) else {
                    throw ProbeError.noPhotoDimensions
                }
                self.photoOutput.maxPhotoDimensions = committedDimension
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                let codecs = self.photoOutput.availablePhotoCodecTypes
                guard let codec = codecs.contains(.hevc) ? AVVideoCodecType.hevc :
                        (codecs.contains(.jpeg) ? AVVideoCodecType.jpeg : nil) else {
                    throw ProbeError.noSupportedCodec
                }

                self.session.startRunning()

                let runningFormat = device.activeFormat
                let runningDimensions = runningFormat.supportedMaxPhotoDimensions
                guard let runningDimension = largestPhotoDimension(in: runningDimensions) else {
                    throw ProbeError.noPhotoDimensions
                }
                if captureDimension(
                    supportedByActiveFormat: runningDimensions,
                    outputMaximum: committedDimension
                ) == nil {
                    self.photoOutput.maxPhotoDimensions = runningDimension
                }
                guard captureDimension(
                    supportedByActiveFormat: device.activeFormat.supportedMaxPhotoDimensions,
                    outputMaximum: runningDimension
                ) != nil else {
                    throw ProbeError.activePhotoFormatChanged
                }

                let committedVideoDimension = CMVideoFormatDescriptionGetDimensions(committedFormat.formatDescription)
                let runningVideoDimension = CMVideoFormatDescriptionGetDimensions(runningFormat.formatDescription)
                self.captureDevice = device
                self.selectedDimension = runningDimension
                self.selectedCodec = codec
                self.isConfigured = true

                self.publish(log: "设备：\(device.localizedName) [\(device.deviceType.rawValue)]")
                self.publish(log: "本次运行设备标识：\(device.uniqueID)")
                self.publish(log: "全部支持的静态尺寸：\(uniqueDimensions.map(Self.describe).joined(separator: ", "))")
                self.publish(log: "会话提交后：视频 \(Self.describe(committedVideoDimension))，支持照片 \(committedDimensions.map(Self.describe).joined(separator: ", "))")
                self.publish(log: "会话启动后：视频 \(Self.describe(runningVideoDimension))，支持照片 \(runningDimensions.map(Self.describe).joined(separator: ", "))")
                self.publish(log: "照片输出上限：\(Self.describe(runningDimension))")
                self.publish(log: "可用编码：\(codecs.map(\.rawValue).joined(separator: ", "))；选中：\(codec.rawValue)")

                self.publish(status: "iPhone 连续互通相机已就绪，请选择保存目录。", ready: true)
                print("[NativeScanner] 设备：\(device.localizedName) [\(device.uniqueID)]")
                print("[NativeScanner] 支持尺寸：\(uniqueDimensions.map(Self.describe).joined(separator: ", "))")
                print("[NativeScanner] 请求上限：\(Self.describe(runningDimension))")
            } catch {
                self.publishFailure(error)
            }
        }
    }

    private func takePendingCapture() -> PendingCapture? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        let pending = pendingCapture
        pendingCapture = nil
        return pending
    }

    private func publish(
        status: String? = nil,
        ready: Bool? = nil,
        capturing: Bool? = nil,
        log: String? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let status { self.statusMessage = status }
            if let ready { self.isReady = ready }
            if let capturing { self.isCapturing = capturing }
            if let log { self.logLines.append(log) }
        }
    }

    private func publishFailure(_ error: any Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        publish(status: "错误：\(message)", capturing: false, log: "错误：\(message)")
        print("[NativeScanner] 错误：\(message)")
    }

    private static func uniqueSortedDimensions(_ dimensions: [CMVideoDimensions]) -> [CMVideoDimensions] {
        var seen = Set<String>()
        return dimensions
            .sorted {
                Int64($0.width) * Int64($0.height) > Int64($1.width) * Int64($1.height)
            }
            .filter { seen.insert(describe($0)).inserted }
    }

    private static func describe(_ dimension: CMVideoDimensions) -> String {
        "\(dimension.width)×\(dimension.height)"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSSSSS"
        return formatter.string(from: Date())
    }
}

private struct PendingCapture {
    let destination: URL
    let requestedDimension: CMVideoDimensions
    let didAccessSecurityScope: Bool
}

private enum ProbeError: LocalizedError {
    case permissionDenied
    case permissionUnavailable
    case noContinuityCamera
    case noPhotoDimensions
    case cannotAddCameraInput
    case cannotAddPhotoOutput
    case noSupportedCodec
    case sessionNotReady
    case photoConnectionUnavailable
    case activePhotoFormatChanged
    case captureInProgress
    case missingCaptureDestination
    case photoProcessingFailed(String)
    case noPhotoData
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有相机权限。请到“系统设置 → 隐私与安全性 → 相机”允许本应用。"
        case .permissionUnavailable:
            return "当前系统无法判定相机权限。"
        case .noContinuityCamera:
            return "未发现 iPhone 连续互通相机，且本应用不会回退到 Mac 内置摄像头。"
        case .noPhotoDimensions:
            return "iPhone 相机没有报告可用的静态照片尺寸。"
        case .cannotAddCameraInput:
            return "无法把 iPhone 相机加入拍摄会话。"
        case .cannotAddPhotoOutput:
            return "无法创建静态照片输出。"
        case .noSupportedCodec:
            return "设备不支持 HEIC 或 JPEG 静态照片编码。"
        case .sessionNotReady:
            return "相机尚未就绪，请先连接 iPhone 相机。"
        case .photoConnectionUnavailable:
            return "iPhone 静态照片连接已失效。请确保 iPhone 在附近并重新连接。"
        case .activePhotoFormatChanged:
            return "相机活动格式已变化，旧的照片尺寸不再合法。请重启应用后再试。"
        case .captureInProgress:
            return "上一张照片仍在处理，请稍后再试。"
        case .missingCaptureDestination:
            return "拍摄完成时丢失了保存位置。"
        case .photoProcessingFailed(let detail):
            return "照片处理失败：\(detail)"
        case .noPhotoData:
            return "相机没有返回可写入的照片数据。"
        case .saveFailed(let detail):
            return "照片保存失败：\(detail)"
        }
    }
}
