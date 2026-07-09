# ClaudeShot

A background **menu-bar** macOS helper that ports Agent Swarm's **Appshot**
screenshot toolkit and wires it into the **Claude desktop app**
(`com.anthropic.claudefordesktop`).

Press the global hotkey (**⇧⌘2** by default) anywhere on your Mac →
ClaudeShot captures the **frontmost window**, plays the capture animation, then
brings Claude forward and pastes the screenshot straight into its composer.

## How it works

| Piece | File |
|---|---|
| Menu-bar app + hotkey wiring | `Sources/ClaudeShot/App/ClaudeShotApp.swift` |
| Capture engine + phase machine | `Sources/ClaudeShot/Services/AppshotController.swift` |
| Paste-into-Claude delivery | `Sources/ClaudeShot/Services/ClaudeInjector.swift` |
| Global hotkey | `Sources/ClaudeShot/Services/GlobalHotKeyController.swift` |
| Animated capture visuals | `Sources/ClaudeShot/Views/AppshotVisuals.swift` |
| Floating overlay panel | `Sources/ClaudeShot/Views/CapturePanel.swift` + `CaptureOverlayView.swift` |
| Hotkey / permission preferences | `Sources/ClaudeShot/Views/PreferencesView.swift` |

The captured PNG is copied to the system clipboard **and** ClaudeShot activates
Claude and synthesizes **⌘V** into it. If Accessibility permission isn't
granted, the paste is skipped but the image is still on the clipboard — just
click Claude's composer and press ⌘V yourself.

## Permissions

1. **Screen Recording** — to capture windows. Granted on first capture.
2. **Accessibility** — to press ⌘V into Claude for you. Grant it from the
   menu-bar menu ("Grant Accessibility Permission…") or Preferences.

Because a real, signed `.app` bundle is produced, both permissions stick to the
bundle id `com.anthropic` … `.ClaudeShot` across rebuilds (with a signing
identity present).

## Build & run

```sh
./script/build_and_run.sh          # build .app bundle, sign, launch (menu-bar only)
./script/build_and_run.sh verify   # build + launch + confirm it's running
```

Runs as a menu-bar accessory (no Dock icon). Look for the camera icon in the
menu bar. Requires macOS 14+ and a Swift toolchain.
# ClaudeShot
