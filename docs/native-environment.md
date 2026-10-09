# 原生高拍仪开发环境

验证日期：2026-10-09

## 主机与工具链

- Mac：Apple Silicon arm64，M2 Pro。
- macOS：15.7.3。
- Xcode：26.3，build 17C529。
- Swift：6.2.4。
- macOS SDK：26.2。
- Developer 目录：`/Applications/Xcode.app/Contents/Developer`。
- Swift 路径：`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift`。
- SDK 路径：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk`。
- `xcodebuild -checkFirstLaunchStatus`：通过。

## 连续互通声明核验

Xcode 26.3 的 `AVCaptureDevice.h` 明确要求：macOS 14.0 起，应用需要在 `Info.plist` 中加入以下键，才能让连续互通摄像头以 `.continuityCamera` 类型报告：

```xml
<key>NSCameraUseContinuityCameraDeviceType</key>
<true/>
```

SDK 证据位置：

```text
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AVFoundation.framework/Versions/A/Headers/AVCaptureDevice.h
```

工程仍需配置 `NSCameraUsageDescription`，并以 macOS 15 为最低部署目标，避免无意使用仅 macOS 26 可用的 API。

## 复核命令

```bash
xcode-select -p
xcodebuild -version
swift --version
xcrun --find swift
xcrun --sdk macosx --show-sdk-version
xcrun --sdk macosx --show-sdk-path
xcodebuild -checkFirstLaunchStatus
```
