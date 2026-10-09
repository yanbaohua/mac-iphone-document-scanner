import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("原生高清高拍仪")
                .font(.title2.bold())

            Text("开发环境已就绪，下一步验证 iPhone 连续互通相机的静态照片尺寸。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(minWidth: 640, minHeight: 420)
    }
}
