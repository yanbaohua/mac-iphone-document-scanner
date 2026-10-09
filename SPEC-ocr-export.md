# Spec：本地 OCR 导出

状态：已批准（2026-10-09）
模块 id：`ocr-export`
能力地图：[CAPABILITY-MAP.md](CAPABILITY-MAP.md)

## 1. Objective

在现有 Mac 单端扫描流程中加入完全本地的文字识别。每次三份 PNG 成功保存后，应用使用 Apple Vision 识别原始透视校正图中的简体中文和英文，并在同一目录输出便于阅读的 TXT 与便于复核、后续处理的 JSON。

OCR 是图像保存之后的附加步骤，而不是扫描成功的前提。OCR 失败、没有识别到文字或 OCR 文件写入失败，都不得删除或回滚已经成功保存的 PNG。

### 用户流程

1. 用户按现有方式点击“扫描”或使用快捷键。
2. 应用完成透视校正，并先保存 `original`、`color`、`gray` 三份 PNG。
3. 应用对 `original` 对应的原始矫正图执行一次高精度 OCR。
4. 识别成功时，应用保存同时间戳的 `_ocr.txt` 和 `_ocr.json`，并显示识别条目数量。
5. 没有识别到文字时，仍保存空 TXT 和有效 JSON，并提示“未识别到文字”。
6. OCR 失败时，界面显示“图像已保存，但 OCR 失败”及可操作原因；三份 PNG 保留。

### 已采用的假设

- 每次成功扫描后自动执行 OCR，不增加第二个“OCR”按钮。
- OCR 输入为未锐化、未调高对比度的原始透视校正图，避免增强处理改变笔画。
- 首版识别语言固定为简体中文和英文；运行时只使用 Vision 实际支持的交集。
- 首版只输出 UTF-8 TXT 和 JSON，不提供文字编辑、搜索、题目结构化或 PDF。
- TXT 阅读顺序采用基于文字框位置的确定性启发式；JSON 保留每条文字的位置和置信度，供人工复核。

## 2. Tech Stack

- 继续使用 macOS 15.7.3、Swift 6、SwiftUI 和现有 Xcode 工程。
- OCR：Apple Vision `VNRecognizeTextRequest`。
- 识别级别：`.accurate`。
- 语言：优先 `zh-Hans`、`en-US`，启动识别前与请求的运行时支持语言求交集。
- 语言修正：`usesLanguageCorrection = true`。
- 输入：现有 `DocumentProcessor` 生成的 `original` 矫正结果。
- 序列化：Foundation `JSONEncoder`，UTF-8，不增加第三方依赖。
- 文件写入：复用现有 `writeAtomicallyWithoutOverwriting`。

本机 Xcode 26.3 SDK 已确认上述 Vision 请求、准确模式、语言修正和运行时支持语言查询接口可用。首版不使用 Python、PyObjC、云端 OCR、Core ML 模型或超分辨率输入。

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

最终验收必须用真实中文试卷完成；合成测试只能验证接口、排序、序列化和基本英文识别，不能代替真机样张。

## 4. Project Structure

```text
NativeScanner/NativeScanner/
  OCRProcessor.swift            Vision OCR、阅读顺序、TXT/JSON 数据生成
  CameraController.swift        在 PNG 保存后调用 OCR，并隔离 OCR 失败
NativeScanner/NativeScannerTests/
  OCRProcessorTests.swift       坐标、排序、序列化和合成文字测试
README.md                       使用说明、输出文件和隐私边界
CHANGELOG.md                    记录本地 OCR 能力
```

不增加 OCR 服务层、协议抽象、依赖注入容器或语言配置界面。`OCRProcessor` 只负责从一张矫正图生成内存中的 OCR 结果；扫描编排和文件生命周期仍由 `CameraController` 负责。

## 5. Functional and Data Contract

### 识别规则

- 每个 `VNRecognizedTextObservation` 只取最高置信度候选，不猜测或合并多个候选。
- 不用置信度阈值静默丢弃结果；置信度写入 JSON，由用户或后续工具判断。
- 阅读顺序按转换后的左上角像素坐标排序：先 `y` 从小到大，再 `x` 从小到大。
- TXT 每个观察结果占一行，文件末尾保留一个换行；无结果时 TXT 为空文件。
- JSON 中的文字必须与 TXT 使用同一顺序，避免两个输出互相矛盾。

该排序适合常见单栏试卷和文档，但不承诺恢复复杂多栏、表格或竖排文本的语义顺序。文字框数据必须保留，以便后续模块重新排版而不必重新 OCR。

### 文件命名

一次扫描的五份文件共用现有时间戳：

```text
scan_yyyyMMdd_HHmmss_SSSSSS_original.png
scan_yyyyMMdd_HHmmss_SSSSSS_color.png
scan_yyyyMMdd_HHmmss_SSSSSS_gray.png
scan_yyyyMMdd_HHmmss_SSSSSS_ocr.txt
scan_yyyyMMdd_HHmmss_SSSSSS_ocr.json
```

TXT 与 JSON 作为一个 OCR 文件组写入：如果其中一个写入失败，删除本次已经写入的 OCR 文件，但不触碰三份 PNG。所有写入保持“不覆盖已有文件”的现有规则。

### JSON v1

```json
{
  "schemaVersion": 1,
  "sourceImage": "scan_20261009_101112_123456_original.png",
  "imageWidth": 880,
  "imageHeight": 633,
  "coordinateSystem": "pixel-top-left",
  "recognitionLanguages": ["zh-Hans", "en-US"],
  "plainText": "第一行\nSecond line\n",
  "observations": [
    {
      "index": 0,
      "text": "第一行",
      "confidence": 0.97,
      "boundingBox": {
        "x": 42.5,
        "y": 31.0,
        "width": 210.0,
        "height": 28.0
      }
    }
  ]
}
```

- 坐标单位为原始矫正图像素，原点位于左上角。
- `index` 是 TXT 使用的阅读顺序，从 `0` 开始。
- `recognitionLanguages` 记录本次真正交给 Vision 的语言，而不是期望值。
- `plainText` 必须与 TXT 字节解码后的字符串完全一致。
- JSON 使用稳定键名和 `schemaVersion = 1`；修改或删除字段需要先修改规格。

## 6. Code Style

沿用现有小型值类型、明确错误和无第三方抽象的风格：

```swift
struct OCRObservation: Codable, Equatable {
    let index: Int
    let text: String
    let confidence: Float
    let boundingBox: OCRBoundingBox
}

let supported = Set(try request.supportedRecognitionLanguages())
request.recognitionLanguages = ["zh-Hans", "en-US"].filter(supported.contains)
```

- 类型使用 `UpperCamelCase`，函数和属性使用 `lowerCamelCase`。
- 可测试的坐标转换、排序和序列化逻辑保持为无副作用函数。
- 用户错误使用简体中文；不把识别出的文档正文写入控制台日志。
- 只在平台限制无法从代码自解释时写一行 `shortcut:` 注释。

## 7. Testing Strategy

### 自动测试

- 语言选择：只保留运行时支持的 `zh-Hans`、`en-US`，没有支持语言时返回明确错误。
- 坐标转换：Vision 左下角归一化框正确转换为左上角像素框。
- 阅读顺序：上方条目优先，同一高度时左侧优先；TXT 与 JSON 顺序一致。
- JSON：可解码，`schemaVersion`、源文件、尺寸、实际语言、置信度和坐标完整。
- 文件命名：OCR 文件与三份 PNG 共享时间戳且后缀正确。
- 文件失败隔离：OCR 文件组写入失败只清理 OCR 文件，不删除 PNG。
- 空结果：生成空 TXT、有效 JSON 和非错误状态。
- 合成图片冒烟测试：标准系统字体渲染的 `TEST 123` 能产生非空 Vision 结果；不对精确分词或置信度做脆弱断言。

### 真机测试

1. 使用真实中文试卷扫描，确认 TXT 可读、JSON 可解析且五份文件时间戳一致。
2. 测试中英混排、数字、标点、铅笔字和低对比度小字，并记录明显错字，不把“生成成功”视为“识别准确”。
3. 扫描纯图像或空白纸，确认空 OCR 输出不会导致扫描失败。
4. 人为制造 OCR 输出写入冲突，确认三份 PNG 保留且应用不崩溃。
5. 连续扫描 20 次，确认 UI 不冻结、无覆盖、无持续内存增长。

OCR 准确率本阶段不设虚假的固定百分比；先建立一组用户认可的真实样张基线，后续 `sr-experiment` 只允许与这组基线做同条件比较。

## 8. Boundaries

### Always do

- 先完成并确认 PNG 文件组，再开始 OCR。
- OCR 在现有后台处理队列执行，结束后再回到主线程更新 UI。
- 保存 TXT 与 JSON 时复用安全写入逻辑，不覆盖已有文件。
- 记录实际识别语言、位置和置信度，让结果可以复核。
- 提交前运行相关 XCTest；交付前运行完整 Swift 和 Python 测试。

### Ask first

- 增加语言选择界面、自定义词典或手写专项模式。
- 改变 JSON schema、阅读顺序规则或 OCR 输入版本。
- 增加 PDF、题目结构化、全文搜索、批量管理或自动拍摄。
- 引入第三方 OCR、Core ML、AI 模型或任何网络服务。

### Never do

- OCR 失败时删除、覆盖或将三份 PNG 标记为失败。
- 把识别结果、真实扫描件或设备信息上传网络或提交 Git。
- 把低置信度文字自动改写成“看起来合理”的内容。
- 用增强图或超分图替换原始矫正图作为本阶段唯一 OCR 基线。
- 在日志、崩溃信息或状态栏中显示整份试卷正文。

## 9. Risks and Trade-offs

1. **输入上限**：1920×1080 中缺失的细笔画无法由 OCR 恢复；支架构图、光线和对焦仍决定上限。
2. **阅读顺序**：简单位置排序可能错误处理多栏、表格和竖排内容；首版用 JSON 坐标保证可追溯，不扩张到版面分析。
3. **延迟**：`.accurate` 比快速模式耗时更长；扫描动作本就不是实时帧处理，优先准确率而不是帧率。
4. **错误可信度**：OCR 可能输出高置信度错字；因此原始 PNG 始终是事实来源，TXT 不能作为无复核的最终档案。
5. **隐私**：TXT 比图片更易被索引和复制；首版保持完全本地，并在 README 明示输出目录责任。

## 10. Success Criteria

- 一次成功扫描生成三份 PNG、一个 UTF-8 TXT 和一个符合 JSON v1 契约的 JSON，五份文件共享时间戳。
- 简体中文、英文、数字和常见标点能在真实样张中产生可阅读结果；错误可通过原图、置信度和坐标复核。
- OCR 没有文字、识别失败或 OCR 文件写入失败时，三份 PNG 均保留，应用不崩溃且状态说明下一步。
- OCR 完全在 Mac 本地完成，运行时不需要网络、Python 环境或新权限。
- 自动测试、20 次连续扫描及真实中文样张验收通过。

## 11. Open Questions

无。多栏版面、OCR 编辑和准确率目标必须基于第一批真实样张再决定，不在本模块预先扩张。
