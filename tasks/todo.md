# Mac 单端本地增强高拍仪任务清单

状态：任务清单已批准（2026-10-09）

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
