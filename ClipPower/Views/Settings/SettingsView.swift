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
                permissionRow(
                    title: "辅助功能",
                    granted: viewModel.isAccessibilityGranted,
                    requestAction: viewModel.requestAccessibilityPermission,
                    openSettingsAction: viewModel.openAccessibilitySettings
                )
                permissionRow(
                    title: "输入监控",
                    granted: viewModel.isInputMonitoringGranted,
                    requestAction: viewModel.requestInputMonitoringPermission,
                    openSettingsAction: viewModel.openInputMonitoringSettings
                )
                Button("刷新权限状态") {
                    viewModel.refreshPermissionStatus()
                }
            } header: {
                Label("权限", systemImage: "hand.raised.fill")
            } footer: {
                Text("两项权限都需要授权，keyword 自动展开和模拟粘贴才能正常工作。系统授权弹窗里点允许后这里不会自动更新，请点上面的「刷新权限状态」；输入监控还可能需要重启 Clip Power 才会真正生效。")
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
                LabeledContent("移动当前窗口到下一个屏幕") {
                    KeyboardShortcuts.Recorder(for: .moveFrontmostWindowToNextScreen)
                }
                LabeledContent("移动当前窗口到上一个屏幕") {
                    KeyboardShortcuts.Recorder(for: .moveFrontmostWindowToPreviousScreen)
                }
            } header: {
                Label("全局快捷键", systemImage: "keyboard")
            } footer: {
                Text("面板打开时按 ⇥ 可以在「片段」和「剪贴板历史」两个标签之间切换。「移动当前窗口到上一个/下一个屏幕」按屏幕从左到右的物理顺序循环切换：全屏窗口会退出全屏、挪过去再重新全屏（1-2 秒动画，部分应用重新进入全屏可能不生效，跟具体应用有关），非全屏窗口直接原样搬过去；都需要辅助功能权限，只有 1 块屏幕时不会有反应。")
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
        .onAppear {
            viewModel.reload()
            viewModel.refreshPermissionStatus()
        }
        .alert("语言已更改", isPresented: $viewModel.pendingLanguageRestart) {
            Button("现在重启") { viewModel.restartNow() }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("需要重启 ClipPower 才能生效。")
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: LocalizedStringKey,
        granted: Bool,
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Label(
                    granted ? "已授权" : "未授权",
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(granted ? .green : .orange)
                .font(.caption)

                if !granted {
                    Button("请求授权") { requestAction() }
                    Button("前往系统设置") { openSettingsAction() }
                }
            }
        }
    }
}
