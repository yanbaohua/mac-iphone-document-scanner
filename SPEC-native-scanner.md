# Spec：Mac 单端本地增强高拍仪

状态：已批准（2026-10-09）
能力地图：[CAPABILITY-MAP.md](CAPABILITY-MAP.md)

## 1. Objective

为运行 macOS 15.7.3 的 M2 Pro Mac 开发原生应用，使用 iPhone 16 Pro 连续互通相机的实测 1920×1080 视频画面，完成实时预览、文档四角检测、稳定绿框、最佳帧选择、透视校正、本地清晰度增强和文件保存。

当前 Python 版及 `v1.0.0` 标签保持可用；原生版位于 `NativeScanner/`。本项目不再追求 iPhone 传感器原生像素，也不建设 iPhone 配套 App。

### 用户流程

1. 用户启动应用并授权相机访问。
2. 应用只连接 iPhone 连续互通相机，不回退到 Mac 内置摄像头。
3. 用户选择本次会话的 Mac 输出文件夹。
4. 应用显示实时画面，并在检测到文档时绘制稳定绿色四边形。
5. 用户点击“扫描”或按 `S` / 空格键。
6. 应用从近期候选帧中选择清晰度最高且检测到文档的一帧。
7. 应用在该帧上执行透视校正，并生成原始矫正、彩色增强和灰度增强三份 PNG。
8. 应用显示保存路径和真实输出像素尺寸。

## 2. Tech Stack

- 平台：macOS 15.7.3，Apple Silicon arm64。
- IDE：Xcode 26.3（build 17C529），macOS SDK 26.2。
- 语言：Swift 6.2.4，严格并发检查。
- UI：SwiftUI；`NSViewRepresentable` 承载 `AVCaptureVideoPreviewLayer`，`NSOpenPanel` 选择目录。
- 采集：AVFoundation，使用 `.continuityCamera`、`AVCaptureVideoDataOutput` 和预览层。
- 检测：Vision `VNDetectRectanglesRequest`。
- 处理：Core Image 透视校正、光照/对比度调整和保守锐化。
- 保存：ImageIO 编码 PNG；写入用户选择的安全作用域目录。
- 测试：XCTest。
- 第三方依赖：无。

## 3. Commands

```bash
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

.venv/bin/python -m unittest -v

open NativeScanner/build/Build/Products/Debug/NativeScanner.app
```

相机权限、连续互通连接、绿框位置和图像质量必须在 GUI 应用中真机验证。

## 4. Project Structure

```text
NativeScanner/NativeScanner/
  NativeScannerApp.swift        应用入口
  ContentView.swift             单窗口界面与操作
  CameraController.swift        相机会话、帧缓存、检测节流和扫描编排
  PreviewView.swift             预览层和绿色四边形
  DocumentProcessor.swift       检测、清晰度评分、透视与增强
  Info.plist
  NativeScanner.entitlements
NativeScanner/NativeScannerTests/
  CaptureConfigurationTests.swift
  DocumentProcessorTests.swift
```

不增加依赖注入容器、插件系统或通用图像框架层。

## 5. Functional Requirements

### `capture-core`

- 只发现 `.continuityCamera` 视频设备。
- 使用 `AVCaptureVideoDataOutput` 获取实际预览帧；丢弃迟到帧，避免积压。
- 检测与候选帧采样最多 5 FPS，同一时间只处理一帧。
- 只保留最近 8 个候选帧；缓存有固定上限。
- 清晰度评分使用输入亮度边缘变化，只用于同一相机、同一构图下择优，不宣称为通用画质评分。
- 扫描时只选择检测到可信文档的最高分帧；没有合格帧时明确提示重新摆放。
- 权限拒绝、无 iPhone 和设备断开时不崩溃、不切换到内置摄像头。

### `document-pipeline`

- Vision 检测返回置信度最高的文档四角。
- 短暂检测丢失时绿框最多保留 0.5 秒。
- Vision 归一化坐标正确转换为 Core Image 坐标后再透视校正。
- 输出尺寸由文档四边距离决定，不执行分辨率插值放大。
- `original`：仅透视校正，保留原始颜色。
- `color`：局部光照、对比度和轻度锐化，保留图表与照片层次。
- `gray`：灰度、对比度和轻度锐化，不做硬二值化。
- 三份输出均为 PNG；处理失败时不保存错误裁切。

### `scanner-ui`

- 单窗口显示实时预览、绿色文档框、设备状态、输出目录、扫描按钮和最近结果。
- 支持按钮、`S` 和空格键触发扫描；退出使用标准 `Command-Q`。
- 未连接、未选择目录、没有合格候选帧或正在处理时不能重复扫描。
- 文件组使用同一时间戳：`scan_yyyyMMdd_HHmmss_SSSSSS_original.png`、`_color.png`、`_gray.png`。
- 保存成功后显示绝对目录、输出尺寸和三份文件名。
- 所有用户文案使用简体中文。

## 6. Testing Strategy

### 自动测试

- 清晰度评分：纯色低分、边缘图高分、非法尺寸安全返回。
- Vision/Core Image 坐标：四角和非正方形图片转换正确。
- 输出尺寸：不超过原文档四边定义的自然尺寸，不插值放大。
- 增强输出：三种模式尺寸一致，灰度版不包含彩色通道差异。
- 文件命名：同一组共享时间戳，后缀正确且不覆盖。
- 状态规则：无目录、无设备、无候选帧和处理中不能再次扫描。

### 真机测试

1. 首次授权、拒绝后恢复授权。
2. iPhone 连接、断开和重新连接。
3. 深色背景、轻微倾斜、短暂遮挡时绿框稳定性。
4. 固定支架下对比原始矫正、彩色增强和灰度增强的小字、铅笔字和图表。
5. Finder 打开三份 PNG，确认方向、裁切、尺寸和文件名正确。
6. 连续扫描 20 次，确认无崩溃、覆盖或持续内存增长。

真实扫描件只保存在 Git 忽略的本地目录。

## 7. Boundaries

### Always do

- 报告真实输入和输出尺寸，不显示虚假 DPI。
- 保留原始矫正图，增强结果不能覆盖它。
- 处理在后台执行，UI 更新返回主线程。
- 每次提交前运行相关 XCTest；交付前运行完整 Swift 和 Python 测试。
- 保留 Python `v1.0.0` 回退版本。

### Ask first

- 添加任何第三方依赖或 AI 模型。
- 改为 iPhone 配套 App、关闭沙箱或增加新系统权限。
- 增加 OCR、PDF、自动拍摄、批量管理、云同步或 App Store 发布。

### Never do

- 将真实试卷、扫描件、设备标识或签名凭据提交到 Git。
- 通过插值或生成式补笔画宣称获得真实细节。
- 识别失败时静默保存错误裁切或覆盖文件。
- 使用已弃用的外接摄像头类型绕过连续互通声明。

## 8. Success Criteria

- 实时预览来自 iPhone 连续互通相机，UI 无明显卡顿。
- 文档稳定可见时绿框正确，短暂丢失不频繁闪烁。
- 扫描选择近期合格帧中清晰度最高者，并完成透视校正。
- 三份 PNG 可由 Finder 打开；彩色和灰度增强比原始帧更易读且无明显光晕。
- 权限、断连、目录缺失和识别失败都有可操作提示。
- 自动测试通过；20 次真机连续扫描无崩溃和文件覆盖。

## 9. Open Questions

无。真实画质和参数仍需在首轮样张中校准，但不阻塞实现。
