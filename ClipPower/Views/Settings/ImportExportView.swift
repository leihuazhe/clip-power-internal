import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImportExportView: View {
    @ObservedObject var viewModel: ImportExportViewModel
    /// 侧栏常驻展示时没有"关闭"的意义（不是弹出的 sheet），设为 false 隐藏按钮。
    var showsCloseButton: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入 / 导出").font(.headline)

            GroupBox("导出") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("包含软隐藏片段", isOn: $viewModel.includeSoftHidden)
                    Toggle("包含加密隐藏片段", isOn: $viewModel.includeEncryptedHidden)
                    if viewModel.includeEncryptedHidden {
                        SecureField("导出密码（留空则加密内容仅本机可用）", text: $viewModel.exportPassword)
                    }
                    Button("选择位置并导出...") { exportToFile() }
                        .disabled(viewModel.isBusy)
                }
                .padding(8)
            }

            GroupBox("导入") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("冲突处理", selection: $viewModel.conflictPolicy) {
                        ForEach(ImportConflictPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    SecureField("导入密码（若导出时设置了密码）", text: $viewModel.importPassword)
                    Button("选择文件并导入...") { importFromFile() }
                        .disabled(viewModel.isBusy)
                }
                .padding(8)
            }

            GroupBox("与 Raycast 互通") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raycast 官方 Snippets JSON 格式为 [{ name, text, keyword }]，没有可见性/加密概念。导入时全部落库为公开可见性；导出时只包含公开（未隐藏）片段——软隐藏/加密隐藏的内容不会被导出成这种没有任何保护的明文格式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("选择 Raycast Snippets 文件导入...") { importFromRaycastFile() }
                        .disabled(viewModel.isBusy)
                    Button("导出为 Raycast 格式...") { exportToRaycastFile() }
                        .disabled(viewModel.isBusy)
                }
                .padding(8)
            }

            HStack {
                if viewModel.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if showsCloseButton {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .topLeading)
        .alert("导入/导出结果", isPresented: statusAlertBinding) {
            Button("好") {}
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.statusMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.statusMessage = nil
                }
            }
        )
    }

    private func exportToFile() {
        Task {
            guard let data = await viewModel.export() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "clippower-export.json"
            // 用户点 Cancel 就什么都不提示；只有真的选好位置并写盘成功后才算"导出成功"。
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                viewModel.statusMessage = String(localized: "导出成功")
            } catch {
                viewModel.statusMessage = localizedFormat("exportFailedFormat", error.localizedDescription)
            }
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        Task {
            await viewModel.importFile(data: data)
        }
    }

    private func importFromRaycastFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        Task {
            await viewModel.importRaycastFile(data: data)
        }
    }

    private func exportToRaycastFile() {
        Task {
            guard let data = await viewModel.exportRaycastFile() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "clippower-raycast-export.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                viewModel.statusMessage = String(localized: "已导出为 Raycast 格式")
            } catch {
                viewModel.statusMessage = localizedFormat("exportFailedFormat", error.localizedDescription)
            }
        }
    }
}
