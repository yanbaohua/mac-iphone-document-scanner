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
