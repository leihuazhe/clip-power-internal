import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var libraryWindowController: LibraryWindowController?

    private var panelController: ClipPowerPanelController?
    private var panelViewModel: ClipPowerPanelViewModel?
    private var clipboardMonitor: ClipboardMonitor?
    private var keywordIndex: KeywordIndex?
    private var textExpansionMonitor: TextExpansionMonitor?
    private var lastToggleAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IONBF, 0) // 关闭 stdout 缓冲，终端直跑时能实时看到 print 日志

        // 真正的首次启动（还没存过语言偏好）：不跟随系统语言，默认英语。写完偏好立刻
        // 静默重启一次再退出——避免用户看到"第一帧是系统语言，之后才变成英文"这种
        // 一次性的突兀体验；本次进程后面的 UI 搭建全部跳过，交给重启后的新进程。
        if !AppLanguageManager.hasStoredPreference && !AppLanguageManager.isRunningTests {
            AppLanguageManager.apply(.en)
            AppLanguageManager.relaunch()
            return
        }

        _ = AppEnvironment.snippetStore // 触发数据库初始化与迁移
        try? AppEnvironment.snippetStore.purgeExpiredTrash()

        setupStatusItem()
        setupClipPowerPanel()
        setupTextExpansion()
        ensureAccessibilityPermission()
        openLibrary()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clip Power"
        )

        let openItem = NSMenuItem(title: String(localized: "打开管理窗口"), action: #selector(openLibrary), keyEquivalent: "")
        openItem.target = self

        let quitItem = NSMenuItem(title: String(localized: "退出 Clip Power"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let menu = NSMenu()
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func setupClipPowerPanel() {
        let monitor = ClipboardMonitor(store: AppEnvironment.clipboardHistoryStore)
        monitor.start()
        clipboardMonitor = monitor

        let snippetsViewModel = QuickPanelViewModel(store: AppEnvironment.snippetStore)
        let clipboardHistoryViewModel = ClipboardHistoryViewModel(store: AppEnvironment.clipboardHistoryStore)
        let viewModel = ClipPowerPanelViewModel(
            snippetsViewModel: snippetsViewModel,
            clipboardHistoryViewModel: clipboardHistoryViewModel
        )
        let controller = ClipPowerPanelController(viewModel: viewModel)

        snippetsViewModel.onPaste = { [weak self, weak controller] text, method in
            controller?.dismiss()
            self?.performPasteAfterPanelCloses(text, method: method)
        }
        snippetsViewModel.onDismiss = { [weak controller] in
            controller?.dismiss()
        }
        clipboardHistoryViewModel.onPaste = { [weak self, weak controller] item in
            controller?.dismiss()
            self?.performPasteAfterPanelCloses(item)
        }
        clipboardHistoryViewModel.onDismiss = { [weak controller] in
            controller?.dismiss()
        }
        controller.onEscape = { [weak controller] in
            controller?.dismiss()
        }

        panelViewModel = viewModel
        panelController = controller

        GlobalHotkeyManager.shared.register(.toggleClipPowerPanel) { [weak self] in
            self?.togglePanel(defaultTab: .snippets)
        }
        GlobalHotkeyManager.shared.register(.toggleSnippetsPanel) { [weak self] in
            self?.togglePanel(defaultTab: .snippets)
        }
        GlobalHotkeyManager.shared.register(.toggleClipboardHistoryPanel) { [weak self] in
            self?.togglePanel(defaultTab: .clipboardHistory)
        }
    }

    private func setupTextExpansion() {
        let index = KeywordIndex(store: AppEnvironment.snippetStore)
        let monitor = TextExpansionMonitor(store: AppEnvironment.snippetStore, keywordIndex: index)
        monitor.start()
        keywordIndex = index
        textExpansionMonitor = monitor
    }

    /// 面板已打开且当前就在目标 Tab 上 → 关闭（维持"再按一次关闭"的习惯）；
    /// 面板已打开但在另一个 Tab 上 → 切换过去，不关闭；面板没打开 → 打开并定位到目标 Tab。
    private func togglePanel(defaultTab: ClipPowerPanelTab) {
        // 防抖：如果用户把两个热键绑到了同一个键位，系统会把一次按键同时投给两个
        // handler，短时间内连续调用两次 togglePanel 会变成"开了又立刻被关掉"，
        // 表现就是面板一闪而过。这里直接忽略过近的重复触发。
        let now = Date()
        if let lastToggleAt, now.timeIntervalSince(lastToggleAt) < 0.3 {
            return
        }
        lastToggleAt = now

        guard let controller = panelController, let viewModel = panelViewModel else { return }
        if controller.isVisible {
            if viewModel.activeTab == defaultTab {
                controller.dismiss()
            } else {
                viewModel.activeTab = defaultTab
            }
        } else {
            viewModel.present(defaultTab: defaultTab)
            controller.present()
        }
    }

    private func ensureAccessibilityPermission() {
        if !PermissionsManager.isAccessibilityGranted() {
            PermissionsManager.requestAccessibilityIfNeeded()
        }
    }

    /// 浮层用 `.nonactivatingPanel` 从未真正抢占前台，关闭后原 App 已经是前台；
    /// 留一点点延迟确保窗口系统状态切换完毕，再发送模拟粘贴按键。
    private func performPasteAfterPanelCloses(_ text: String, method: PasteMethod) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switch method {
            case .clipboard:
                PasteSimulator.paste(text)
            case .direct:
                PasteSimulator.typeDirectly(text)
            }
        }
    }

    private func performPasteAfterPanelCloses(_ item: ClipboardHistoryItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PasteSimulator.paste(item)
        }
    }

    @objc private func openLibrary() {
        if libraryWindowController == nil {
            libraryWindowController = LibraryWindowController(
                store: AppEnvironment.snippetStore,
                clipboardHistoryStore: AppEnvironment.clipboardHistoryStore
            )
        }
        libraryWindowController?.show()
    }
}
