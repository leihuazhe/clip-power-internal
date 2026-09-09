import SwiftUI

struct LibraryView: View {
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var trashViewModel: TrashViewModel
    @StateObject private var importExportViewModel: ImportExportViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    private enum SidebarItem: Hashable {
        case all
        case trash
        case settings
        case importExport
    }

    /// 用 `.sheet(item:)` 而不是 `.sheet(isPresented:)` + 单独的 `editingSnippet`，
    /// 因为后者在同一次状态更新里改两个 @State（isShowingEditor + editingSnippet）时，
    /// SwiftUI 有时会复用上一次呈现的 sheet 内容视图，导致"编辑"打开的还是上一次
    /// （或空白的新建）表单。`.sheet(item:)` 靠 id 变化强制重建视图，从根上避免这个问题。
    private enum EditorTarget: Identifiable {
        case create
        case edit(Snippet)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let snippet): return snippet.id
            }
        }
    }

    @State private var sidebarSelection: SidebarItem? = .all
    @State private var listSelection: String?
    @State private var editorTarget: EditorTarget?
    @State private var isShowingImportExport = false

    init(store: SnippetStore, clipboardHistoryStore: ClipboardHistoryStore) {
        let library = LibraryViewModel(store: store)
        _libraryViewModel = StateObject(wrappedValue: library)
        _trashViewModel = StateObject(wrappedValue: TrashViewModel(store: store, onChange: { [weak library] in
            library?.reload()
        }))
        _importExportViewModel = StateObject(wrappedValue: ImportExportViewModel(store: store, onImported: { [weak library] in
            library?.reload()
        }))
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(clipboardStore: clipboardHistoryStore))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Label("全部片段", systemImage: "doc.on.clipboard").tag(SidebarItem.all)
                Label("回收站", systemImage: "trash").tag(SidebarItem.trash)
                Label("导入/导出", systemImage: "square.and.arrow.up.on.square").tag(SidebarItem.importExport)
                Label("设置", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } content: {
            switch sidebarSelection {
            case .trash:
                TrashView(viewModel: trashViewModel)
            case .settings:
                SettingsView(viewModel: settingsViewModel)
            case .importExport:
                ImportExportView(viewModel: importExportViewModel, showsCloseButton: false)
            default:
                SnippetListView(
                    snippets: libraryViewModel.snippets,
                    selection: $listSelection,
                    searchText: $libraryViewModel.searchText
                )
            }
        } detail: {
            switch sidebarSelection {
            case .trash, .settings, .importExport:
                Color.clear
            default:
                if let id = listSelection, let snippet = libraryViewModel.snippets.first(where: { $0.id == id }) {
                    SnippetDetailView(
                        snippet: snippet,
                        libraryViewModel: libraryViewModel,
                        onEdit: {
                            editorTarget = .edit(snippet)
                        },
                        onDelete: {
                            libraryViewModel.softDelete(snippet)
                            listSelection = nil
                        }
                    )
                } else {
                    emptyDetailPlaceholder
                }
            }
        }
        .toolbar {
            if sidebarSelection != .settings && sidebarSelection != .importExport {
                ToolbarItem {
                    Button {
                        isShowingImportExport = true
                    } label: {
                        Label("导入/导出", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }
            if sidebarSelection == nil || sidebarSelection == .all {
                ToolbarItem {
                    Button {
                        editorTarget = .create
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingImportExport) {
            ImportExportView(viewModel: importExportViewModel)
        }
        .sheet(item: $editorTarget) { target in
            let existing: Snippet? = {
                if case .edit(let snippet) = target { return snippet }
                return nil
            }()
            SnippetEditorView(
                mode: existing.map { .edit($0) } ?? .create,
                onSave: { draft in
                    await libraryViewModel.save(draft: draft, existing: existing)
                }
            )
        }
        .alert("出错了", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(libraryViewModel.errorMessage ?? trashViewModel.errorMessage ?? "")
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("选择一个片段查看详情")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: {
                libraryViewModel.errorMessage != nil || trashViewModel.errorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    libraryViewModel.errorMessage = nil
                    trashViewModel.errorMessage = nil
                }
            }
        )
    }
}
