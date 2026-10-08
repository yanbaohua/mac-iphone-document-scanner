# Mac / iPhone 高拍仪

通过 macOS 连续互通相机读取 iPhone 画面，在 Mac 上实时预览文档边缘；按键后完成透视校正并保存灰度扫描图。

当前归档版本：`v1.0.0`。

## 准备

1. Mac 与 iPhone 登录同一 Apple ID，并打开 Wi-Fi、蓝牙和 iPhone 的“连续互通相机”。
2. 建议把 iPhone 固定在支架上，并在纸张下方放纯色深色垫。
3. 安装依赖：

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r requirements.txt
   ```

首次运行时，macOS 会请求终端使用摄像头的权限，请允许。如果刚修改过权限，请完全退出并重新打开终端。

## 运行

```bash
python scanner.py --camera 0
```

只有在系统已经显示多个摄像头、且索引 `0` 是 Mac 内置摄像头时，才改用：

```bash
python scanner.py --camera 1
```

预览窗口需要保持聚焦。按 `s` 扫描，按 `q` 退出。扫描结果以保留灰阶细节的无损 PNG 保存到 `scanned_docs/`；可用 `--output 路径` 更改。

程序会请求较高的输入分辨率，但最终分辨率由 macOS 连续互通相机实际提供。启动日志中的“实际画面”才是有效值；本版本不保证 4K，也不等同于 iPhone 相机 App 的原生照片画质。若需要原生照片级清晰度，应使用后续的 macOS 原生采集方案，而不是放大当前视频帧。

若终端出现 `AVCaptureDeviceTypeExternal is deprecated for Continuity Cameras`，这是 OpenCV 当前调用 AVFoundation 时产生的兼容性警告；只要预览和保存正常，它不会影响本版本使用。

## 摄像头无法打开

按以下顺序排查，不要盲目增加索引：

1. 打开“系统设置 → 隐私与安全性 → 相机”，允许当前使用的终端应用访问摄像头，然后完全退出并重新打开终端。
2. 打开 FaceTime，检查“视频”菜单中是否能选择 iPhone。若这里没有 iPhone，Python 也无法打开它。
3. 若 FaceTime 没有显示 iPhone：确认两台设备使用启用双重认证的同一 Apple 账户，并开启 Wi-Fi、蓝牙和 iPhone“设置 → 通用 → 隔空播放与连续互通 → 连续互通相机”。
4. iPhone 重启后至少解锁一次，然后将其锁定、靠近 Mac、稳定安装且后置镜头无遮挡；仍无效时用 USB 连接并在 iPhone 上信任 Mac。
5. 关闭正在占用摄像头的 FaceTime 等应用，再运行 `python scanner.py --camera 0`。

日志 `out device of bound (0-0): 1` 表示当前只有索引 `0`，此时索引 `1` 无效。

## 自检

```bash
python -m unittest -v
```

此版本使用画面中面积最大的显著四边形作为纸张。纸张卷边、边缘被遮挡、桌沿入镜或纸张与背景接近时，识别会失败；优先调整支架、光线和背景，而不是盲目修改阈值。

## 隐私与归档

`scanned_docs/`、`.venv/` 和 macOS 临时文件已被 Git 忽略，不会进入仓库。推送前仍应使用 `git status` 检查暂存内容，避免试卷或其他个人文档泄露。
