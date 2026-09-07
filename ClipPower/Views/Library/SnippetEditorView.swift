import SwiftUI

struct SnippetEditorView: View {
    enum Mode {
        case create
        case edit(Snippet)
    }

    let mode: Mode
    /// 返回是否保存成功；成功后视图会自动关闭。
    let onSave: (SnippetDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var keyword: String
    @State private var content: String
    @State private var tagsText: String
    @State private var visibility: SnippetVisibility
    @State private var isSaving = false

    init(mode: Mode, onSave: @escaping (SnippetDraft) async -> Bool) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _keyword = State(initialValue: "")
            _content = State(initialValue: "")
            _tagsText = State(initialValue: "")
            _visibility = State(initialValue: .normal)
        case .edit(let snippet):
            _name = State(initialValue: snippet.name)
            _keyword = State(initialValue: snippet.keyword ?? "")
            _content = State(initialValue: snippet.plainContent ?? "")
            _tagsText = State(initialValue: snippet.tags.joined(separator: ", "))
            _visibility = State(initialValue: snippet.visibility)
        }
    }

    private var title: String {
        switch mode {
        case .create: return "新建片段"
        case .edit: return "编辑片段"
        }
    }

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)

            Form {
                TextField("标题", text: $name)
                TextField("触发词（选填）", text: $keyword)
                TextField("标签，用逗号分隔（选填）", text: $tagsText)

                Picker("可见性", selection: $visibility) {
                    ForEach(SnippetVisibility.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if visibility == .encryptedHidden {
                    Text("保存时会要求 Touch ID / 密码验证，内容将加密存储")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("内容").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $content)
                        .font(.body.monospaced())
                        .frame(minHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                }
            }

            HStack {
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(isSaving)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isNameValid || isSaving)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }

    private func save() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = SnippetDraft(
            name: name,
            keyword: trimmedKeyword.isEmpty ? nil : trimmedKeyword,
            content: content,
            tags: tags,
            visibility: visibility
        )

        isSaving = true
        Task {
            let success = await onSave(draft)
            isSaving = false
            if success {
                dismiss()
            }
        }
    }
}
