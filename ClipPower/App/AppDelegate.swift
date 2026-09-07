import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var libraryWindowController: LibraryWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var snippetsPanelController: QuickPanelController?
    private var snippetsPanelViewModel: QuickPanelViewModel?

    private var clipboardHistoryPanelController: ClipboardHistoryPanelController?
    private var clipboardHistoryViewModel: ClipboardHistoryViewModel?
    private var clipboardMonitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppEnvironment.snippetStore // 触发数据库初始化与迁移
        try? AppEnvironment.snippetStore.purgeExpiredTrash()

        setupStatusItem()
        setupSnippetsPanel()
        setupClipboardHistory()
        openLibrary()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clip Power"
        )

        let openItem = NSMenuItem(title: "打开管理窗口", action: #selector(openLibrary), keyEquivalent: "")
        openItem.target = self

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let quitItem = NSMenuItem(title: "退出 Clip Power", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let menu = NSMenu()
        menu.addItem(openItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func setupSnippetsPanel() {
        let viewModel = QuickPanelViewModel(store: AppEnvironment.snippetStore)
        let controller = QuickPanelController(viewModel: viewModel)

        viewModel.onPaste = { [weak self, weak controller] text in
            controller?.dismiss()
            self?.performPasteAfterPanelCloses(text)
        }
        viewModel.onDismiss = { [weak controller] in
            controller?.dismiss()
        }
        controller.onEscape = { [weak controller] in
            controller?.dismiss()
        }

        snippetsPanelViewModel = viewModel
        snippetsPanelController = controller

        GlobalHotkeyManager.shared.register(.toggleSnippetsPanel) { [weak self] in
            self?.toggleSnippetsPanel()
        }
    }

    private func setupClipboardHistory() {
        let monitor = ClipboardMonitor(store: AppEnvironment.clipboardHistoryStore)
        monitor.start()
        clipboardMonitor = monitor

        let viewModel = ClipboardHistoryViewModel(store: AppEnvironment.clipboardHistoryStore)
        let controller = ClipboardHistoryPanelController(viewModel: viewModel)

        viewModel.onPaste = { [weak self, weak controller] text in
            controller?.dismiss()
            self?.performPasteAfterPanelCloses(text)
        }
        viewModel.onDismiss = { [weak controller] in
            controller?.dismiss()
        }
        controller.onEscape = { [weak controller] in
            controller?.dismiss()
        }

        clipboardHistoryViewModel = viewModel
        clipboardHistoryPanelController = controller

        GlobalHotkeyManager.shared.register(.toggleClipboardHistoryPanel) { [weak self] in
            self?.toggleClipboardHistoryPanel()
        }
    }

    private func toggleSnippetsPanel() {
        guard let controller = snippetsPanelController else { return }
        if controller.isVisible {
            controller.dismiss()
        } else {
            clipboardHistoryPanelController?.dismiss()
            ensureAccessibilityPermission()
            snippetsPanelViewModel?.reset()
            controller.present()
        }
    }

    private func toggleClipboardHistoryPanel() {
        guard let controller = clipboardHistoryPanelController else { return }
        if controller.isVisible {
            controller.dismiss()
        } else {
            snippetsPanelController?.dismiss()
            ensureAccessibilityPermission()
            clipboardHistoryViewModel?.reset()
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
    private func performPasteAfterPanelCloses(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PasteSimulator.paste(text)
        }
    }

    @objc private func openLibrary() {
        if libraryWindowController == nil {
            libraryWindowController = LibraryWindowController(store: AppEnvironment.snippetStore)
        }
        libraryWindowController?.show()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(clipboardHistoryStore: AppEnvironment.clipboardHistoryStore)
        }
        settingsWindowController?.show()
    }
}
