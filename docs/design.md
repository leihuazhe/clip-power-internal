# Clip Power — Raycast 风格 Snippets 管理器（macOS Apple Silicon 原生版）

## Context

Raycast 的 Snippets 功能（全局热键呼出、搜索、回车粘贴常用文本片段）好用，但缺一个关键能力：**内容隐藏/加密**——用户想把密码、密钥等敏感片段也放进去，但不希望它们以明文出现在列表里，也不希望任何人打开面板就能直接看到/粘贴出去。

本项目目标：做一个只面向 Apple Silicon Mac 的原生菜单栏应用，复刻 Raycast Snippets 的核心体验（全局热键 → 浮层搜索 → 选中粘贴），并补上两级隐藏能力：
- **软隐藏**：从列表/搜索中隐去，但内容不加密，无需鉴权。
- **加密隐藏**：内容用 Secure Enclave 包裹的密钥加密存储，查看/粘贴前必须过 Touch ID 或密码。

已与用户确认的技术方向：SwiftUI + AppKit 原生（纯 arm64，不考虑 Intel/跨平台）、本地 SQLite 存储 + JSON 导入导出、全局热键呼出浮层选择器（同 Raycast 交互）。

**前置条件**：本机当前只装了 Command Line Tools，没有完整 Xcode.app（`xcodebuild` 不可用，无法生成/编译标准 `.xcodeproj`，也没有 `actool` 编译 `Assets.xcassets`）。用户已确认要先安装完整 Xcode 再继续实现。**在用户确认 Xcode 安装完成之前，不会开始写代码**——用户可以从 App Store 搜索"Xcode"安装，或去 developer.apple.com 下载，装完后告知我（我会用 `xcodebuild -version` 核实）即可开始。

本轮实现范围：**尽量一次完成 M0（骨架）→ M1（CRUD）→ M2（加密隐藏）→ M3（全局热键与浮层）→ M4（导入导出）**，不含 M5 视觉打磨（M5 留给后续会话，届时调用 `design-consultation` skill 产出正式视觉规范后再重做界面细节）。

---

## 整体架构

单进程、`LSUIElement=true` 的常驻菜单栏 App（不需要 XPC/独立后台服务——敏感操作本身走系统级隔离的 Keychain/Secure Enclave/LocalAuthentication，进程内隔离已经足够）。

```
ClipPower.xcodeproj
ClipPower/
  App/                  ClipPowerApp.swift, AppDelegate.swift（NSStatusItem、生命周期、热键注册、权限引导入口）
  Models/                Snippet.swift, SnippetVisibility.swift, SnippetContentType.swift, ExportPackage.swift
  Services/
    Database/            DatabaseManager.swift（GRDB pool + migrations）
    Crypto/               KeyManager.swift（SEP 密钥/DEK 包裹解包）, SnippetCipher.swift（AES-GCM）, BiometricGate.swift（LocalAuthentication）
    Hotkey/               GlobalHotkeyManager.swift（KeyboardShortcuts 封装）, PasteSimulator.swift（CGEvent 模拟 ⌘V）
    Permissions/          PermissionsManager.swift（Accessibility 检测与引导）
    SnippetStore.swift     数据层 facade，供 UI 层观察（GRDB ValueObservation → Combine）
    ImportExportService.swift
  ViewModels/            LibraryViewModel, QuickPanelViewModel, EditorViewModel, SettingsViewModel
  Views/
    MenuBar/              StatusItemController.swift
    QuickPanel/           QuickPanelController.swift（NSPanel）, QuickPanelView.swift, QuickPanelRow.swift
    Library/               SnippetListView, SnippetDetailView, SnippetEditorView, TrashView
    Settings/              GeneralSettingsView, SecuritySettingsView, HotkeySettingsView, ImportExportView
    Onboarding/            PermissionOnboardingView.swift
  Resources/              Info.plist（LSUIElement、Accessibility/AppleEvents 用途说明）；先用普通 .icns 图标，暂不建 Assets.xcassets 依赖
ClipPowerTests/
  CryptoTests/ DatabaseTests/ ImportExportTests/
```

依赖（SwiftPM）：`GRDB.swift`（数据层，选它而非 Core Data 是因为 FTS5、迁移脚本、`ValueObservation` 响应式查询更直接）、`KeyboardShortcuts`（Sindre Sorhus，封装 Carbon 全局热键 + 录制 UI，避免自己重新处理修饰键冲突等边界情况）。系统框架：`CryptoKit`、`LocalAuthentication`、`Security`、`ApplicationServices`。

数据流：写路径 Editor → ViewModel → `SnippetStore`（业务校验+必要时加密）→ GRDB 事务 → `ValueObservation` 推送给所有观察者（主窗口与浮层共享同一个 Store，天然一致）。读路径（热键触发）：记录当前焦点应用 → 弹出浮层 → 查询 Store（默认过滤 softHidden/encryptedHidden）→ 选中后如需鉴权则走 `BiometricGate` → 解密 → 关闭浮层 → `PasteSimulator` 模拟 ⌘V → 清空解密后的临时明文引用。

---

## 数据模型 / SQLite Schema

```swift
enum SnippetVisibility: String, Codable { case normal, softHidden, encryptedHidden }
enum SnippetContentType: String, Codable { case plainText, richText, template } // MVP 只实现 plainText

struct Snippet: Identifiable, Codable {
    var id: UUID
    var name: String
    var keyword: String?           // 触发词，唯一索引（NULL 允许）
    var contentType: SnippetContentType
    var plainContent: String?      // normal/softHidden 用
    var cipherContent: Data?       // encryptedHidden 用：AES-GCM sealedBox.combined
    var keyID: String?             // 引用 KeyManager 中的密钥标识，支持未来密钥轮换
    var visibility: SnippetVisibility
    var tags: [String]
    var usageCount: Int
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool            // 软删除→回收站
    var deletedAt: Date?
}
```

明文/密文字段互斥（不做"总是加密再缓存解密结果"），避免加密内容在非鉴权路径下被意外读到。

```sql
CREATE TABLE snippet (
    id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, keyword TEXT,
    content_type TEXT NOT NULL DEFAULT 'plainText',
    plain_content TEXT, cipher_content BLOB, key_id TEXT,
    visibility TEXT NOT NULL DEFAULT 'normal', tags TEXT,
    usage_count INTEGER NOT NULL DEFAULT 0, last_used_at REAL,
    created_at REAL NOT NULL, updated_at REAL NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0, deleted_at REAL
);
CREATE UNIQUE INDEX idx_snippet_keyword ON snippet(keyword) WHERE keyword IS NOT NULL AND is_deleted = 0;

CREATE VIRTUAL TABLE snippet_fts USING fts5(
    id UNINDEXED, name, keyword, searchable_content, tags,
    content='snippet', content_rowid='rowid'
); -- 触发器同步维护；encryptedHidden 条目的 searchable_content 只写 name/keyword/tags，绝不索引密文/明文内容
```

数据库文件放 `~/Library/Application Support/ClipPower/clippower.sqlite`，文件权限设为 0600。

---

## 加密方案

- **密钥体系**：软件生成 256-bit DEK（`CryptoKit.SymmetricKey`）加密所有 encryptedHidden 内容；DEK 本身用 Secure Enclave 生成的 `SecureEnclave.P256.KeyAgreement.PrivateKey` 做 ECDH 派生出的 KEK 包裹（wrap）后存 Keychain（`SecAccessControl` 要求 `.biometryCurrentSet`/`.userPresence`）。SEP 硬件只支持非对称密钥，因此对称 DEK 必须走"SEP 保护的非对称密钥包裹软件对称密钥"这一标准模式。
- **应用内密码兜底**：设备不支持/未注册 Touch ID 时，走密码派生 KEK（PBKDF2，`CommonCrypto`）包裹 DEK，同样不持久化派生结果。
- **内容加解密**：`AES.GCM`，每条内容独立随机 nonce，直接存 `sealedBox.combined` 到 `cipher_content` 一个字段。
- **鉴权网关**：`LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)`（允许 Touch ID 失败后 fallback 系统密码，避免未注册指纹用户被锁死），验证通过才触发 SEP 解包→拿到 DEK→解密。会话级宽限期（默认 15s，可在设置关闭）避免连续操作反复弹 Touch ID。
- **内存卫生**：解密结果尽量用 `Data`/`[UInt8]`，用完 `resetBytes` 清零；必须转 `String` 写入 Pasteboard 时只作局部变量，不留存于 ViewModel 属性；粘贴完成后可选延迟清空系统剪贴板（按 `changeCount` 判断未被用户覆盖再清）。

---

## 全局热键 + 浮层 + 模拟粘贴

- **热键注册**：用 `KeyboardShortcuts` 包（内部封装 Carbon HotKey API），默认 `⌥+Space`，Settings 里可自定义/录制。`NSEvent.addGlobalMonitorForEvents` 只用于监听"点击面板外部"以关闭浮层，不用它做主热键（它无法拦截事件，且需要 Accessibility 权限才能监听非本 App 按键）。
- **NSPanel 配置**：`styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless]`，`level = .floating`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`，`isOpaque=false`/`backgroundColor=.clear`。**关键点**：用 `.nonactivatingPanel` 使浮层不抢占前台激活状态，原本聚焦的输入框不失焦，这样关闭浮层后原 App 天然恢复焦点，粘贴目标不会丢失（同 Raycast 做法）——不要调用 `NSApp.activate(ignoringOtherApps:)`。
- **模拟粘贴**（主路径）：写入 `NSPasteboard.general` + `CGEvent` 模拟 ⌘V（`virtualKey: 0x09`, `flags = .maskCommand`，`post(tap: .cghidEventTap)`）。兼容性最好，几乎所有 App 都能正确响应。备选路径（AX `kAXValueAttribute` 直写）只作为已知场景的增强，不做主路径。
- **权限**：`CGEvent.post` 需要 Accessibility 授权。首次启动用 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` 引导系统授权提示，并在 Settings 里做权限状态面板+跳转系统设置的按钮。**注意**：本机用 ad-hoc/开发者身份签名多次重新构建时，Accessibility 授权可能需要重新授予一次（正常现象，会在验证阶段提醒用户）。

---

## CRUD / 隐藏 / 导入导出交互

- **创建/编辑**：表单含标题、keyword（唯一性校验）、内容（纯文本，MVP 不做富文本/模板）、隐藏级别三态选择器（公开/软隐藏/加密隐藏）、标签。切到"加密隐藏"保存时触发加密写入并清空 `plain_content`；切回公开需先鉴权解密还原明文。
- **删除**：软删除（`isDeleted=1`），主窗口提供回收站视图（恢复/永久删除），默认 30 天自动清理，App 启动时跑一次清理 job。
- **导出**：范围可选（全部/仅普通/含软隐藏/含加密），JSON 顶层含 `formatVersion`、`exportedAt`、`requiresExportPassword`。含加密隐藏条目时若不设导出密码，只能导出"设备绑定密文"（无法在其他设备解密，SEP 密钥本身不可导出，这是硬件特性）；设导出密码则先鉴权解密→用密码派生的临时密钥重新加密打包，可跨设备迁移，但始终不落地明文。
- **导入**：解析 JSON → 按 keyword 做冲突预检（跳过/覆盖/合并为新三种策略，默认"跳过"最安全）→ 加密条目按是否有导出密码分别处理（有密码：解密后用本机密钥重新加密落库；无密码且非本机备份：明确报错"设备绑定密文无法跨设备导入"）。

---

## 项目结构与依赖（Xcode 版）

用户确认将安装完整 Xcode 后继续，因此采用标准 `.xcodeproj` + SwiftPM 依赖（而非纯 SPM 手工打包 .app），可用 `xcodebuild` 编译、`xcodebuild test` 跑单元测试，App 图标先用简单 `.icns`（暂不依赖 Assets.xcassets 的复杂配置，避免不必要的前期工作）。

---

## 本轮实现范围与里程碑（M0 → M4，不含 M5 视觉打磨）

1. **M0 骨架**：Xcode 项目 + Info.plist（LSUIElement=true、权限用途文案）、菜单栏图标+空主窗口、GRDB 初始化与迁移框架跑通。
2. **M1 CRUD**：完整创建/编辑/更新/删除（软删除+回收站）+ 主窗口列表/FTS5 搜索/详情预览，先只覆盖 `visibility=normal`。
3. **M2 加密隐藏**：软隐藏过滤逻辑；加密隐藏全链路（KeyManager SEP 密钥生成/包裹、SnippetCipher AES-GCM、BiometricGate LocalAuthentication、编辑器隐藏级别切换与加解密联动、密码兜底方案）。
4. **M3 全局热键与浮层**：KeyboardShortcuts 集成与自定义 UI；QuickPanelController/View；焦点应用记录+PasteSimulator；Accessibility 权限检测与引导；打通"呼出→搜索→选中（含加密鉴权）→粘贴→关闭"全链路。
5. **M4 导入导出**：ExportPackage 落地、导出范围/密码保护 UI、导入预检与冲突处理 UI、跨设备加密内容迁移逻辑、格式版本兼容性处理。

M5（视觉打磨）留给后续会话：届时调用 gstack 插件的 `design-consultation` skill，输入产品定位（"Raycast 风格效率工具 + 隐私优先"，macOS 原生毛玻璃美学）产出正式的字体/色板/间距/动效规范，再回头重做 `Views/` 下各视图与 `NSVisualEffectView` 参数。

---

## 验证方式

- **单元测试**（`ClipPowerTests`，用 `xcodebuild test`）：
  - `CryptoTests`：加密/解密 round-trip、DEK 包裹/解包、密码派生兜底路径、内存清零逻辑的可测部分。
  - `DatabaseTests`：迁移脚本、keyword 唯一索引冲突、软删除过滤、FTS5 搜索命中/加密内容不可被搜索到。
  - `ImportExportTests`：导出 JSON 结构、导入冲突三种策略、跨设备密文导入报错路径。
- **手动集成验证**（Touch ID 弹窗、Accessibility 授权、全局热键这些系统级交互无法在无 GUI 环境下自动化，需要你在本机实际操作确认）：
  1. `xcodebuild -scheme ClipPower build` 编译通过。
  2. `open` 生成的 .app，检查菜单栏图标出现、主窗口 CRUD 全流程可用。
  3. 触发一次加密隐藏保存+查看，确认弹出 Touch ID/密码验证且验证前看不到明文。
  4. 按下全局热键，确认浮层弹出且不打断原输入框焦点；选中一个 snippet 回车，确认目标输入框收到粘贴内容。
  5. 导出一份含普通+加密内容的 JSON，重新导入一遍，检查冲突处理与加密迁移是否符合预期。

每完成一个里程碑会在对话里明确汇报进度，M2/M3 涉及系统权限的部分会提示你配合做一次实机验证，而不是我单方面宣称"完成"。

---

## 实现记录（M0-M4 已完成，与本文档设计的差异说明）

- **构建方式**：本机只有 Command Line Tools 时先用 XcodeGen（`project.yml` → `xcodegen generate`）生成 `.xcodeproj`；安装完整 Xcode 后继续沿用同一套 `project.yml`，`xcodegen generate` 随时可重新生成项目文件（该文件已加入版本管理，`.xcodeproj` 本身是生成产物）。
- **Snippet.id 类型**：实际实现用 `String`（UUID 字符串）而不是 `UUID`，因为 GRDB 对 `Foundation.UUID` 默认按 16 字节 BLOB 存储，与 schema 里 `id TEXT PRIMARY KEY` 不匹配；改用 String 直接对应 TEXT 主键，避免类型不一致。
- **搜索实现**：`SnippetStore.search` 最终用的是转义后的 `LIKE '%...%'` 子串匹配，而不是 FTS5 `MATCH`。原因是 SQLite 默认的 `unicode61` 分词器不会对中文分词（“工作邮箱”会被当成一个整体 token），导致中文子串搜索匹配不到；`snippet_fts` 虚表和触发器仍按本文档保留在 schema 里（为后续切换分词器或做英文场景下的相关性排序留了空间），但当前查询路径不依赖它们。搜索的安全边界（加密隐藏内容不可被搜到）由 `plainContent` 字段在加密隐藏时本就是 `NULL` 来保证，与是否用 FTS5 无关。
- **KeyManager 可测试性**：`KeyManager.wrap`/`unwrap` 抽出为对 `KeyAgreementPrivateKey` 协议的泛型静态方法，`SecureEnclave.P256.KeyAgreement.PrivateKey` 与软件版 `P256.KeyAgreement.PrivateKey` 都满足该协议，因此 ECDH+HKDF+AES-GCM 的包裹/解包算法可以用软件密钥在单元测试里跑通，无需触碰真实 Secure Enclave/Touch ID。
- **ImportExportService 可测试性**：加解密相关调用都通过 `SnippetContentRevealing` 协议注入（默认实现是真实的 `SnippetEncryptionService`），单元测试里换成一个不触碰 Keychain 的假实现，从而能自动化验证导出打包、导入冲突策略（跳过/覆盖/新建副本）、导出密码保护、设备绑定密文这几条逻辑分支，而不必真的弹 Touch ID。

### 已验证 / 待你手动验证

- ✅ 已验证：`xcodebuild build`/`xcodebuild test` 全绿（34 个单元测试，覆盖数据库迁移、CRUD、软删除/回收站、加解密算法、密钥包裹算法、导入导出全部分支）；App 能正常启动为菜单栏常驻进程、创建/编辑/删除窗口不崩溃、能正常退出。
- ⏳ 待你在图形界面下手动验证（这些依赖真实 Touch ID 弹窗/系统权限对话框，无法在当前无 GUI 的命令行环境里自动化，也不应该被自动化绕过）：
  1. 在「新建片段」里选「加密隐藏」保存，确认会弹出 Touch ID / 密码验证，验证前后内容是否符合预期（列表里显示为已隐藏、详情页需要再次验证才能看到明文）。
  2. 首次触发全局热键（默认 ⌥+Space）时，系统应弹出「辅助功能」授权提示；去系统设置里允许后，再按热键确认浮层能正常呼出、搜索、方向键切换、回车粘贴到其他 App 的输入框，且不会打断原来的输入焦点。
  3. 在「导入/导出」里，导出一份包含加密隐藏内容并设置导出密码的 JSON，删除本机记录后用该密码重新导入，确认内容能正确恢复。
  4. 菜单栏图标的「打开管理窗口」「退出」菜单项，以及回收站的恢复/永久删除按钮的实际点击效果。

M5（视觉打磨，调用 `design-consultation` skill 产出正式视觉规范）尚未开始，当前界面只是功能可用的默认 SwiftUI 样式。

### 隐藏 UI 的一次修正（用户反馈后调整）

最初实现把软隐藏/加密隐藏条目放进一个独立的「隐藏片段」侧栏，与「全部片段」分开。用户反馈这不是想要的效果：应该是**统一列表**，隐藏条目照样出现在主列表和全局热键浮层的搜索结果里，只是打上标记（🔒/👁️‑ 图标）、内容打码显示为「●●●●● 已隐藏」，点击后才展开（软隐藏直接展开；加密隐藏需要先过 Touch ID / 密码）。据此做了以下调整：

- `SnippetStore.fetchActive()` / `search()` 不再按 `visibility` 过滤，隐藏条目的**标题/关键词/标签**可以被搜到，但**内容**搜不到——因为加密隐藏条目的 `plainContent` 本就是 `NULL`，这个安全边界与是否按 visibility 过滤无关。
- 删除了独立的「隐藏片段」侧栏（`HiddenViewModel`/`HiddenListView`/`HiddenDetailView`），改为 `SnippetListView`/`SnippetDetailView` 直接按 `visibility` 分支渲染打码/解锁逻辑，`LibraryViewModel` 新增 `reveal`/`unhideSoft`/`unhideEncrypted` 方法。
- 全局热键浮层（`QuickPanelViewModel`）的搜索结果同样包含隐藏条目，行内打码显示；选中加密隐藏条目会先触发一次 Touch ID / 密码鉴权再粘贴，浮层底部会显示「验证中...」状态，避免用户以为没反应。

---

## M4.5：剪贴板历史 + 独立可配置热键 + 设置面板

对齐 Raycast 的另一个常用功能——除了 Snippets，还有一个「剪贴板历史」浮层，两者是完全独立的能力：

- **数据层**：新增 `clipboardHistoryItem` 表（`ClipboardHistoryItem` / `ClipboardHistoryStore`），字段只有 `id/content/createdAt`，不做加密/隐藏（剪贴板历史本来就是系统剪贴板的原始记录，隐藏是 Snippets 的特性）。上限 200 条，超出自动清理最旧的；连续重复内容（比如自己粘贴 snippet 又被监控抓回来）会被跳过，不产生重复记录。排序统一加了 `rowid` 做次级排序键——纯粹是因为自动化测试连续 `record()` 时 `createdAt` 精度不够会撞到同一毫秒，真实使用中基本不会碰到，但测试踩了这个坑就顺手修了。
- **采集方式**：`ClipboardMonitor` 轮询 `NSPasteboard.general.changeCount`（0.5s 一次）——macOS 没有剪贴板变化的推送通知 API，Raycast/Alfred 等剪贴板管理器也都是轮询实现的。
- **浮层复用**：把 `QuickPanelController` 的窗口行为（`.nonactivatingPanel` 配置、方向键/Esc 的本地事件监听、失焦自动关闭）抽成了一个共享基类 `FloatingPanel`，Snippets 面板和剪贴板历史面板都是它的薄封装，只需要提供各自的 SwiftUI 内容视图和上下键回调。
- **失焦自动关闭**（用户反馈后补的）：`FloatingPanel` 实现了 `NSWindowDelegate.windowDidResignKey`，浮层只要失去键盘焦点（点了别的窗口/别的 App）就自动收起，不需要非得再按一次热键或 Esc。
- **独立可配置热键**：`GlobalHotkeyManager` 现在管理两个 `KeyboardShortcuts.Name`——`toggleSnippetsPanel`（默认 ⌥+Space，不变）和 `toggleClipboardHistoryPanel`（默认 ⌘⇧V）。两个热键互斥：呼出一个会自动收起另一个。
- **设置面板**：菜单栏新增「设置...」，`SettingsWindowController`（AppKit 管理生命周期，和 `LibraryWindowController` 同样的套路）打开一个独立窗口，列出两个热键的 `KeyboardShortcuts.Recorder`（可以随意改绑，比如改成 ⌘1）+ 剪贴板历史条数统计 + 一键清空。

### 一个值得记录的调试方法论

这一轮开发里连着修了两个"看起来诡异"的 bug（编辑表单显示空白、方向键选中第二项回车却粘贴了第一项），都不是靠读代码猜出来的，是靠**在终端直接跑 App 可执行文件 + 临时加 `print` 调试日志 + 让用户实际操作复现**，日志一出来根因立刻就清楚了（比如 `searchText` 重复赋值触发 `reload()` 把 `selectedIndex` 冲掉）。之后这个项目的调试都统一走这条路，不再用 `open App.app`（那样看不到 stdout）。

### 设置搬进管理窗口（用户反馈后调整）

设置最初是菜单栏里一个独立的小窗口（`SettingsWindowController`），用户反馈应该挪到管理窗口下面，作为侧栏的一个栏目，且视觉要更现代化。改动：删除 `SettingsWindowController`，`SettingsView` 变成 `LibraryView` 侧栏的第三个 `SidebarItem`（齿轮图标），菜单栏的「设置...」入口也去掉了（统一走管理窗口）。视觉上换成了 macOS 原生的 `Form + Section + LabeledContent`、`.formStyle(.grouped)`，对齐系统设置那种分组卡片风格。

---

## M4.6：合并浮层 + Tab 切换 + 三个入口热键

用户进一步反馈：Snippets 面板和剪贴板历史面板不应该是两个互斥的独立浮层，而应该是**同一个浮层里的两个 Tab**，用 Tab 键左右切换。同时明确了三个热键的语义：

1. **ClipPower 打开快捷键**（新增，`toggleClipPowerPanel`，默认 ⌥+Space，沿用原来 Snippets 面板的默认值）——通用入口，按下后打开合并面板，**默认展示"片段"**这个 Tab。
2. **片段快捷键**（`toggleSnippetsPanel`，默认不绑定，用户可在设置里自定义）——直接打开合并面板并定位到"片段" Tab。
3. **剪贴板历史快捷键**（`toggleClipboardHistoryPanel`，默认 ⌘⇧V，不变）——直接打开合并面板并定位到"剪贴板历史" Tab。

交互规则：
- 面板已经打开时，按下另一个 Tab 对应的热键 → **切换到那个 Tab**（不关闭面板）；按下**当前已经激活的那个 Tab** 对应的热键 → 关闭面板（维持原来"再按一次关闭"的习惯）。
- 面板内按 **Tab 键**在两个 Tab 之间左右切换（只有两个 Tab，Tab 键单纯是"切到另一个"，不用区分 Shift+Tab）。
- 每个 Tab 各自保留自己的搜索框状态/选中项（`QuickPanelViewModel`/`ClipboardHistoryViewModel` 互不干扰），只是纳入了同一个窗口里显示；每次面板重新打开时两个 Tab 的搜索状态都会重置。

实现上：新增 `ClipPowerPanelViewModel`（持有两个子 ViewModel + `activeTab` 状态 + 路由 `moveSelection`/`cycleTab`）、`ClipPowerPanelView`（顶部 Tab 条 + 下方切换显示 `QuickPanelView`/`ClipboardHistoryView` 的内容部分）、`ClipPowerPanelController`（`FloatingPanel` 的薄封装）。原来独立的 `QuickPanelController`/`ClipboardHistoryPanelController` 两个窗口控制器被这一个取代；`FloatingPanel` 基类新增了 `onTabKey` 回调（拦截 keyCode 48 也就是 Tab 键）。
