# 原生高清高拍仪任务清单

状态：待任务清单批准

## Task 1：准备并记录完整 Xcode 工具链

**Description:** 安装完整 Xcode.app，选择其 Developer 目录，接受许可证，并记录实际 Xcode、Swift、SDK、macOS 和架构信息。

**Acceptance criteria:**

- [x] `/Applications/Xcode.app` 存在，`xcode-select -p` 指向其中的 Developer 目录。
- [x] `xcodebuild -version`、`swift --version` 和 macOS SDK 查询均成功。
- [x] 工具链版本写入 `docs/native-environment.md`。

**Verification:**

- [x] `xcodebuild -version`
- [x] `swift --version`
- [x] `xcrun --sdk macosx --show-sdk-version`

**Dependencies:** None

**Files likely touched:**

- `docs/native-environment.md`

**Estimated scope:** XS

## Task 2：建立最小签名 macOS 工程

**Description:** 创建 `NativeScanner` SwiftUI macOS App 和测试 target，配置相机用途说明、连续互通声明候选、App Sandbox 与用户选择文件读写权限，并显示最小状态窗口。

**Acceptance criteria:**

- [x] 工程可使用当前 Xcode 和本机签名构建、启动。
- [x] 相机用途说明与沙箱 entitlement 可在构建产物中核验。
- [x] `NSCameraUseContinuityCameraDeviceType` 已依据 SDK 声明或构建结果确认，而非猜测。

**Verification:**

- [x] Debug 构建成功。
- [x] 应用启动且不立即崩溃。
- [x] 使用 `codesign` / `plutil` 检查签名、entitlement 和 Info.plist。

**Dependencies:** Task 1

**Files likely touched:**

- `NativeScanner/NativeScanner.xcodeproj/`
- `NativeScanner/NativeScanner/NativeScannerApp.swift`
- `NativeScanner/NativeScanner/ContentView.swift`
- `NativeScanner/NativeScanner/Info.plist`
- `NativeScanner/NativeScanner/NativeScanner.entitlements`

**Estimated scope:** M

## Task 3：完成连续互通静态照片探针

**Description:** 发现 `.continuityCamera` 设备，枚举活动格式支持的最大照片尺寸，选择总像素最大的合法尺寸，捕获一张原始静态照片到用户选择的文件夹，并记录请求值与实际值。

**Acceptance criteria:**

- [ ] 只选择连续互通相机，不回退到 Mac 内置摄像头。
- [ ] 日志列出设备、活动格式、全部支持尺寸、请求尺寸和实际输出信息。
- [ ] 能保存一张未经插值的原始静态照片，并对无设备、拒绝权限和保存失败给出明确错误。

**Verification:**

- [ ] `largestPhotoDimension` XCTest 通过。
- [ ] 真机照片可从 Finder 打开并读取实际像素尺寸。
- [ ] 与 Python 1920×1440 基线完成同机位文字细节对比。

**Dependencies:** Task 2

**Files likely touched:**

- `NativeScanner/NativeScanner/CameraController.swift`
- `NativeScanner/NativeScanner/ContentView.swift`
- `NativeScanner/NativeScannerTests/CaptureConfigurationTests.swift`
- `docs/native-probe-results.md`

**Estimated scope:** M

## Checkpoint A：Go / No-Go

- [ ] 实际照片不少于 5,529,600 像素。
- [ ] 10 磅文字对比有真实额外细节。
- [ ] 用户确认 Go；否则停止 Task 4–8。

## Task 4：实现全尺寸文档处理管线

**Description:** 在独立 `DocumentProcessor` 中完成 Vision 矩形检测、方向处理、坐标转换、Core Image 透视校正、灰度转换和 PNG 编码。

**Acceptance criteria:**

- [ ] 静态图片返回置信度最高的文档四角或明确的未检测错误。
- [ ] 透视输出方向、边界和灰度正确，像素尺寸没有插值放大。
- [ ] 非二值化灰阶细节得到保留。

**Verification:**

- [ ] 生成测试图的坐标、透视和灰度 XCTest 通过。
- [ ] 无矩形、旋转图片和非正方形图片测试通过。
- [ ] 相关测试失败时任务不得完成。

**Dependencies:** Checkpoint A = Go

**Files likely touched:**

- `NativeScanner/NativeScanner/DocumentProcessor.swift`
- `NativeScanner/NativeScannerTests/DocumentProcessorTests.swift`

**Estimated scope:** S

## Task 5：加入实时预览和绿色文档框

**Description:** 把连续互通会话接入预览层，使用最多 5 FPS、单请求在途的 Vision 分析更新绿色四边形，并在短暂检测丢失时保持不超过 0.5 秒。

**Acceptance criteria:**

- [ ] 实时预览来自 iPhone 连续互通相机。
- [ ] 文档稳定可见时绿框位置、方向正确，短暂丢失不剧烈闪烁。
- [ ] Vision 不在主线程运行且不会堆积分析请求。

**Verification:**

- [ ] Debug 构建和已有 XCTest 通过。
- [ ] 真机移动、倾斜和短暂遮挡测试完成。
- [ ] 使用 Instruments 或运行观察确认没有持续请求积压。

**Dependencies:** Task 4

**Files likely touched:**

- `NativeScanner/NativeScanner/CameraController.swift`
- `NativeScanner/NativeScanner/PreviewView.swift`
- `NativeScanner/NativeScanner/DocumentProcessor.swift`
- `NativeScanner/NativeScanner/ContentView.swift`

**Estimated scope:** M

## Checkpoint B1：处理与预览

- [ ] 全部 XCTest 通过。
- [ ] 预览持续运行，界面保持响应。
- [ ] 绿框在三类真机场景中正确。

## Task 6：打通全尺寸扫描和 PNG 保存

**Description:** 扫描时创建新的照片设置，捕获全尺寸静态照片，在原图上重新检测、透视和灰度处理，并以唯一文件名保存到已选目录。

**Acceptance criteria:**

- [ ] 每次拍摄使用新的 `AVCapturePhotoSettings`，且以实际照片尺寸处理。
- [ ] 最终裁切基于静态原图检测结果，不复用预览坐标。
- [ ] PNG 成功保存并显示绝对路径与真实像素尺寸；检测失败不保存错误裁切。

**Verification:**

- [ ] 文件命名和状态规则 XCTest 通过。
- [ ] Finder 可打开输出，方向、灰度和裁切正确。
- [ ] 连续两次扫描不会覆盖文件或复用照片设置。

**Dependencies:** Checkpoint B1

**Files likely touched:**

- `NativeScanner/NativeScanner/CameraController.swift`
- `NativeScanner/NativeScanner/DocumentProcessor.swift`
- `NativeScanner/NativeScanner/ContentView.swift`
- `NativeScanner/NativeScannerTests/CaptureConfigurationTests.swift`

**Estimated scope:** M

## Task 7：补齐交互与故障恢复

**Description:** 完成输出目录选择、扫描按钮、`S` / 空格快捷键、设备状态和权限、断连、忙碌、目录失效、识别失败提示。

**Acceptance criteria:**

- [ ] 无权限、无 iPhone、未选目录和拍摄中状态不会错误启动拍摄。
- [ ] iPhone 断开后应用不崩溃、不切换到内置摄像头，并能提示重新连接。
- [ ] 所有用户文案为简体中文且包含下一步操作。

**Verification:**

- [ ] 状态规则 XCTest 通过。
- [ ] 人工执行权限拒绝、断连和目录不可写测试。
- [ ] 按钮、`S`、空格和 `Command-Q` 行为正确。

**Dependencies:** Task 6

**Files likely touched:**

- `NativeScanner/NativeScanner/ContentView.swift`
- `NativeScanner/NativeScanner/CameraController.swift`
- `NativeScanner/NativeScanner/PreviewView.swift`
- `NativeScanner/NativeScannerTests/CaptureConfigurationTests.swift`

**Estimated scope:** M

## Task 8：真机回归和交付整理

**Description:** 完成 20 次连续拍摄、权限和连接回归，检查构建产物与 Git 隐私边界，并更新安装、运行、限制和回退说明。

**Acceptance criteria:**

- [ ] 20 次连续拍摄无崩溃、无覆盖、无明显持续内存增长。
- [ ] 构建、Swift XCTest 和既有 Python 测试全部通过。
- [ ] 文档准确说明实际照片上限、使用方法、已知限制和 Python 回退方式。

**Verification:**

- [ ] 执行完整 `xcodebuild build` 与 `xcodebuild test`。
- [ ] 执行 `.venv/bin/python -m unittest -v`。
- [ ] 检查 Git 暂存树不含扫描件、设备标识、签名凭据和 `NativeScanner/build/`。

**Dependencies:** Task 7

**Files likely touched:**

- `README.md`
- `CHANGELOG.md`
- `.gitignore`
- `docs/native-validation.md`

**Estimated scope:** M

## Checkpoint B2：可交付

- [ ] 所有规格成功条件满足。
- [ ] 用户审核真机结果和样张对比。
- [ ] 用户批准后再提交、推送和决定原生版标签。
