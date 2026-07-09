<h1 align="center">ClaudeShot</h1>

<p align="center">
  <strong>A native macOS menu bar helper that screenshots the frontmost window and pastes it straight into Claude — with one global hotkey.</strong>
</p>

<p align="center">
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Language-Swift_5.10+-orange.svg?style=flat-square" alt="Swift"/></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/Platform-macOS_14.0+-black.svg?style=flat-square&logo=apple" alt="macOS"/></a>
  <a href="#-license"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Dependencies-none-brightgreen.svg?style=flat-square" alt="No Dependencies"/></a>
  <a href="#"><img src="https://img.shields.io/badge/UI-SwiftUI_+_ScreenCaptureKit-purple.svg?style=flat-square" alt="SwiftUI"/></a>
</p>

<p align="center">
  <a href="#-overview">Overview</a> •
  <a href="#-key-features">Key Features</a> •
  <a href="#%EF%B8%8F-how-it-works">How It Works</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-permissions">Permissions</a> •
  <a href="#%EF%B8%8F-development">Development</a> •
  <a href="#-license">License</a>
</p>

---

## 📖 Overview

**ClaudeShot** ports Agent Swarm's **Appshot** capture toolkit and wires it into the **Claude desktop app** (`com.anthropic.claudefordesktop`). It runs as a background **menu-bar accessory** — no Dock icon, negligible footprint, zero external dependencies.

Press the global hotkey (**⇧⌘2** by default) anywhere on your Mac and ClaudeShot captures the **frontmost window** via ScreenCaptureKit, plays a polished flash → landing → settling animation, copies the PNG to your clipboard, then brings Claude forward and synthesizes **⌘V** into its composer. The screenshot lands in Claude before you've let go of the keys.

If Accessibility isn't granted, the paste step is skipped — the image is still on your clipboard, so you just click Claude's composer and press ⌘V yourself.

---

## ✨ Key Features

### ⌨️ Global Hotkey Capture
- System-wide Carbon hotkey fires from **any** app, not just when ClaudeShot is focused.
- Default **⇧⌘2**, with presets for **⇧⌘A**, **⌥⌘A**, **⌃⌥C**, and **⇧⌘V** — pick one in Preferences and it's persisted across launches.
- Also available as a menu item (**Take Appshot**) for mouse-only use.

### 📸 Frontmost-Window Screenshots
- Captures the **frontmost window** at native Retina scale using **ScreenCaptureKit**.
- Records source metadata (app name, window title, bundle id, pid) so delivery targets the right window.
- PNGs are written to a capture directory **and** placed on the system pasteboard.

### 🤖 Paste-Into-Claude Delivery
- Automatically activates the Claude desktop app, focuses its composer, and presses **⌘V** for you.
- Works even from a background agent: if the target isn't frontmost, the paste is posted **directly to Claude's pid** so it always lands.
- Graceful fallback — no Accessibility permission means the image simply stays on the clipboard for a manual paste.

### 🎬 Animated Capture Visuals
- A floating overlay panel drives a four-phase state machine: **flash → landing → settling → ready**.
- Liquid-glass capture overlay with a camera-shutter flash pulse.
- Adjustable **flash speed** via a *Faster ⇄ Smoother* slider in Preferences.

### 🔊 Selectable Capture Sound
- Choose a capture sound (e.g. **Pop**) or turn it off entirely — your choice is remembered.

### 🌐 Bilingual Interface
- Full **English / 日本語** localization, switchable live from Preferences.

### 🧊 Native Menu-Bar UI
- Lives in the menu bar behind a `camera.viewfinder` SF Symbol — runs as an `LSUIElement` accessory with no Dock presence.
- Glass-card Preferences window for hotkey, sound, flash speed, language, and permission grants.

---

## ⚙️ How It Works

The SwiftUI menu-bar app orchestrates capture and delivery entirely through native macOS system APIs:

```
[ Global Hotkey ⇧⌘2 ]  ──or──  [ Menu ▸ Take Appshot ]
       │
       ├─► [1] Resolve the frontmost window (ScreenCaptureKit + source metadata)
       ├─► [2] Play flash pulse, capture at native Retina scale → PNG
       ├─► [3] Copy PNG to the system pasteboard
       ├─► [4] Activate Claude (com.anthropic.claudefordesktop) + focus composer
       ├─► [5] Synthesize ⌘V (or post directly to Claude's pid if backgrounded)
       └─► [6] Run landing → settling → ready overlay animation + capture sound
```

| Piece | File |
|---|---|
| Menu-bar app + hotkey wiring | `Sources/ClaudeShot/App/ClaudeShotApp.swift` |
| Capture engine + phase machine | `Sources/ClaudeShot/Services/AppshotController.swift` |
| Paste-into-Claude delivery | `Sources/ClaudeShot/Services/ClaudeInjector.swift` |
| Global hotkey (Carbon) | `Sources/ClaudeShot/Services/GlobalHotKeyController.swift` |
| Animated capture visuals | `Sources/ClaudeShot/Views/AppshotVisuals.swift` |
| Floating overlay panel | `Sources/ClaudeShot/Views/CapturePanel.swift` + `CaptureOverlayView.swift` |
| Preferences (hotkey / sound / permissions) | `Sources/ClaudeShot/Views/PreferencesView.swift` |

---

## 🚀 Installation

### 1. Clone the repository
```bash
git clone https://github.com/MohamedFuad16/ClaudeShot.git
cd ClaudeShot
```

### 2. Build, sign & run
```bash
./script/build_and_run.sh          # build .app bundle, sign, install to /Applications, launch
```

The script builds with SwiftPM, wraps the binary in a proper `.app` bundle (so permissions stick to the bundle id `com.mfuad.ClaudeShot`), ad-hoc signs it, installs it into `/Applications`, and launches it as a menu-bar accessory. Look for the **camera icon** in your menu bar.

### 3. Other modes
```bash
./script/build_and_run.sh build    # build + install only, no launch
./script/build_and_run.sh verify   # build + launch + confirm the process is running
./script/build_and_run.sh logs     # build + launch + stream unified logs
```

> **Signing:** with an `Apple Development` / `Developer ID` identity in your keychain the script uses it automatically (permissions survive rebuilds). Without one it falls back to ad-hoc signing — screen recording / accessibility grants may need re-approving after each rebuild. Override with `CLAUDESHOT_SIGN_IDENTITY`.

Requires **macOS 14+** and a Swift toolchain (Xcode or Command Line Tools).

---

## 🔐 Permissions

ClaudeShot needs two macOS privacy permissions, both grantable from the menu or Preferences:

1. **Screen Recording** — to capture windows. Requested on your first appshot.
2. **Accessibility** — to press ⌘V into Claude for you. Grant it via the menu-bar item **"Grant Accessibility Permission…"** or the Preferences window.

Because a real, signed `.app` bundle is installed into `/Applications`, both permissions stick to the bundle id `com.mfuad.ClaudeShot` across rebuilds (with a signing identity present). Temp-dir apps can't be added to the privacy lists — that's why the build script installs to `/Applications`.

---

## 🛠️ Development

Built entirely in Swift with **zero external dependencies** — no CocoaPods, no third-party SPM packages, just Apple frameworks compiled by SwiftPM.

| | |
|---|---|
| **Language** | Swift 5.10+ |
| **UI** | SwiftUI (`MenuBarExtra`, glass-card Preferences) |
| **Frameworks** | ScreenCaptureKit, AppKit, Carbon (hotkeys) |
| **Build** | SwiftPM (`swift build -c release`) |
| **Min OS** | macOS 14.0 (Sonoma) |
| **Dependencies** | None |
| **Runs as** | Menu-bar accessory (`LSUIElement`, no Dock icon) |

### Project Structure
```
Sources/ClaudeShot/
├── App/
│   ├── ClaudeShotApp.swift         — MenuBarExtra app, hotkey wiring, menu items
│   └── SettingsPresenter.swift     — Preferences window presentation
├── Services/
│   ├── AppshotController.swift     — Capture pipeline + flash→ready phase machine
│   ├── ClaudeInjector.swift        — Pasteboard + activate Claude + synthesize ⌘V
│   ├── GlobalHotKeyController.swift — System-wide Carbon hotkey registration
│   ├── AppSettings.swift           — Delivery target, sound, flash-speed persistence
│   ├── PermissionsModel.swift      — Screen Recording / Accessibility state
│   └── Localization.swift          — English / 日本語 strings
├── Models/
│   └── AppshotModels.swift         — Source metadata, hotkey presets
└── Views/
    ├── PreferencesView.swift       — Hotkey, sound, flash, language, permissions
    ├── AppshotVisuals.swift        — Animated capture visuals
    ├── CapturePanel.swift          — Floating overlay panel
    ├── CaptureOverlayView.swift    — Capture overlay rendering
    └── GlassSupport.swift          — Liquid-glass helpers

script/build_and_run.sh            — Build, bundle, sign, install to /Applications, launch
Package.swift                      — SwiftPM manifest (macOS 14, executable target)
```

---

## 📝 License

This project is licensed under the MIT License.

Developed with ❤️ by **[MohamedFuad16](https://github.com/MohamedFuad16)**. Contributions and issues are always welcome!
