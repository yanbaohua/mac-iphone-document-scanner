# Implementation Plan：Mac 单端本地增强高拍仪

状态：已批准（2026-10-09）

## Dependency Graph

```text
已完成：工具链、原生工程、连续互通能力探针
  └─ Task 4 文档处理与清晰度评分
       └─ Task 5 实时预览、节流检测与稳定绿框
            └─ Task 6 最佳帧扫描与三份 PNG 保存
                 └─ Task 7 错误恢复与快捷键
                      └─ Task 8 真机回归与交付文档
```

## Architecture Decisions

- 接受实测 1920×1080 上限，不再以传感器级分辨率作为 Go/No-Go。
- 仅使用 AVFoundation、Vision、Core Image 和 ImageIO，不增加依赖。
- 视频帧分析最多 5 FPS且单任务在途，缓存最近 8 个合格候选帧。
- 扫描选取候选帧中清晰度最高者；不做插值放大。
- 每次保存原始矫正、彩色增强和灰度增强三份 PNG。
- Python 版、标签和既有文件保持不变。

## Verification Checkpoints

### Checkpoint B1：纯处理

- 生成图片的清晰度、坐标、透视、三种输出和命名 XCTest 通过。
- 输出尺寸不超过输入文档的自然像素尺寸。

### Checkpoint B2：实时闭环

- 预览持续运行，检测不积压，绿框位置正确。
- 扫描能够选择合格候选帧并保存三份 PNG。
- 无候选帧、无目录、断连和处理中都有明确状态。

### Checkpoint B3：可交付

- Swift 构建、XCTest 和 Python 测试通过。
- 20 次真机扫描无崩溃、覆盖或明显持续内存增长。
- 样张确认小字、铅笔字和图表没有被过度增强破坏。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 1080p 对整张 A4 的细节有限 | High | 页面尽量填满画面；不夸大 DPI |
| Vision 或 Core Image 造成预览卡顿 | High | 5 FPS 节流、单请求在途、后台队列 |
| 候选帧占用内存 | Medium | 固定最多 8 帧，先进先出 |
| 锐化产生光晕或断笔 | Medium | 保守参数、保存原始矫正图、真机样张校准 |
| 坐标方向导致错误裁切 | High | 纯函数测试加真机横竖方向验证 |
| 输出目录权限失效 | Medium | 本次会话选择、安全作用域访问、明确错误 |

## Rollback

- 每个 Task 独立提交，可按任务回退。
- Python `v1.0.0` 始终可运行。
- 扫描件、设备标识和构建产物不进入 Git。

---

# Extension Plan：`ocr-export`

状态：已批准（2026-10-09）
规格：[SPEC-ocr-export.md](../SPEC-ocr-export.md)

## Overview

在现有三份 PNG 扫描闭环之后增加 Apple Vision 本地 OCR，并输出同时间戳的 UTF-8 TXT 与 JSON。图像保存和 OCR 是两个失败域：只有三份 PNG 全部保存后才启动 OCR；OCR 识别或文件写入失败不得回滚 PNG。

现有 Task 8 的真机画质与连续扫描验收保持原样，不因本扩展被关闭或覆盖。OCR 核心实现不依赖 Task 8 完成，但最终 OCR 真机验收与 Task 8 一并执行更省重复测试成本。

## Dependency Graph

```text
已完成：DocumentProcessor 生成 original/color/gray PNG 数据
  └─ Task 9 OCR 内存结果与数据契约
       └─ Task 10 扫描链路接入与失败隔离
            └─ Task 11 文档、完整回归与真实中文样张验收

并行保留：原 Task 8 真机画质/20 次连续扫描验收
```

## Architecture Decisions

- 新增单一 `OCRProcessor.swift`，直接使用 `VNRecognizeTextRequest`；不增加协议层、服务容器或第三方依赖。
- OCR 输入使用 `ProcessedDocument` 的 `original` PNG 数据解码结果，确保识别内容与用户保存的原始矫正图一致，也避免扩张 `DocumentProcessor` 的公开结果结构。
- 坐标转换、位置排序、语言交集和 JSON/TXT 生成设计为可独立测试的无副作用函数；Vision 调用只保留一层薄封装。
- 首先完成三份 PNG 的现有事务；随后单独执行 OCR 和两份 OCR 文件事务。OCR 事务失败只清理本次 OCR 文件。
- 复用 `writeAtomicallyWithoutOverwriting`，不新增第二套写盘实现。
- OCR 继续运行在现有后台处理队列；主线程只更新状态，避免扫描时冻结窗口。
- 不调整实时预览、文档检测、增强参数或相机权限，缩小回归面。

## Implementation Slices

### Task 9：OCR 内存结果与稳定数据契约

建立最小的 OCR 值类型、Vision 调用、语言选择、坐标转换、确定性排序及 TXT/JSON 编码，使一张原始矫正图能够在不接触文件系统和 UI 的情况下生成完整 OCR 文件数据。

**依赖：** 无新增依赖；使用现有 `DocumentProcessor` 输出契约。
**预计范围：** 中，2–3 个文件。
**验证关卡：** `OCRProcessorTests` 覆盖语言交集、坐标、排序、空结果、JSON 往返和合成英文图片冒烟测试；应用可构建。

### Task 10：接入扫描保存链路并隔离失败

在 `CameraController.process` 中保持现有 PNG 事务不变，确认 PNG 成功后调用 OCR，写入 `_ocr.txt` 与 `_ocr.json`，并分别呈现成功、空结果和 OCR 失败状态。通过测试证明 OCR 失败不会删除 PNG。

**依赖：** Task 9。
**预计范围：** 中，3–4 个文件。
**验证关卡：** 文件名、同时间戳、禁止覆盖和 OCR 事务清理测试通过；完整 XCTest 通过；既有扫描按钮路径可构建。

### Task 11：文档、完整回归与真机验收

更新 README 和 CHANGELOG，运行 Swift/Python 全量测试，并用真实中英混排试卷检查五份输出、可读性、错误可追溯性和连续扫描稳定性。

**依赖：** Task 10。
**预计范围：** 小，2 个文档文件及本地验收记录。
**验证关卡：** 全量测试通过；真实样张 JSON 可解析、TXT 可读；20 次扫描不崩溃、不覆盖、无明显持续内存增长；Git 不包含扫描件。

## Verification Checkpoints

### Checkpoint O1：纯 OCR 核心

- 语言、坐标、排序、TXT 和 JSON 契约测试通过。
- 合成英文图像能得到非空 Vision 结果。
- 没有修改相机、预览和现有图像增强行为。

### Checkpoint O2：完整保存闭环

- 一次扫描正常生成同时间戳的三份 PNG、TXT 和 JSON。
- 空白页得到空 TXT 和有效 JSON，不被当作扫描失败。
- OCR 请求或 OCR 文件写入失败时三份 PNG 保留，界面给出明确状态。

### Checkpoint O3：可交付

- Swift 构建、XCTest 和 Python 测试全部通过。
- 真实中文样张完成复核，明确记录 OCR 错字和版面顺序限制。
- 原 Task 8 与 OCR 连续 20 次扫描验收合并完成。
- Git 状态确认没有扫描件、构建产物、设备信息或签名资料。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Vision 对 1080p 小字或铅笔字误识别 | High | 原始 PNG 始终为事实来源；JSON 保留置信度和坐标；真实样张建立基线 |
| 简单位置排序破坏多栏或表格顺序 | Medium | 首版明确只保证确定性顺序；保留所有文字框，暂不做版面分析 |
| `.accurate` OCR 增加扫描等待时间 | Medium | 仅在用户触发扫描后运行；保持后台处理；验收时记录实际耗时 |
| OCR 文件写入错误误删 PNG | High | PNG 和 OCR 使用两个独立事务；加入失败隔离测试 |
| 合成 OCR 测试受系统模型变化影响 | Medium | 冒烟测试只断言非空，不锁定分词和置信度；真实中文样张人工验收 |
| TXT 使文档更容易被系统索引 | Medium | 完全本地、用户选择目录、README 明示隐私责任，不写正文日志 |

## Resource and ROI Check

- 研发成本集中在一个处理文件、一次扫描编排接入和一组测试，不新增运行时、模型下载或维护服务。
- OCR 结果同时提供人读 TXT 和机器可用 JSON，直接为后续准确率比较提供基线；在此之前不投入超分辨率。
- 不建设语言设置、OCR 编辑器、PDF 和题目结构化，避免把扫描工具扩张成文档管理系统。

## Rollback

- 删除 `OCRProcessor.swift` 及其测试，并移除 `CameraController` 中 PNG 保存后的 OCR 调用，即可恢复现有三 PNG 行为。
- OCR 输出没有迁移或数据库状态；回滚不会影响既有扫描件。
- 每个实现切片独立提交，失败时优先回退当前切片而不是改动已稳定的图像处理链路。

## Open Questions

无。多栏版面处理、可配置语言和准确率目标留到真实样张基线之后评估。
