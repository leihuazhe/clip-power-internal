# ClipPower

A native, Apple Silicon–only macOS menu bar utility that combines a Raycast‑style **Snippets manager** with a **Clipboard History** viewer — plus one thing Raycast doesn't have: the ability to hide or encrypt sensitive snippet content.

## Requirements

- macOS 13.0 (Ventura) or later
- **Apple Silicon only** — there's no Intel build
- Accessibility permission, granted on first launch (needed to paste for you and to power text expansion)

## Installation

1. Download the latest `.dmg` from the [Releases](../../releases) page and open it.
2. Drag `ClipPower.app` into the `Applications` shortcut in the same window.
3. The app isn't signed with a paid Apple Developer certificate, so Gatekeeper will initially refuse to open it ("ClipPower is damaged and can't be opened" / "unidentified developer"). Clear that flag once:
   ```sh
   xattr -cr /Applications/ClipPower.app
   ```
4. Open ClipPower. On first launch it asks for Accessibility permission — grant it in **System Settings → Privacy & Security → Accessibility**, or it won't be able to paste anything for you.

ClipPower has **no Dock icon** and doesn't appear in ⌘‑Tab — it lives entirely in the menu bar (look for the "C" icon at the top of your screen).

## Usage

### Global hotkeys

All three are rebindable from **Settings**.

| Hotkey | Action |
|---|---|
| ⌥ Space | Open the panel, on the **Snippets** tab |
| ⌘⇧V | Open the panel, on the **Clipboard History** tab |
| ⇥ | Switch tabs while the panel is open |
| ↑ / ↓ | Move the selection |
| ↩ Return | Paste the selected item and close the panel |
| Esc / click outside | Close the panel without pasting |

### Snippets

Click the menu bar icon → **All Snippets** to open the management window, where you create, edit, tag, and organize snippets. Each one has a visibility level:

| Visibility | Behavior |
|---|---|
| **Public** | Shown and searchable normally. |
| **Soft‑hidden** | Masked in lists and previews; no authentication needed to reveal. |
| **Encrypted‑hidden** | Encrypted with a Secure Enclave–backed key; revealing or pasting requires Touch ID (or your system password). |

Pasting a soft‑hidden or encrypted‑hidden snippet types it directly instead of going through the system clipboard, so it never ends up in ClipPower's own history — or any other clipboard manager's.

You can also trigger a snippet by typing its **keyword** anywhere on the system: the keyword you typed is deleted and replaced with the snippet's content, Espanso‑style. Encrypted‑hidden snippets don't participate in this, since expanding one shouldn't skip the Touch ID prompt.

### Clipboard History

Every piece of text, image, and file you copy is recorded automatically (up to 200 items, searchable). Copying the same content again — or pasting an older entry back out of history — moves that entry to the top instead of creating a duplicate.

### Import / Export

From the **Import/Export** section of the management window:

- **Native format** — a JSON package, optionally password‑protected. A password is required if it contains encrypted‑hidden snippets you want to restore on a *different* Mac; without one, encrypted content is bound to the device that exported it.
- **Raycast format** — imports or exports the plain `[{ "name", "text", "keyword" }]` array Raycast itself uses. Only public snippets go out this way, since the format has no concept of hiding or encryption.

Keyword conflicts on import can be skipped, overwritten, or kept as a duplicate — you choose per import.

### Settings

- Rebind any of the three global hotkeys.
- Switch the app language — English, 简体中文, or 日本語. ClipPower defaults to English regardless of your system language; changing it prompts a restart.
- View and clear your clipboard history.

## Privacy & security

- Everything is stored locally in SQLite (`~/Library/Application Support/ClipPower/`). Nothing is sent over the network.
- Encrypted‑hidden content uses AES‑GCM with a key wrapped by a Secure Enclave–backed key pair, gated by Touch ID (or your system password as a fallback).

## Building from source

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the `.xcodeproj` is generated, not checked in by hand.

```sh
xcodegen generate
xcodebuild -project ClipPower.xcodeproj -scheme ClipPower -configuration Release build
xcodebuild -project ClipPower.xcodeproj -scheme ClipPower -configuration Debug test   # run tests
```

Dependencies: [GRDB.swift](https://github.com/groue/GRDB.swift) (persistence) and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (global hotkeys), both resolved automatically via SwiftPM. See `docs/design.md` for the full technical design.

## License

Personal project. No license has been chosen yet — all rights reserved by the author.
