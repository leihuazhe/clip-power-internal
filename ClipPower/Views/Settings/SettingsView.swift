import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置").font(.headline)

            GroupBox("全局快捷键") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("打开片段面板")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleSnippetsPanel)
                    }
                    HStack {
                        Text("打开剪贴板历史")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleClipboardHistoryPanel)
                    }
                }
                .padding(8)
            }

            GroupBox("剪贴板历史") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已记录 \(viewModel.clipboardHistoryCount) 条")
                        .foregroundStyle(.secondary)
                    Button("清空剪贴板历史", role: .destructive) {
                        viewModel.clearClipboardHistory()
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 300)
    }
}
