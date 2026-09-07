import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImportExportView: View {
    @ObservedObject var viewModel: ImportExportViewModel
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

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if viewModel.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func exportToFile() {
        Task {
            guard let data = await viewModel.export() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "clippower-export.json"
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
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
}
