# Mac 单端本地增强高拍仪任务清单

状态：核心任务清单已批准；`ocr-export` 任务清单待批准（2026-10-09）

## 已完成基础

- [x] Task 1：完整 Xcode 工具链与环境记录。
- [x] Task 2：最小签名 macOS 工程、相机权限和沙箱配置。
- [x] Task 3：连续互通真机探针；确认实际上限为 1920×1080。
- [x] 决策：接受 1080p，继续 Mac 单端本地增强路线。

## Task 4：文档处理与清晰度评分

**Acceptance:**

- [x] 可测试的清晰度评分能区分纯色与高边缘图。
- [x] Vision 检测和坐标转换返回正确文档四角。
- [x] 透视输出不插值放大。
- [x] 生成原始矫正、彩色增强和灰度增强三种 PNG 数据。

**Verify:** `DocumentProcessorTests`

**Files:** `DocumentProcessor.swift`、`DocumentProcessorTests.swift`、工程文件。

## Task 5：实时预览、节流检测与稳定绿框

**Acceptance:**

- [x] 预览来自 `.continuityCamera`。
- [x] 视频输出丢弃迟到帧，分析不超过 5 FPS且不并发积压。
- [x] 只缓存最近 8 个合格候选帧。
- [x] 文档可见时显示绿框，短暂丢失最多保留 0.5 秒。

**Verify:** 构建、已有 XCTest、真机移动/倾斜/遮挡测试。

**Files:** `CameraController.swift`、`PreviewView.swift`、`ContentView.swift`、相关测试、工程文件。

## Task 6：最佳帧扫描与三份 PNG 保存

**Acceptance:**

- [x] 扫描选择近期合格候选中清晰度最高的一帧。
- [x] 同一时间戳保存 `_original.png`、`_color.png`、`_gray.png`。
- [x] 原子写入且不覆盖已有文件；失败时显示明确错误。
- [x] 成功状态显示目录和真实输出尺寸。

**Verify:** 命名/状态 XCTest、Finder 人工打开输出。

**Files:** `CameraController.swift`、`DocumentProcessor.swift`、`ContentView.swift`、相关测试。

## Task 7：交互与故障恢复

**Acceptance:**

- [x] 支持按钮、`S`、空格扫描和标准 `Command-Q`。
- [x] 无权限、无 iPhone、未选目录、无候选帧、处理中和断连不会误操作。
- [x] 文案为简体中文并给出下一步操作。

**Verify:** 状态 XCTest 和权限/断连人工测试。

## Task 8：真机回归与交付

**Acceptance:**

- [ ] 20 次连续扫描无崩溃、覆盖和明显持续内存增长。
- [ ] 小字、铅笔字、图表的增强结果经用户样张确认。
- [x] Swift 构建、XCTest 和 Python 测试全部通过。
- [x] README、限制和真机验证记录准确。
- [ ] Git 不含扫描件、设备标识、签名资料或构建产物。

**Verify:** 完整构建/测试、真机清单、Git 暂存检查。

---

## `ocr-export` 扩展

规格：[SPEC-ocr-export.md](../SPEC-ocr-export.md)
计划：[plan.md](plan.md)

## Task 9：OCR 内存结果与数据契约

**Description:** 新增一个直接调用 Apple Vision 的 `OCRProcessor`，从原始矫正 PNG 生成有确定顺序的 TXT 数据和 JSON v1 数据；先完成纯内存路径，不接入扫描 UI 或文件写入。

**Acceptance criteria:**

- [x] 只使用运行时支持的 `zh-Hans`、`en-US`，以 `.accurate` 和语言修正执行 OCR；没有可用语言或图片无法解码时返回简体中文错误。
- [x] Vision 文字框转换为左上角像素坐标并按 `y`、`x` 稳定排序；每条结果保留最高候选文字和置信度。
- [x] TXT 与 JSON v1 的文本和顺序一致；空结果生成空 TXT 和有效 JSON，合成 `TEST 123` 图片产生非空结果。

**Verification:**

- [x] Tests pass:
  `xcodebuild -project NativeScanner/NativeScanner.xcodeproj -scheme NativeScanner -configuration Debug -destination 'platform=macOS' -derivedDataPath NativeScanner/build test -only-testing:NativeScannerTests/OCRProcessorTests`
- [x] Build succeeds:
  `xcodebuild -project NativeScanner/NativeScanner.xcodeproj -scheme NativeScanner -configuration Debug -destination 'platform=macOS' -derivedDataPath NativeScanner/build build`

**Dependencies:** 已完成的 Task 4 和 Task 6 输出契约；不依赖未完成的 Task 8。

**Files likely touched:**

- `NativeScanner/NativeScanner/OCRProcessor.swift`
- `NativeScanner/NativeScannerTests/OCRProcessorTests.swift`
- `NativeScanner/NativeScanner.xcodeproj/project.pbxproj`

**Estimated scope:** Medium，3 个文件。

## Checkpoint O1：纯 OCR 核心

- [x] `OCRProcessorTests` 全部通过，应用构建成功。
- [x] 未修改相机、预览、文档检测和增强参数。
- [x] 人工检查 JSON 样例与规格中的 v1 字段完全一致。

## Task 10：接入扫描保存与失败隔离

**Description:** 在现有三 PNG 文件组成功保存后自动运行 OCR，用同一时间戳写入 `_ocr.txt` 和 `_ocr.json`；把 PNG 和 OCR 分成两个事务，并为成功、空结果和 OCR 失败提供明确状态。

**Acceptance criteria:**

- [ ] 一次正常扫描生成同时间戳的三份 PNG、TXT 和 JSON，状态显示真实图像尺寸和 OCR 条目数量；无文字时显示非错误提示。
- [x] OCR 识别或任一 OCR 文件写入失败时，只清理本次 TXT/JSON，三份 PNG 保留且应用结束处理中状态。
- [x] 五份文件均使用现有原子且不覆盖的安全写入方式；应用不记录或显示整份 OCR 正文。

**Verification:**

- [x] Focused tests pass:
  `xcodebuild -project NativeScanner/NativeScanner.xcodeproj -scheme NativeScanner -configuration Debug -destination 'platform=macOS' -derivedDataPath NativeScanner/build test -only-testing:NativeScannerTests/OCRProcessorTests -only-testing:NativeScannerTests/CaptureConfigurationTests`
- [x] Full XCTest passes:
  `xcodebuild -project NativeScanner/NativeScanner.xcodeproj -scheme NativeScanner -configuration Debug -destination 'platform=macOS' -derivedDataPath NativeScanner/build test`
- [ ] Manual check: 正常样张和空白页均能完成扫描；文件冲突的失败隔离由可控路径的自动测试验证。

**Dependencies:** Task 9。

**Files likely touched:**

- `NativeScanner/NativeScanner/CameraController.swift`
- `NativeScanner/NativeScanner/OCRProcessor.swift`
- `NativeScanner/NativeScannerTests/CaptureConfigurationTests.swift`

**Estimated scope:** Medium，3 个文件。

## Checkpoint O2：完整保存闭环

- [ ] 正常扫描生成五份可打开或解析的文件。
- [ ] 空白页生成空 TXT 和有效 JSON，不被判定为扫描失败。
- [ ] OCR 失败保留三份 PNG，窗口保持运行且可以继续下一次扫描。

## Task 11：文档与完整真机验收

**Description:** 更新用户说明和版本记录，执行所有自动测试，并把 OCR 真机验证与原 Task 8 的画质、隐私和 20 次连续扫描检查合并完成。

**Acceptance criteria:**

- [ ] README 和 CHANGELOG 准确说明五份输出、本地处理、JSON 坐标、阅读顺序限制和隐私风险。
- [ ] 真实中英混排试卷的 TXT 可读、JSON 可解析；明显错字、铅笔字和多栏顺序限制记录在验证文档中，不虚报准确率。
- [ ] 连续扫描 20 次无崩溃、覆盖或明显持续内存增长，Git 不包含扫描件、设备信息、签名资料和构建产物。

**Verification:**

- [ ] Swift tests pass:
  `xcodebuild -project NativeScanner/NativeScanner.xcodeproj -scheme NativeScanner -configuration Debug -destination 'platform=macOS' -derivedDataPath NativeScanner/build test`
- [ ] Python regression passes:
  `.venv/bin/python -m unittest -v`
- [ ] Manual check: Finder 打开三份 PNG，文本编辑器打开 TXT，`python3 -m json.tool <输出文件.json>` 验证 JSON，并完成 20 次真机扫描清单。
- [ ] Repository check: `git status --short --ignored` 不出现未忽略的扫描件、签名资料或构建产物。

**Dependencies:** Task 10；与原 Task 8 合并验收。

**Files likely touched:**

- `README.md`
- `CHANGELOG.md`
- `docs/native-validation.md`

**Estimated scope:** Medium，3 个文件。

## Checkpoint O3：`ocr-export` 完成

- [ ] Task 9–11 的验收项全部完成。
- [ ] Swift 构建、XCTest 和 Python 回归全部通过。
- [ ] 真实中文样张已由用户复核，原始 PNG 仍是事实来源。
- [ ] `ocr-export` 可以独立回退，不影响既有三 PNG 扫描流程。
