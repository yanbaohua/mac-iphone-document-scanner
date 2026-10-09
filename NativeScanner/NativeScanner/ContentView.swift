import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var outputDirectory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundStyle(camera.isReady ? .green : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("原生高清照片探针")
                        .font(.title2.bold())
                    Text("仅使用 iPhone 连续互通相机，不回退到 Mac 内置摄像头。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("当前状态") {
                Text(camera.statusMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }

            HStack {
                Button("连接 iPhone 相机") {
                    camera.start()
                }

                Button("选择保存目录") {
                    selectOutputDirectory()
                }

                Button(camera.isCapturing ? "拍摄中…" : "拍摄一张原始照片") {
                    guard let outputDirectory else { return }
                    camera.capture(to: outputDirectory)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!camera.isReady || camera.isCapturing || outputDirectory == nil)
            }

            Text("保存目录：\(outputDirectory?.path ?? "未选择")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            GroupBox("设备与照片日志（设备标识仅显示在本次运行）") {
                ScrollView {
                    Text(camera.logLines.isEmpty ? "连接后将显示设备、支持尺寸、请求值与实际输出。" : camera.logLines.joined(separator: "\n"))
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 180)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 520)
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择原始高清照片的保存目录"
        panel.prompt = "选择目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }
}
