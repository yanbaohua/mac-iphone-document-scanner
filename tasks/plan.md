# Implementation Plan：原生高清高拍仪

状态：已批准（2026-10-09）

## Overview

在保留 Python `v1.0.0` 的前提下，新增独立的 Swift macOS 应用。实施先解决最大不确定性：iPhone 连续互通相机是否通过 `AVCapturePhotoOutput` 提供显著高于 1920×1440 的真实静态照片。只有探针通过像素和文字细节双重门槛，才投入文档处理、实时绿框和完整界面。

## Dependency Graph

```text
Task 1 完整 Xcode 与工具链记录
  └─ Task 2 最小签名 macOS 工程
       └─ Task 3 连续互通静态照片探针
            └─ Checkpoint A：Go / No-Go
                 └─ Task 4 全尺寸文档处理管线
                      └─ Task 5 实时预览与节流绿框
                           └─ Task 6 扫描、校正与 PNG 保存闭环
                                └─ Task 7 交互与故障恢复
                                     └─ Task 8 真机回归与交付文档
                                          └─ Checkpoint B：可交付
```

Task 3 是硬门槛。No-Go 时终止 Task 4–8，不以插值、锐化或 UI 包装替代真实清晰度提升。

## Architecture Decisions

- 原生应用位于 `NativeScanner/`，不移动或改写 Python 文件。
- 使用 SwiftUI 单窗口外壳；仅用 `NSViewRepresentable` 承载 `AVCaptureVideoPreviewLayer`，用 `NSOpenPanel` 选择输出目录。
- `CameraController` 独占 AVFoundation 会话，并在串行队列配置、启动和停止会话。
- `DocumentProcessor` 不依赖 UI 或相机，输入静态图片和方向，输出校正后的灰度图片或明确错误，便于 XCTest 覆盖。
- 预览 Vision 分析最多 5 FPS、只允许一个请求在途；静态照片另行执行全尺寸检测。
- App Sandbox 保持启用，首版只使用本次会话中用户选择的目录，不持久化书签。
- 不引入第三方包，不做 OCR、PDF、自动拍摄、云同步或 App Store 分发。
- 每个任务形成一个可回退的原子提交；未经用户批准不创建新版本标签或公开发布。

## Implementation Phases

### Phase 1：工具链与能力探针

- Task 1：安装并验证完整 Xcode，记录工具链版本。
- Task 2：创建最小签名 macOS 工程，验证权限声明和沙箱目录访问。
- Task 3：发现连续互通设备、枚举静态照片尺寸并保存最大尺寸原图。

### Checkpoint A：原生高清可行性

- 实际输出总像素不少于 5,529,600。
- 同机位 10 磅文字对比显示真实额外细节。
- 请求尺寸、实际尺寸、格式和文件大小都有日志证据。
- 用户确认 Go 后才继续；No-Go 则保存探针结果并停止后续任务。

### Phase 2：文档处理与实时反馈

- Task 4：完成可独立测试的矩形检测、坐标转换、透视与灰度 PNG 管线。
- Task 5：加入实时预览、5 FPS Vision 分析和稳定绿色四边形。

### Checkpoint B1：处理与预览

- XCTest 全部通过。
- 预览持续运行且 UI 不被 Vision 阻塞。
- 文档稳定可见时绿框方向和位置正确。

### Phase 3：扫描闭环与交付

- Task 6：在全尺寸静态照片上重新检测、校正并保存 PNG。
- Task 7：补齐输出目录、键盘操作、权限与断连错误状态。
- Task 8：执行 20 次真机回归，更新使用说明和版本记录。

### Checkpoint B2：可交付

- 构建与 XCTest 通过。
- 连接、预览、扫描、保存、退出流程完整。
- 20 次连续拍摄无崩溃、无重名覆盖、无明显持续内存增长。
- Git 暂存内容不包含扫描件、设备标识、签名凭据或构建产物。
- 用户审核通过后再提交、推送和决定版本标签。

## Verification Commands

```bash
xcodebuild -version
swift --version
xcodebuild -project NativeScanner/NativeScanner.xcodeproj \
  -scheme NativeScanner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath NativeScanner/build build
xcodebuild -project NativeScanner/NativeScanner.xcodeproj \
  -scheme NativeScanner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath NativeScanner/build test
```

真机验证必须在签名 GUI 应用中执行。命令行构建成功不能代替相机授权、连续互通连接、照片尺寸和视觉细节验证。

## Definition of Done

每项任务只有在以下条件全部满足时才能勾选：

- 该任务的验收条件与错误路径均已实际验证。
- 新增非平凡逻辑有能在缺少实现时失败的测试。
- 构建、相关 XCTest 和既有 Python 测试通过。
- 没有死代码、调试输出、无关重构或未说明的依赖。
- 用户可见行为和关键架构决策已同步到文档。
- 扫描件、设备标识、签名资料和构建产物未进入 Git。
- 有可回退提交，且需要人审的真机结果已由用户确认。

## Parallelization

Task 1–3 必须顺序执行。Checkpoint A 通过后，Task 4 的纯图像处理与界面草图理论上可以并行，但首版不提前建设界面；实际仍按 Task 4 → Task 5 顺序推进，以避免在高清能力尚未证实前增加代码和协调成本。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 连续互通静态照片不超过现有画质 | High | Task 3 最先实测；不达门槛立即 No-Go |
| 完整 Xcode 缺失或 SDK 与系统不兼容 | High | Task 1 记录版本并完成最小构建后才建功能 |
| SDK 不接受连续互通声明键或设备类型 | High | Task 2 以实际 SDK 头文件、构建诊断和真机发现结果为准 |
| 预览与静态照片方向、裁切不同 | Medium | 静态原图重新检测；坐标转换由生成图片测试覆盖 |
| Vision 造成预览卡顿 | Medium | 5 FPS 上限、单请求在途、后台队列 |
| 输出目录沙箱权限失效 | Medium | 每次会话重新选择目录；写入前检查并反馈错误 |
| 私人试卷进入版本库 | High | 忽略测试输出；每次提交前检查暂存文件树 |

## Rollback

- Python `v1.0.0` 标签和 `main` 上的现有实现保持不变。
- 原生应用全部位于 `NativeScanner/`，任何失败切片都可按原子提交回退。
- 探针 No-Go 时保留规格、源码和去隐私日志，但不发布一个无法提升画质的扫描器。

## Open Questions

- Xcode 安装后的准确版本与 SDK 版本。
- SDK 中 `NSCameraUseContinuityCameraDeviceType` 的正式声明和行为。
- iPhone 16 Pro 实际暴露的静态照片尺寸与最终 Go / No-Go 结论。
