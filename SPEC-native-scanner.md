# Spec：原生高清高拍仪

状态：已批准（2026-10-08）
能力地图：[CAPABILITY-MAP.md](CAPABILITY-MAP.md)

## 1. Objective

为一台运行 macOS 15.7.3 的 M2 Pro Mac 开发本地原生应用，使用 iPhone 16 Pro 连续互通相机完成文档实时预览、静态照片捕获、文档四角检测、透视校正和无损灰度 PNG 保存。

本项目首先验证“原生照片输出是否真正提高细节”，而不是默认原生 API 一定能获得 iPhone 相机 App 的完整像素。当前 Python 版及 `v1.0.0` 标签必须保持可用，原生版放在独立目录中。

### 用户流程

1. 用户启动应用并授权相机访问。
2. 应用发现 iPhone 连续互通相机；不存在时显示可操作的排查信息。
3. 用户选择本次会话的 Mac 输出文件夹。
4. 应用显示实时预览，并在识别到文档时绘制绿色四边形。
5. 用户点击“扫描”或按 `S` / 空格键。
6. 应用捕获最大合法尺寸的静态照片，在静态原图上重新检测四角并执行透视校正。
7. 应用保存灰度 PNG，显示保存路径和实际像素尺寸。

### 高清验证门槛

现有基线为 `1920×1440 = 2,764,800` 像素。`capture-core` 探针必须保存原始静态照片并记录以下信息：

- 连续互通设备名称、唯一标识和设备类型。
- 活动格式与所有 `supportedMaxPhotoDimensions`。
- 请求的最大照片尺寸。
- 实际输出宽高、总像素数、文件格式和文件大小。

只有同时满足以下条件才继续完整应用：

- 实际静态照片总像素数不少于基线的 2 倍，即至少 `5,529,600` 像素。
- 使用同一支架、纸张、构图和光线时，10 磅印刷文字的局部对比图显示出可辨认的额外笔画细节，而不是插值放大。

若任一条件失败，则停止 `scanner-ui` 开发，保存探针源码、日志和不含私人文档的测试结果，并报告连续互通 API 的实测上限。

应用只显示真实像素尺寸。首版不显示或写入“有效 DPI”，因为没有纸张物理尺寸就无法可靠计算 DPI。

## 2. Tech Stack

- 平台：macOS 15.7.3，Apple Silicon arm64。
- IDE：Xcode 26.3（build 17C529），macOS SDK 26.2。
- 语言：Xcode 所附 Swift 6.2.4，不单独安装或锁定另一套 Swift 工具链。
- UI：SwiftUI；仅在预览层、目录选择器等系统能力需要时桥接 AppKit。
- 采集：AVFoundation。
  - 使用 `AVCaptureDevice.DiscoverySession` 与 `.continuityCamera` 发现设备。
  - 使用 `AVCaptureVideoPreviewLayer` 显示预览。
  - 使用 `AVCaptureVideoDataOutput` 向 Vision 提供节流后的预览帧。
  - 使用 `AVCapturePhotoOutput` 捕获静态照片。
  - 最大照片尺寸从当前活动格式的 `supportedMaxPhotoDimensions` 选择，并在会话启动前配置。
- 文档检测：Vision `VNDetectRectanglesRequest`。
- 透视校正与灰度处理：Core Image `CIFilter.perspectiveCorrection()` 和系统颜色滤镜。
- 文件选择：AppKit `NSOpenPanel`，每次应用启动只选择一次目录，不在首版持久化安全作用域书签。
- 测试：XCTest。
- 第三方依赖：无。

### 系统声明

- `Info.plist` 必须包含 `NSCameraUsageDescription`。
- Xcode 26.3 SDK 头文件已确认工程需要配置 `NSCameraUseContinuityCameraDeviceType = true`，使连续互通摄像头以 `.continuityCamera` 类型报告。
- App Sandbox 保持启用，并允许用户选择文件的读写访问；首版不申请照片图库权限，因为文件直接写入用户选择的 Mac 文件夹。

## 3. Commands

以下命令在完整 Xcode 安装、工程生成并确认 scheme 名称为 `NativeScanner` 后执行：

```bash
# 构建
xcodebuild -project NativeScanner/NativeScanner.xcodeproj \
  -scheme NativeScanner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath NativeScanner/build build

# 单元测试
xcodebuild -project NativeScanner/NativeScanner.xcodeproj \
  -scheme NativeScanner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath NativeScanner/build test

# 运行已构建应用
open NativeScanner/build/Build/Products/Debug/NativeScanner.app
```

真机相机权限、连续互通连接和图像质量必须在 GUI 应用中人工验证，不能由无相机权限的命令行测试替代。

## 4. Project Structure

```text
CAPABILITY-MAP.md                 能力边界和依赖顺序
SPEC-native-scanner.md            本规格
scanner.py                        已归档 Python 回退版本
test_scanner.py                   Python 版测试
NativeScanner/
  NativeScanner.xcodeproj/        Xcode 工程
  NativeScanner/
    NativeScannerApp.swift        应用入口
    ContentView.swift             单窗口界面与用户操作
    CameraController.swift        设备发现、会话、预览帧和静态照片捕获
    PreviewView.swift             AVCaptureVideoPreviewLayer 的 AppKit 桥接
    DocumentProcessor.swift       Vision 检测、坐标转换、透视与 PNG 编码
    Info.plist                    相机用途和连续互通声明
    NativeScanner.entitlements    沙箱与用户选择文件权限
  NativeScannerTests/
    CaptureConfigurationTests.swift
    DocumentProcessorTests.swift
```

不增加通用框架层、依赖注入容器或插件系统。三个模块按能力地图保持单向依赖：采集和文档处理不依赖界面。

## 5. Code Style

- 遵循 Swift API Design Guidelines；类型使用 `UpperCamelCase`，函数和属性使用 `lowerCamelCase`。
- 相机会话的配置和启动在专用串行队列执行，不阻塞主线程。
- Vision 分析在后台队列执行；只有可观察 UI 状态和图层更新返回主线程。
- 失败使用有上下文的 `Error`，用户界面显示可执行的恢复建议，不静默失败。
- 不使用强制解包处理设备、图片、文件 URL 或 Vision 结果。

示例：最大尺寸选择保持为可测试的纯函数。

```swift
func largestPhotoDimension(in dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
    dimensions.max {
        Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
    }
}
```

## 6. Functional Requirements

### `capture-core`

- 只选择设备类型为 `.continuityCamera` 的视频设备，不把 Mac 内置摄像头误当作高清来源。
- 权限状态为未决定时请求权限；被拒绝时给出“系统设置 → 隐私与安全性 → 相机”的恢复路径。
- 使用照片优先的会话配置，同时提供预览、视频帧分析和静态照片输出。
- 从活动格式的合法尺寸中选择总像素数最大的尺寸；没有合法尺寸时明确失败。
- 每次拍摄创建新的 `AVCapturePhotoSettings`，不得复用设置实例。
- 保存前读取实际照片宽高，不能把请求尺寸当作实际输出尺寸。
- iPhone 断开时停止可用状态并提示重新连接，不崩溃、不自动切换到 Mac 内置摄像头。

### `document-pipeline`

- 预览分析最多每秒 5 帧，且同一时间只处理一帧，避免请求堆积。
- 预览检测返回置信度最高的一个文档四边形；短暂丢失时最多保留上次绿框 0.5 秒。
- 静态拍摄完成后必须在原始照片上重新执行矩形检测，不复用预览坐标。
- Vision 输入必须显式提供照片方向。
- 将 Vision 归一化坐标正确转换为 Core Image 坐标后再透视校正。
- 输出为 8 位灰度无损 PNG，不执行二值化、锐化或分辨率插值。
- 全尺寸图片未检测到可信文档时不保存错误裁切，显示重新摆放纸张的提示。

### `scanner-ui`

- 单窗口界面包含：实时预览、绿色文档框、设备状态、实际预览尺寸、输出目录、选择目录按钮、扫描按钮和最近一次结果。
- 未授权、未连接 iPhone、未选择输出目录、正在拍摄或未检测到文档时，扫描按钮不可误触或给出明确反馈。
- 支持按钮、`S` 和空格键触发扫描；退出使用标准 macOS `Command-Q`。
- 文件名使用本地时间和微秒，格式为 `scan_yyyyMMdd_HHmmss_SSSSSS.png`，避免覆盖已有文件。
- 保存成功后显示绝对路径和实际输出像素尺寸。
- 所有界面文案使用简体中文。

## 7. Testing Strategy

### 自动测试

- `largestPhotoDimension`：空数组、单一尺寸、相同面积和多个尺寸。
- Vision/Core Image 坐标转换：四角、旋转方向和非正方形图片。
- 透视校正：使用生成的倾斜矩形测试图验证输出方向和边界。
- 灰度 PNG：验证单通道、非二值化、像素尺寸未被放大。
- 文件命名：连续生成不冲突，扩展名正确。
- 状态规则：未选目录、无设备和拍摄中不能启动第二次拍摄。

### 真机测试

1. 首次授权、拒绝后恢复授权。
2. 无 iPhone、iPhone 连接、拍摄中断和重新连接。
3. 记录所有支持尺寸并保存一张未裁切原图。
4. 固定同一支架和试卷，对比 Python 基线与原生静态照片。
5. 验证深色背景、轻微阴影、试卷倾斜和短暂遮挡时的绿框。
6. 验证扫描后 PNG 能从 Finder 打开，路径、像素尺寸和视觉方向正确。
7. 连续拍摄 20 张，确认无崩溃、无重名覆盖和明显内存持续增长。

真机测试图片只保存在被 Git 忽略的本地目录，不进入仓库。

## 8. Boundaries

### Always do

- 使用 Apple 当前 SDK 中未弃用的 API，并在代码注释或开发记录中保留对应官方文档链接。
- 在写 UI 前通过 `capture-core` 高清门槛。
- 每次提交前运行构建和 XCTest。
- 报告请求尺寸与实际输出尺寸，不夸大分辨率或 DPI。
- 保留 Python `v1.0.0` 回退版本，不覆盖其源码和标签。

### Ask first

- 添加任何第三方依赖。
- 改为保存彩色、JPEG、HEIF、PDF 或原始照片副本。
- 持久化输出目录权限、关闭 App Sandbox 或增加新的系统权限。
- 增加自动拍摄、OCR、批量管理、云同步或 App Store 发布。
- 高清探针失败后改走 USB、iPhone 配套应用或其他硬件路线。

### Never do

- 将真实试卷、扫描件、设备标识或签名凭据提交到 Git。
- 通过插值放大宣称提升清晰度。
- 把请求的最大尺寸当作实际拍摄尺寸。
- 识别失败时静默保存错误裁切或覆盖已有文件。
- 使用已弃用的外接摄像头设备类型规避连续互通警告。

## 9. Success Criteria

### 阶段 A：能力探针

- 完整 Xcode 已安装并记录版本。
- 签名后的 macOS 应用可以发现 iPhone 16 Pro 连续互通相机。
- 应用记录所有最大照片尺寸并保存一张实际静态原图。
- 高清验证门槛有明确的 Go 或 No-Go 结论及证据。

### 阶段 B：完整扫描器，仅在 Go 后执行

- 实时预览不因 Vision 检测明显卡顿，检测频率不超过每秒 5 帧。
- 文档稳定可见时显示绿色四边形。
- 扫描会在全尺寸静态照片上重新检测和透视校正。
- 输出 PNG 保留灰阶且无插值放大，保存到用户选择的 Mac 文件夹。
- 权限拒绝、iPhone 断开、目录缺失和文档检测失败均有明确提示。
- 自动测试通过，20 次连续真机拍摄无崩溃和文件覆盖。

## 10. Open Questions

1. iPhone 16 Pro 通过这台 Mac 的连续互通相机实际暴露哪些 `supportedMaxPhotoDimensions`，只能由阶段 A 真机探针回答。
