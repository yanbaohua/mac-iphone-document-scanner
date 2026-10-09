# Mac / iPhone 高拍仪

当前开发版是 macOS 原生单端 App：通过连续互通相机读取 iPhone 1920×1080 实时画面，用 Vision 追踪文档，在 Mac 上选择近期最清晰帧，完成透视校正、本地增强和离线文字识别。

Python/OpenCV 版仍保留，已归档为 `v1.0.0`。

## 原生版（当前开发）

### 功能边界

- 只连接 iPhone 连续互通相机，不回退到 Mac 内置摄像头。
- 实时显示文档绿框，分析最多 5 FPS，缓存最近 8 个合格候选帧。
- 每次扫描先保存三份无损 PNG：`_original`（仅校正）、`_color`（彩色增强）、`_gray`（灰度增强）。
- PNG 保存成功后，使用 Apple Vision 在 Mac 本地识别简体中文和英文，并输出 `_ocr.txt` 与 `_ocr.json`。
- OCR 失败不会删除三份 PNG；应用会提示“图像已保存，但 OCR 失败”。
- 不插值放大，不声称 4K 或 iPhone 相机 App 原生照片画质。

### 一次扫描的输出

```text
scan_yyyyMMdd_HHmmss_SSSSSS_original.png
scan_yyyyMMdd_HHmmss_SSSSSS_color.png
scan_yyyyMMdd_HHmmss_SSSSSS_gray.png
scan_yyyyMMdd_HHmmss_SSSSSS_ocr.txt
scan_yyyyMMdd_HHmmss_SSSSSS_ocr.json
```

TXT 是按文字框位置从上到下、同高度从左到右排列的 UTF-8 文本。JSON 保留源图尺寸、实际识别语言、每条文字的置信度和左上角像素坐标；它适合复核和后续工具处理。当前排序不保证正确还原多栏、表格或竖排版面，OCR 也可能产生高置信度错字，原始校正 PNG 始终是事实来源。

### 构建与运行

1. Mac 与 iPhone 登录同一 Apple 账户，开启 Wi-Fi、蓝牙和 iPhone 的“连续互通相机”。
2. 用 Xcode 打开 `NativeScanner/NativeScanner.xcodeproj`。
3. 选择 `NativeScanner` scheme 和“My Mac”，按 `Command-R`。
4. 允许相机权限，让纸张四个角都进入画面，等待绿框稳定。
5. 选择保存目录，点击“扫描”，或按 `S` / 空格；等待状态栏显示 OCR 条目数量或失败原因。

命令行自检：

```bash
xcodebuild -project NativeScanner/NativeScanner.xcodeproj \
  -scheme NativeScanner \
  -destination 'platform=macOS' \
  -derivedDataPath NativeScanner/build test
```

原生版的实测记录见 [`docs/native-validation.md`](docs/native-validation.md)。

## Python/OpenCV 归档版

### 准备

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

首次运行时，macOS 会请求终端使用摄像头的权限。如果刚修改过权限，请完全退出并重新打开终端。

### 运行

```bash
python scanner.py --camera 0
```

只有在系统已经显示多个摄像头、且索引 `0` 是 Mac 内置摄像头时，才改用 `--camera 1`。预览窗口需要保持聚焦；按 `s` 扫描，按 `q` 退出。扫描结果保存到 `scanned_docs/`，可用 `--output 路径` 更改。

程序会请求较高的输入分辨率，但最终分辨率由 macOS 连续互通相机实际提供。启动日志中的“实际画面”才是有效值；本版本不保证 4K，也不等同于 iPhone 相机 App 的原生照片画质。

若终端出现 `AVCaptureDeviceTypeExternal is deprecated for Continuity Cameras`，这是 OpenCV 当前调用 AVFoundation 时产生的兼容性警告；只要预览和保存正常，它不会影响使用。

### 摄像头无法打开

1. 打开“系统设置 → 隐私与安全性 → 相机”，允许当前终端访问摄像头，然后完全退出并重新打开终端。
2. 打开 FaceTime，检查“视频”菜单中是否能选择 iPhone。
3. 确认两台设备使用启用双重认证的同一 Apple 账户，并开启 Wi-Fi、蓝牙和连续互通相机。
4. iPhone 重启后至少解锁一次，再将其锁定、靠近 Mac、稳定安装且后置镜头无遮挡。
5. 关闭正在占用摄像头的 FaceTime 等应用。

日志 `out device of bound (0-0): 1` 表示当前只有索引 `0`，此时索引 `1` 无效。

### 自检

```bash
python -m unittest -v
```

## 隐私与归档

`scanned_docs/`、`.venv/`、`NativeScanner/build/` 和 macOS 临时文件已被 Git 忽略。原生版的图像和 OCR 均只写入用户当次选择的本地目录，不使用网络服务。

TXT/JSON 比图片更容易被系统搜索和复制。请不要把输出目录放在会自动同步或提交 Git 的位置；推送前仍应使用 `git status` 检查暂存内容，避免试卷、识别文字或其他个人文档泄露。
