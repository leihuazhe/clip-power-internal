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

### 热键冲突防抖（用户反馈后补的）

如果用户在设置里把两个热键绑到了同一个键位，系统会把一次按键同时投给两个 handler，`togglePanel` 被连续调用两次——第一次打开面板，第二次立刻判定"已经在目标 Tab"就把它关掉，表现就是面板一闪而过（"秒退"）。修复：`AppDelegate` 加了 300ms 防抖，短时间内的重复触发直接忽略。

### Snippets 面板左右分栏 + 按使用时间排序（对标 Raycast 原生 UI）

参考 Raycast 官方 Snippets/Clipboard History 面板截图重做了两个 Tab 的浮层内容：左边是按"今天/昨天/本月/更早"分组的列表（`DateSectionGrouping` 工具），右边是内容大字预览 + Information 元数据区。同时给 `Snippet` 加了 `usageCount`/`lastUsedAt` 统计（`SnippetStore.recordUsage`，每次在浮层里选中粘贴就 +1、更新最近使用时间，不影响 `updatedAt`），列表默认按最近使用时间排序（没用过的按创建时间）。

**踩过的一个坑**：右侧预览区一开始只挡了 `.encryptedHidden`，忘了 `.softHidden` 也需要打码——这个预览区是方向键选中就自动刷新的，不是用户主动点击"查看"，一旦露出软隐藏内容就等于"选中即看到"，跟隐藏的初衷相悖。修复后两种隐藏可见性在预览区都只显示打码占位，查看/解锁走管理窗口那套需要主动点击的流程。

浮层窗口的四个角一开始有两个是方的，因为 `FloatingPanel` 的 `styleMask` 里带了 `.titled`——即使隐藏了标题栏文字、设了透明标题栏，styleMask 里带 `.titled` 仍然会在窗口顶部保留一条方形的系统标题栏区域盖住圆角。改成纯 `.borderless` + 直接给内容视图的 CALayer 设 `cornerRadius`（20pt）+`masksToBounds`，四个角才真正跟着圆。管理窗口是标准 macOS 标题栏窗口，系统本身就会自动画圆角，没有改。

### 剪贴板历史支持图片/文件 + 关键词自动展开 + 导入 Raycast Snippets

三个独立的新增能力：

1. **剪贴板历史支持图片/文件**：`ClipboardHistoryItem` 从单一 `content: String` 拆成 `kind`（text/image/file）+ 各类型专属字段（`textContent`/`imageData`+`imageWidth`+`imageHeight`/`fileURLs`+`byteSize`），schema 迁移用"建新表→搬数据→删旧表"的方式（SQLite 不支持直接改列约束）。`ClipboardMonitor` 按 **文件 → 图片 → 文本** 的优先级判断剪贴板内容（Finder 复制文件时剪贴板有时也带图标的图片表示，必须先排除文件 URL 再判断图片，用 `NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly` 精确识别真正的文件 URL，避免把复制的网页链接误判成文件）。`PasteSimulator` 按类型把内容写回剪贴板（`NSImage`/`NSURL` 对象或纯文本）再模拟 `⌘V`。
2. **关键词自动展开**（对标 Espanso/TextExpander，Raycast 本身也没有）：`TextExpansionMonitor` 用 `NSEvent.addGlobalMonitorForEvents` 只读监听全局按键（不拦截，用户正常输入完全不受影响），维护一个滚动缓冲区，每敲一个字符就用 `KeywordIndex`（内存里的「触发词→片段 id」索引，监听 `.snippetsDidChange` 通知自动刷新，不用手动同步）检查缓冲区末尾是否命中某个触发词，命中就用 `PasteSimulator.replaceTypedText` 模拟退格删掉刚打的触发词、再粘贴替换内容。**加密隐藏的片段不参与**——那需要 Touch ID，不适合在打字时无感触发，软隐藏则正常参与（不需要鉴权）。已知局限（和大多数简单文本替换工具一样）：如果触发词恰好是另一个更长单词的后缀（比如触发词 "gitc"，用户打的是 "logitc"），也会被命中展开，需要自己挑不容易跟普通单词撞在一起的触发词，这是设计上的取舍，不是 bug。
3. **导入 Raycast 官方 Snippets JSON**：`ImportExportService.importRaycastSnippets`，格式是 `[{ "name", "text", "keyword"? }, ...]` 的纯明文数组（没有可见性/加密概念），全部落库为 `normal` 可见性，冲突处理复用已有的跳过/覆盖/新建副本三种策略。管理窗口「导入/导出」面板里加了单独的入口。

### 两个 V6 引入的 bug

1. **迁移遗漏导致剪贴板历史查询整体失败**：上面 schema 迁移的 `INSERT INTO clipboardHistoryItem (id, kind, textContent, createdAt) SELECT ...` 没有显式给 `fileURLs` 赋值，旧数据这一列全是 `NULL`；但 `ClipboardHistoryItem.fileURLs` 在 Swift 里是非空的 `[String]`（不是 `[String]?`），GRDB 解码遇到 `NULL` 直接抛错——而且 `fetchAll` 是整批一起解码的，只要有一行失败，**整个查询结果都被吞掉**（外层用了 `try?`），表现就是"剪贴板历史一条都没有了"，包括新写入的数据（因为查询本身就没跑成功，不是数据没写进去）。修复：迁移语句显式把 `fileURLs` 填成 `'[]'`；另外加了一个 `v4_backfillClipboardFileURLs` 迁移，把已经跑过旧版 v3 迁移、留下 `NULL` 的机器上的数据直接修复回来。
2. **第一次呼出浮层时回车不生效**：NSPanel 第一次 `makeKeyAndOrderFront` 时，窗口还没真正变成 key window，SwiftUI 的 `.onAppear` 已经把 `@FocusState` 设过去了，设置不生效——搜索框没拿到真正的键盘第一响应者，回车摸不到 `.onSubmit`；方向键仍然能用是因为那是在窗口级别用 `NSEvent` 本地事件监听的，不需要真正的第一响应者。第二次之后窗口已经"热"了（窗口服务器资源已分配好），就不再有这个时序问题。修复：`QuickPanelView`/`ClipboardHistoryView` 的 `.onAppear` 里把 `isSearchFocused = true` 延迟到下一个 runloop 周期（`DispatchQueue.main.async`）再设。

### 隐藏内容不落地剪贴板 + 剪贴板历史全局去重

两个独立的收尾修正：

1. **软隐藏/加密隐藏内容不再经过系统剪贴板**：之前粘贴任何片段（包括隐藏的）都是走"写剪贴板 + 模拟 ⌘V"，意味着刚解锁的敏感内容会被自己的 `ClipboardMonitor`（或用户机器上别的剪贴板管理器）当成一条新的剪贴板历史又记录下来，等于白隐藏了——加密隐藏的内容尤其讽刺，费了 Touch ID 解锁，转头就以明文形式留在了剪贴板历史里。新增 `PasteSimulator.typeDirectly` / `PasteMethod` 枚举：软隐藏、加密隐藏都改成用 CGEvent 直接模拟键盘输入整段文字（`keyboardSetUnicodeString`），完全不碰 `NSPasteboard`；普通（公开）片段仍然走剪贴板+模拟 ⌘V（兼容性最好，某些应用对直接模拟输入的支持不如响应真实 ⌘V 可靠）。顺手把「关键词自动展开」（`PasteSimulator.replaceTypedText`）也从剪贴板粘贴改成了直接输入，避免每次展开普通片段都污染用户当前的剪贴板内容——这不只是隐藏内容才有意义的改动。
2. **剪贴板历史去重从"只看上一条"改成"全局去重"**：原来 `ClipboardHistoryStore.record` 只检查是否和最近一条完全相同，如果中间复制过别的内容，同一份内容再复制一次就不会被判重，导致列表里堆出一堆一样的条目（实测截图里 "Zaneyoujie@1314" 连续出现好几次）。改成：不管在历史的哪个位置，只要同类型（文本比文字、图片比字节、文件比路径列表）已经存在完全相同的内容，就直接把那条已有记录的 `createdAt` 更新成现在（效果是"挪到最前面"），不新建重复行。

### 管理窗口新增「导入/导出」侧栏栏目 + 导入结果改为弹窗提示

两个独立的小改动：

1. **侧栏新增独立入口**：`LibraryView` 的 `SidebarItem` 加了 `.importExport`，在侧栏"回收站"和"设置"之间插入"导入/导出"一项，内容区直接渲染 `ImportExportView(showsCloseButton: false)`（常驻栏目不需要"关闭"按钮）。原来菜单栏工具条上的"导入/导出"按钮 + `.sheet` 弹窗入口按用户要求原样保留，两个入口共享同一个 `ImportExportViewModel` 实例，行为完全一致，只是多了一条不需要先点工具条按钮就能到达的路径。
2. **导入/导出结果从纯文字说明改成 `.alert` 弹窗**：排查用户反馈"导入后没有成功/失败提示，而且导入没成功"时，先加临时 `print` 调试日志+终端直跑复现，结果确认导入本身是成功的（真实 Raycast 导出文件 18 条，17 条导入、1 条因 keyword 冲突被正确跳过，逐条对照 sqlite 数据核实无误）——真正的问题纯粹是 UX：`viewModel.statusMessage` 之前只在面板底部显示一行 `.caption` 小字，很容易被忽略，用户因此误以为"没有提示，也没有导入成功"。修复：`ImportExportView` 去掉底部的行内 caption，改用 `.alert("导入/导出结果", isPresented:)` 弹窗展示同一条 `statusMessage`（绑定方式与 `LibraryView` 现有的错误提示 `.alert` 一致：`Binding` 的 get 判断 `statusMessage != nil`，set 在用户点掉弹窗时把它清空），确保成功/失败/跳过数量以醒目的模态弹窗呈现，而不是容易被忽略的小字。

### 浮层方向键选中高亮"消失"的 bug

用户反馈：在浮层里用上下方向键切换选中项时，被选中行的蓝色高亮块会"消失"，不会跟着移动到新选中的行上。

根因排查：`QuickPanelView`/`ClipboardHistoryView` 左侧列表都是普通 `ScrollView + LazyVStack`，`selectedIndex` 变化本身没问题（`QuickPanelViewModel.moveSelection`/`selectRow` 的逐行 `isSelected = index == viewModel.selectedIndex` 判断是对的），但列表**没有任何自动滚动逻辑**跟 `selectedIndex` 联动。方向键按到列表比较靠下的位置时，新选中的那一行会被移出可视区域——屏幕上看不到任何带蓝色底色的行，视觉上就等同于"高亮块凭空消失了"，而不是真的没跟着移动。

修复：给每一行加 `.id(index)`（`index` 就是 `results.firstIndex(of:)` 换算出来的真实下标，和分组无关），用 `ScrollViewReader` 包一层，`.onChange(of: viewModel.selectedIndex)` 触发时调用 `proxy.scrollTo(newIndex, anchor: .center)`（带一个 120ms 的 `easeOut` 小动画），确保选中行始终自动滚动到可视范围内。`QuickPanelView` 和 `ClipboardHistoryView` 是同一套列表结构，两边都改了同样的逻辑。（注：`.onChange(of:initial:_:)` 双参数闭包版本要 macOS 14+，项目部署目标是 macOS 13，用了单参数的旧版 `onChange(of:) { newValue in }`。）

---

## 国际化：支持英语 / 简体中文 / 日语，默认英语，设置里可切换

用户要求全应用支持多语言（先做英/中/日三种），语言在「设置」里手动选择，且**默认使用英语**，不跟随系统语言。这是本项目第一次做国际化，扫描下来 `ClipPower/` 下 29 个 `.swift` 文件、165 处中文字符串字面量命中，涉及全部 View/ViewModel/Service 层，先过了一遍设计方案（详见 `/Users/huazhe.lei/.claude/plans/velvety-leaping-scott.md`）再动手。

### 技术方案

**用 Xcode String Catalog（`ClipPower/Resources/Localizable.xcstrings`），源语言设为 `zh-Hans`**：代码里现有的中文字面量就是 catalog 的 key，只要写好 `en`/`ja` 两组翻译，SwiftUI 的 `Text`/`Label`/`Button`/`TextField`/`Toggle`/`Picker`/`SecureField`/`LabeledContent` 这些 API 传字面量时天然会走 `LocalizedStringKey` 查表——**绝大多数调用点不用改一行代码**。`.xcstrings` 是纯 JSON，全程用 `xcodebuild` CLI 构建（没开 Xcode GUI 用"提取字符串"功能），所以是手写的完整 JSON，不是靠自动提取。手写时踩了两个真实的隐藏陷阱：
- **三元表达式喂给 `Text(...)`（`Text(cond ? "a" : "b")`）不保证走 `LocalizedStringKey` 那个重载**——为了不赌编译器的类型推断，统一改成显式 `Text(cond ? LocalizedStringKey("a") : LocalizedStringKey("b"))`。
- **字面量一旦先赋值给一个 `String` 类型的函数参数、再传进 `Text(变量)`，就会退化成不查表的 verbatim 重载**——`PanelHintPill.text`、`InfoRow.label`、`SnippetDetailView.maskedPlaceholder(text:)` 这三个内部小组件原来的参数类型都是 `String`，改成了 `LocalizedStringKey`，调用点不用变（本来传的就是字面量），但组件内部 `Text(text)` 才能真正生效。

**运行时拼接的文案（错误提示、导入结果统计、日期/字节数格式化）不能靠字面量自动查表**，因为 key 必须是编译期常量。这类地方新增了一个小工具函数 `localizedFormat(_ key:, _ args: CVarArg...)`（`ClipPower/Services/LocalizedFormat.swift`），显式给一个自己起的 key（比如 `"importSummaryFormat"`）+ `String(format:)` 拼参数，而不是依赖 `String(localized: "文案\(x)")` 插值语法自动推导 key——插值语法生成的 key 格式不透明，手写 `.xcstrings` 时很容易对不上导致翻译悄悄不生效，显式 key 完全可控。一共 18 处这样的格式化文案（各种"XX 失败：%@"、导入结果统计、"更新于/删除于 %@"、图片尺寸/文件数量等）。

**语言切换机制：设置里选、默认英语、切换后需要重启生效**。这是最关键的取舍：macOS 对 `Bundle.main` 本地化字符串的解析是进程启动早期就定死并缓存的，运行时改 `UserDefaults` 的 `AppleLanguages` 键不会让已经在跑的进程里的文案立刻刷新——要做到"选完立刻生效不用重启"，得给全部文案单独写一套自己维护的 Bundle 查表函数，不能再依赖 SwiftUI 原生的 `Text` 自动本地化。对 ClipPower 这个个人小工具来说，这个复杂度换来的收益不成比例，所以选了"改语言后需要重启一次"的方案（很多 Mac 小工具也是这么做的）：
- 新增 `AppLanguage` 枚举（`en`/`zhHans`/`ja`），`displayName` 永远用语言自己的写法显示（"English"/"简体中文"/"日本語"），不跟着当前 App 语言本地化——不管界面现在是什么语言，用户都能在选择器里认出自己想切的那个。
- 新增 `AppLanguageManager`（`ClipPower/Services/AppLanguageManager.swift`）：`apply(_:)` 写偏好 + `AppleLanguages`；`relaunch()` 用 `NSWorkspace.openApplication` 重新拉起同一个 `.app` bundle 的新进程，再 `NSApp.terminate` 退出当前进程。
- `AppDelegate.applicationDidFinishLaunching` 最开头检查：如果还没存过语言偏好（真正的首次启动），不跟随系统语言，直接写入 `.en` 并**静默重启一次**再退出，不搭建任何 UI——这样用户看到的第一帧界面就已经是英文，不会有"先看到系统语言、之后才变成英文"的一次性突兀体验。
- 「设置」页新增「语言」分组，一个 `Picker` 绑定三个语言，选中新值后弹 `.alert` 提示需要重启，"现在重启"按钮触发同样的 `relaunch()`。

### 实现过程中发现并修的两个真实 bug

1. **重启逻辑有竞态，导致新进程压根没起来**：最初写法是 `NSWorkspace.shared.openApplication(...) { _, _ in }` 后紧跟着立刻 `NSApp.terminate(nil)`。`openApplication` 底层是一次到 Launch Services 的异步 XPC 往返，当前进程如果在这次往返真正处理完之前就退出，拉起新进程的请求会直接被丢弃——实测复现了（`ps aux` 看不到任何新进程）。修复：把 `terminate` 挪到 `openApplication` 的 completion handler 里面，等这次请求真正处理完之后再退出。
2. **单元测试把 `ClipPower.app` 自己当 test host 跑，首次启动的静默重启逻辑在测试进程里被触发，直接把测试宿主进程杀了**：`xcodebuild test` 报"测试运行器过早退出"。根因是 `ClipPowerTests` 的 macOS 单测默认拿 `ClipPower.app` 本身当宿主进程启动，`AppDelegate.applicationDidFinishLaunching` 在这个上下文里也会真的跑一遍——这台机器是第一次跑这段新代码，还没存过语言偏好，于是触发了"首次启动→写偏好→重启→terminate"这条路径，而重启一个新进程对正在等待连接的 XCTest 驱动毫无意义，`terminate` 反而直接把测试宿主杀了。修复：`AppLanguageManager.isRunningTests`（检查 `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]`）跳过这条路径，测试环境下直接走正常启动流程，语言解析退化成"这次跑测试就用默认 `.en`，不落盘、不重启"。

### 剪贴板交互全面审查（用户反馈"用起来还是有问题"后做的一次系统性排查）

用户报告了三个现象：高亮块不跟着方向键移动、出现两行同时高亮（有截图）、选中后按 Enter 输出的不是选中那条。前两次针对症状的猜测性修复（加自动滚动、去掉动画）都没有真正解决，所以这次把整条链路（`ClipboardMonitor` → `ClipboardHistoryStore` → `ClipboardHistoryViewModel` → `ClipboardHistoryView` → `FloatingPanel` → `PasteSimulator` → `AppDelegate`）完整过了一遍。查出 5 个问题，其中 3 个是真 bug：

**1. 视图里用 `firstIndex(of:) ?? 0` 反查下标（根因，最严重）**

两个浮层列表里每一行的下标都是这么来的：
```swift
let index = viewModel.results.firstIndex(of: item) ?? 0
QuickPanelRow(snippet: item, isSelected: index == viewModel.selectedIndex)
```
问题在于列表是 `LazyVStack`，**行的 body 是延迟求值的**——求值时机可能晚于 `groupedResults` 被捕获的那一帧。中间 `results` 一旦被 `reload()` 换过一轮（搜索文本变化、`reset()`、条目被删），闭包捕获的旧 `item` 就不在新 `results` 里了，反查返回 `nil`，而 `?? 0` 这个兜底让**所有反查失败的行都算成"第 0 项"**：

- 多行同时满足 `isSelected` → **多行同时高亮**（用户截图里"curl --request GET..."和"cars-search"两行同时是蓝色，正是这个）
- 点击/回车都用这个错误下标 → **粘贴的永远是 `results[0]`**，跟看起来选中的那一行无关

附带还有性能问题：192 条内容时每次渲染是 O(n²) 次 `Equatable` 比较，图片条目要逐字节比 `Data`。

修复：新增 `IndexedRow<Element: Identifiable>`（`ClipPower/Models/IndexedRow.swift`），让 `groupedResults` 在**同一次快照**里就把真实下标和元素绑在一起返回，视图直接用 `row.index`，不再反查。同时把行的 `.id()` 从下标改成元素自己的 id（`IndexedRow.id` 转发 `element.id`），这样 `ForEach` 的身份、`.id()` 标记、`ScrollViewReader` 的滚动目标三者完全一致——用下标做视图身份会在列表重排时让 SwiftUI 把行认错，是另一个隐患。补了回归测试 `testGroupedResultsCarryIndicesThatMatchResults`，跨多个日期分组断言下标唯一且指回同一项。

**2. 粘贴 20 秒后静默清空用户剪贴板**

`PasteSimulator.commitPaste` 里有"粘贴 N 秒后，若剪贴板没被别人改过就清空它"的逻辑。这个最早是为敏感内容加的，但 V7 之后软隐藏/加密隐藏内容改走 `typeDirectly`（完全不碰剪贴板）——**真正需要保护的路径已经不经过这里了**。剩下会走到 `commitPaste` 的只有「公开片段」和「剪贴板历史条目」：前者按定义就不敏感，后者是用户主动挑出来要放进剪贴板的。于是这个逻辑退化成纯副作用：用户粘完想再手动 ⌘V 一次，会发现剪贴板莫名空了。删掉。

**3. 浮层开着时会吃掉管理窗口的按键**

`FloatingPanel` 用 `NSEvent.addLocalMonitorForEvents` 拦截方向键/Esc/Tab，但守卫条件写的是 `self.isVisible`。这是个 **App 级**监听器，所以只要浮层还开着，本 App **所有**窗口的这些按键都会被它吃掉（例如管理窗口的新建片段表单里按 Esc 关不掉）。改判 `self.isKeyWindow`。

**4. Enter 可靠性硬化（预防性，根治之前反复出现两次的同类 bug）**

回车原来只走搜索框的 `.onSubmit`，这要求搜索框真正拿到键盘第一响应者——而这在浮层首次呼出等时序下并不保证（这正是之前两次"选好内容按回车没反应"的根因；方向键一直正常，恰恰因为它走的是窗口级监听）。把 Return/小键盘 Enter 也放进 `FloatingPanel` 的窗口级监听（`onReturn` → `ClipPowerPanelViewModel.confirmSelection()` 路由到当前 Tab），回车和方向键的可靠性彻底一致，不再依赖焦点状态。因为事件被监听器吃掉（返回 `nil`），不会和 `.onSubmit` 重复触发；`.onSubmit` 保留作为监听器未安装时的兜底。

**5. 「清空」按钮无二次确认**

浮层搜索框旁边一个小小的「清空」，一点就不可撤销地删掉全部历史（实测 192 条）。改成"点一次变确认态、再点一次才执行"的行内两步确认——浮层是无边框 `.nonactivatingPanel`，弹 `.alert` 在这种窗口上表现不稳定，所以不用弹窗；且每次重新呼出浮层都回到未确认态，避免上次点了没确认、下次一打开就停在"确认清空？"上被误点。

### App 图标：SwiftUI 手工设计，不依赖外部 AI 生图

用户要求做一个和 ClipPower 主题相关的图标。查了一遍本机可用的设计类 skill（`design-shotgun`/`gstack design` 工具），发现走 AI 生图需要先配置 OpenAI API Key（`~/.gstack/openai.json`），用户明确选择"不配 key，我用 SwiftUI 手工设计"。

设计思路：蓝色三段对角线渐变的 squircle（天蓝 → 蓝 → 深蓝紫，macOS Big Sur+ 风格的方形圆角图标，不依赖 Assets.xcassets，走本项目一直用的"普通 `.icns` 资源"路线）+ 白色剪贴板（本体 + 顶部夹子）+ 黄色渐变闪电，一层对应"Clip"（剪贴板），一层对应"Power"（闪电，也呼应快捷键瞬间呼出的产品体验）。闪电故意比剪贴板画得更大、稍微越出边缘，避免两个图形完全内嵌显得呆板。

技术路径：写一个独立的 SwiftUI View（不在主项目里，临时脚本 `/tmp/clippower-icon/IconRender.swift`），用 `ImageRenderer`（macOS 13+）在纯 `swift` 脚本环境里离线渲染成 1024×1024 PNG——`ImageRenderer.nsImage` 是 `@MainActor` 隔离的 API，脚本顶层代码默认是非隔离上下文，用 `MainActor.assumeIsolated { ... }` 包一层即可（脚本本来就跑在主线程，只是要满足 Swift 6 的隔离检查）。再用系统自带的 `sips` 生成 iconset 要求的 10 个尺寸（`icon_16x16.png` 到 `icon_512x512@2x.png`），`iconutil -c icns` 打成 `AppIcon.icns`，放进 `ClipPower/Resources/`，`Info.plist` 加 `CFBundleIconFile = AppIcon` 引用它——沿用项目最初就定的"不建 Assets.xcassets，直接用 loose `.icns`"的路子，不用改 `project.yml`。

菜单栏状态栏图标（`AppDelegate.setupStatusItem` 里的 `NSImage(systemName: "doc.on.clipboard")`）**没有换成这个彩色图标**——菜单栏图标按 macOS 惯例是单色模板图标（跟随系统深浅色、选中态自动反色），换成彩色 App 图标会破坏这个约定，也会显得比其他菜单栏图标突出。App 图标和菜单栏图标是两个独立的设计位置，各自用各自该用的风格。

中途按用户反馈改过一版：闪电原来带 `.shadow(color: .black.opacity(0.25), ...)`，在 1024px 渲染时看起来还行，但那团模糊阴影在小尺寸/用户实际截图里糊成一片深色，被反馈成"闪电上面的乌云"——去掉了。背景从两段色改成三段色渐变（多插一个中间色阶），层次感更明显，闪电本身也顺手加了一个竖直方向的浅黄→深黄渐变。

### 菜单栏状态栏图标换成单色剪影版

App 图标定下来之后，用户追问"能进 Dock 吗"，追问下去才澄清真实需求：不是要改 `LSUIElement`（那会改变"纯菜单栏工具"的产品形态，属于另一个决策），是想把**菜单栏状态栏图标**从系统 SF Symbol `doc.on.clipboard` 换成新设计的样子。

问了一下要哪种风格：彩色原图缩小 vs 单色剪影 template 图标，用户选了单色剪影——这也是对的选择，`NSStatusItem` 的图标按 macOS 惯例应该是 `isTemplate = true` 的单色图标，系统会根据深浅色菜单栏、鼠标悬停/选中状态自动决定颜色（自动反色），彩色图标做不到这一点，会跟其他系统菜单栏图标格格不入。

实现：另写一个 SwiftUI 视图 `MenuBarIconView`（同一套构图——剪贴板轮廓 + 闪电，去掉渐变和颜色，剪贴板改成描边而不是填充，纯色块在这么小的尺寸下会糊成一团黑方块），用同样的 `ImageRenderer` 离线渲染成 72×72 PNG（对应 18pt @2x 视网膜分辨率），存进 `ClipPower/Resources/StatusIcon.png`。`AppDelegate.statusBarIcon()` 加载它、设 `isTemplate = true`，并**显式**把 `.size` 设成 `18×18pt`——不依赖 AppKit 按位图像素尺寸反推逻辑大小（那样会被当成 72pt 的图标，比菜单栏其它图标大好几倍），加载失败时兜底回退到原来的 SF Symbol。

### 超长内容让界面卡死 11.5 秒（实测定位，不是猜的）

用户反馈"按快了界面卡顿"，而且补充了关键线索："每次到某一条内容那里就卡住了"——说明不是普遍的性能问题，而是**某个特定条目**触发的。

前一轮我先猜"是国际化引入的 `String(localized:)` bundle 查表 + 每项 `Calendar.current` 太贵"，把它们从循环里提出来预算一次。**写了个临时基准实测，证伪了这个假设**：192 条分组一次，旧实现 1.17ms、新实现 1.17ms，毫无变化。于是改成在真实按键路径上插桩（`DispatchQueue.main.async` 排在当前 runloop 之后执行，而 SwiftUI 的视图更新+布局就在这一轮里，两者时间差近似等于"这次按键让主线程忙了多久"），同时打印每次详情栏重建时的文本长度。日志立刻给出答案：

```
[PERF] 详情栏重建，文本长度 39872
[PERF] ↓ 按键→渲染完成 11526.8 ms      ← 11.5 秒
[PERF] ↓ 按键→渲染完成 18.7 ms         ← 其他条目都是 15~40ms
```

根因：**SwiftUI 的 `Text` 没有惰性布局**。详情栏把整条内容原样塞进 `ScrollView { Text(...).textSelection(.enabled) }`，于是 SwiftUI 要为全部 39872 个字符做完整排版，`.textSelection(.enabled)` 还要为每个字形建立选择几何。而预览区只有 ~220pt 高，肉眼最多看到几百字符——其余 3.9 万字符的排版成本全是白烧。

修复（`ClipPower/Services/DisplayTruncation.swift`）：预览只渲染前 `DisplayLimit.preview`（2000）字符，列表行标题只取前 `DisplayLimit.rowTitle`（200）字符——行标题那条尤其必要，因为调用方还要对它做换行符替换这类 O(n) 变换，而行 body 会被反复求值。被截断时界面上显示"预览已截断，粘贴时仍是完整内容"，避免用户误以为内容只有这么多。**粘贴/导出/搜索/去重走的永远是完整内容**，这条边界有单元测试守着（断言原字符串长度未被改动）。Snippets 面板的内容预览有完全相同的隐患（长片段一样会卡死），一并修了。

顺带两个同源的渲染成本：
- **图片重复解码**：`NSImage(data:)` 每次都真的解一遍 PNG，而行 body / 详情栏在滚动和选中变化时反复求值——选中一张图后每按一次方向键都要完整重解一次。加了 `ClipboardImageCache`（`NSCache`，内存紧张时系统自动回收，丢了只是重解一次，无正确性问题）。
- **分组结果每次渲染重算**：`groupedResults` 原来是计算属性，而 SwiftUI 的 body 在**任何** `@Published` 变化时都会重算——包括每按一次方向键改 `selectedIndex`。分组只取决于 `results`，和选中项无关，所以改成在 `reload()` 里算一次存起来。这一项实测只值 1.17ms（不是卡顿主因），但按键路径上的无谓开销该去掉。

### 粘贴过的条目排到最前面

用户要求：在浮层里回车粘贴某条剪贴板历史后，把它排到列表最前面（最近使用优先）。

这件事和前面"反复粘贴同一条"的死循环看着矛盾，其实不冲突——那个 bug 的真正问题是**高亮行和实际粘贴的条目不一致**（`?? 0` 反查兜底导致），而不是"被顶到最前"本身。反查修掉之后，两者永远一致，"最近使用排最前 + 重新呼出时默认选中第一项"就是自洽的：连着按回车会重复粘贴最近用过的那条，这正是"最近使用优先"应有的语义。

实现选择：新增 `ClipboardHistoryStore.touch(id:)`，在 `ClipboardHistoryViewModel.confirmSelection()` 里显式调用（和 `QuickPanelViewModel` 粘贴片段时调 `store.recordUsage` 对称）。**没有**改成"去掉 `suppressNextChange`、让剪贴板监控顺便把它记一遍"——那样有三个问题：① 依赖 0.5s 轮询，时机不确定；② 语义上是在假装"用户复制了东西"，而用户其实是在粘贴；③ 粘贴图片/文件时会白白把剪贴板重新读一遍、图片再编码一次 PNG。

字段选择：直接改 `createdAt`，不新增 `lastUsedAt` 列。因为这张表的排序和日期分组（今天/昨天/本月/更早）全以 `createdAt` 为准，而 V7 的去重逻辑本来就已经在"同样内容再被复制一次"时把它改成当前时间了——这个字段的语义早就是"最后一次见到这份内容的时间"。沿用同一字段能和去重保持一致，代价是详情里的"记录于"显示的是最后一次使用时间而非首次复制时间；对剪贴板历史这个场景可以接受，也避免了一次 schema 迁移。

### 剪贴板历史"反复粘贴同一条"的自我循环

另一个独立的真 bug：用户不断按快捷键调出剪贴板历史、不选择直接按 Enter，结果反复粘贴的都是同一条旧内容。

根因不是"粘贴错了"，是一个自我循环：粘贴剪贴板历史里的旧内容时，必须先把它写回系统剪贴板（⌘V 本身就是读剪贴板），而我们自己的 `ClipboardMonitor` 每 0.5s 轮询 `changeCount`，会把这次写入当成一次**新的复制事件**又记一遍——按 V7 的全局去重逻辑，这条历史被"挪到最前面"。再加上每次重新打开面板都会 `reset()` 把 `selectedIndex` 归零，于是形成死循环：打开 → 不选 → 粘贴 `results[0]` → 它被顶到最前 → 再打开 → 第一项还是它 → 再粘贴同一条。

修复：`ClipboardMonitor` 新增 `suppressNextChange()`，在 `AppDelegate` 完成一次"重新粘贴历史条目"的模拟粘贴之后立刻调用，把监控内部记录的 `lastChangeCount` 同步到最新值。因为写剪贴板、发按键、调 `suppressNextChange` 全在主线程上同步完成，轮询的 `Timer` 不可能插在中间，所以这个同步是可靠的。

---

顺带修了两个因为文案变成"运行时才能确定"而暴露出的测试脆弱点：`DateSectionGroupingTests`/`QuickPanelViewModelTests` 原来直接断言硬编码中文字面量（"今天"/"昨天"），现在 `DateSectionGrouping.title(for:)` 会按运行环境语言解析，测试机的语言不一定是中文——改成断言 `String(localized: "今天")`，跟生产代码走同一条本地化解析路径，不再硬编码某个语言的具体文案。

### 导出兼容 Raycast 格式

之前只做了"导入 Raycast Snippets JSON"这一个方向，用户追问"导出兼容 Raycast 了吗"才发现导出方向一直没做——`ImportExportService.export` 只有我们自己的 `ExportPackage` 格式（带 `formatVersion`/加密信息，是为了保留隐藏能力设计的，Raycast 的纯数组格式装不下这些）。

新增 `ImportExportService.exportRaycastSnippets()`：只导出 `visibility == .normal` 的片段，映射成 `[{name, text, keyword}]` 数组。**故意不包含软隐藏/加密隐藏内容**——Raycast 格式本身没有任何保护机制，把隐藏内容明文写进这种格式里等于绕开隐藏功能直接暴露明文，这是一个安全边界，不是遗漏。UI 上在「导入/导出」面板把原来单独的「从 Raycast 导入」卡片改名成「与 Raycast 互通」，加了一个并排的"导出为 Raycast 格式..."按钮，文案里说明了只导出公开片段的原因。

### 导出"成功"提示比真正保存还早弹出的 bug

加了这个导出按钮之后，用户马上发现一个问题：在系统 `NSSavePanel` 里还没点 Save，"导入/导出结果"弹窗就已经显示"导出成功"/"已导出为 Raycast 格式"了。

根因：`ImportExportViewModel.export()`/`exportRaycastFile()` 在内存里把 JSON 数据生成出来的那一刻，就直接把 `statusMessage` 设成了成功文案；而调用方 `ImportExportView` 的流程是先拿到这份数据，再弹出 `NSSavePanel` 让用户选保存位置——"提示结果"这一步发生在用户真正点击 Save**之前**。数据生成本身几乎是瞬间完成的（纯内存 JSON 编码，不涉及磁盘/网络），所以看起来就是"面板还没出现，成功提示先跳出来了"。这个时序问题其实从最早的 `export()` 实现起就存在，只是之前用一行不起眼的 caption 展示，不容易被注意到；换成醒目的 `.alert` 弹窗后，问题一下就暴露出来了。

修复：把"设置成功文案"这一步从 ViewModel 的 `export`/`exportRaycastFile` 里删掉——这两个方法现在只负责生成数据，失败才设 `statusMessage`（这类错误跟保存面板无关，提前报是对的）。改成 `ImportExportView` 里等 `NSSavePanel.runModal() == .OK` 且 `data.write(to:)` 真正写盘成功之后，才把 `viewModel.statusMessage` 设成功文案；写盘失败会捕获异常改成失败文案；用户在保存面板点 Cancel 则什么提示都不弹（本来就没有产生任何"结果"）。普通导出和 Raycast 格式导出两个入口都这样改了。

### 用 /design-review 做的一次布局审视：三栏 NavigationSplitView 里长期空着的第三栏

`/design-review` 这个 skill 本身是给 Web 前端（浏览器 DOM/CSS 自动化）设计的，ClipPower 是纯原生 SwiftUI/AppKit 菜单栏应用，没有网页、没有 DOM，这个仓库也不是 git 仓库——`$B` 浏览器自动化、CSS 提取、per-fix commit 这些环节都不适用。改成源码级审查（`grep` 统计 `Views/` 下的字体/间距/颜色用量）+ 对话里已有的真实截图。

审查结论：字体全部用系统语义字体（`.headline`/`.caption`/`.body`），颜色全部用 `.secondary`/`Color.accentColor` 语义色，没有硬编码 hex——这两点是原生 App 的正确做法（Web 版 AI slop 检测里"别用默认字体系统"这条规则不适用于原生 App，反而这里是优点）。间距数值比较零散（1/2/3/4/5/6/8/10/12/14/20 混用），是 Polish 级别的瑕疵，影响很小没有动。

真正发现的结构性问题：`LibraryView` 用的三栏 `NavigationSplitView`（侧栏/内容/详情），但「回收站」「设置」「导入/导出」这三个场景下第三栏（详情）一直是空的灰色区域，只有「全部片段」真正用到"列表+详情"的三栏关系——这也解释了为什么之前两次单独加宽"侧栏"和"内容列"都没有从根本上解决"看起来很挤"的感觉：真正浪费的是那块常年空着的第三栏，而不是列宽数字本身。

和用户确认后，改成两栏结构：`NavigationSplitView` 只保留 sidebar + detail 两个闭包，「回收站/设置/导入导出」直接把各自的视图放进 `detail:`（这样能用满除侧栏外的全部宽度）；「全部片段」原来靠 SwiftUI 原生三栏给的"列表+详情"关系，改成在 `detail:` 里手动拼一个 `HStack`（`SnippetListView` 固定宽度 260pt + `Divider()` + `SnippetDetailView`）。代价是这个列表栏不再能像原生三栏那样被用户拖拽调宽（固定 260pt，和浮层里 Snippets/剪贴板历史列表同宽，保持全局一致），换来的是其它三个场景终于能用满剩余宽度，不再有那块永远空着的灰色区域。
