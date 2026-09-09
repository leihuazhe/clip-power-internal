import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("语言", selection: $viewModel.selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: viewModel.selectedLanguage) { newValue in
                    viewModel.languageDidChange(to: newValue)
                }
            } header: {
                Label("语言", systemImage: "globe")
            } footer: {
                Text("切换语言需要重启 ClipPower 才能生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("打开 ClipPower") {
                    KeyboardShortcuts.Recorder(for: .toggleClipPowerPanel)
                }
                LabeledContent("直接打开「片段」") {
                    KeyboardShortcuts.Recorder(for: .toggleSnippetsPanel)
                }
                LabeledContent("直接打开「剪贴板历史」") {
                    KeyboardShortcuts.Recorder(for: .toggleClipboardHistoryPanel)
                }
            } header: {
                Label("全局快捷键", systemImage: "keyboard")
            } footer: {
                Text("面板打开时按 ⇥ 可以在「片段」和「剪贴板历史」两个标签之间切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("已记录条数", value: "\(viewModel.clipboardHistoryCount)")
                Button("清空剪贴板历史", role: .destructive) {
                    viewModel.clearClipboardHistory()
                }
            } header: {
                Label("剪贴板历史", systemImage: "doc.on.clipboard")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560)
        .onAppear { viewModel.reload() }
        .alert("语言已更改", isPresented: $viewModel.pendingLanguageRestart) {
            Button("现在重启") { viewModel.restartNow() }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("需要重启 ClipPower 才能生效。")
        }
    }
}
