import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var outputDirectory: URL?

    var body: some View {
        VStack(spacing: 14) {
            PreviewView(
                session: camera.captureSession,
                quadrilateral: camera.documentQuadrilateral
            )
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topLeading) {
                Text("实时画面 \(camera.previewSize)")
                    .font(.caption.monospacedDigit())
                    .padding(7)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                    .padding(10)
            }
            .frame(minHeight: 480)

            HStack(spacing: 12) {
                Circle()
                    .fill(camera.hasDocumentCandidate ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(camera.statusMessage)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("选择保存目录") {
                    selectOutputDirectory()
                }

                Text(outputDirectory?.path ?? "尚未选择保存目录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                Button(camera.isProcessing ? "处理中…" : "扫描") {
                    scan()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: [])
                .disabled(!canScan)

                Button("使用空格扫描") {
                    scan()
                }
                .keyboardShortcut(.space, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
                .disabled(!canScan)
            }
        }
        .padding(18)
        .frame(minWidth: 920, minHeight: 680)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var canScan: Bool {
        camera.isReady &&
            camera.hasDocumentCandidate &&
            !camera.isProcessing &&
            outputDirectory != nil
    }

    private func scan() {
        guard let outputDirectory else { return }
        camera.scan(to: outputDirectory)
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择扫描文件保存目录"
        panel.prompt = "选择目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }
}
