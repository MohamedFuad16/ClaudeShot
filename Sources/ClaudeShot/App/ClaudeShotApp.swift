import AppKit
import SwiftUI

@MainActor
enum ClaudeShotRuntime {
    static let localizer = Localizer.shared
    static let settings = AppSettings.shared
    static let injector = ClaudeInjector()
    static let controller = AppshotController(injector: injector, settings: settings, localizer: localizer)
    static let globalHotKeyController = GlobalHotKeyController()
    static let panel = CapturePanel(controller: controller)

    /// Single entry point for both the hotkey and the menu item.
    static func capture() {
        panel.present()
        controller.takeAppshot()
    }

    /// Shows just the flash pulse (for the flash-speed slider preview).
    static func previewFlash() {
        panel.present()
        controller.previewFlash()
    }
}

@main
struct ClaudeShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = ClaudeShotRuntime.controller
    @State private var localizer = ClaudeShotRuntime.localizer

    var body: some Scene {
        MenuBarExtra("ClaudeShot", systemImage: "camera.viewfinder") {
            MenuContent(localizer: localizer, controller: controller)
        }

        Settings {
            PreferencesView(
                controller: controller,
                localizer: localizer,
                settings: ClaudeShotRuntime.settings
            )
            .frame(width: 540, height: 620)
        }
    }
}

private struct MenuContent: View {
    @Bindable var localizer: Localizer
    @Bindable var controller: AppshotController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(localizer.t("menu.takeAppshot")) {
            ClaudeShotRuntime.capture()
        }
        .keyboardShortcut(menuShortcut)

        Divider()

        Button(localizer.t("menu.preferences")) {
            SettingsPresenter.present { openSettings() }
        }
        .keyboardShortcut(",", modifiers: .command)

        Button(localizer.t("menu.grantAccessibility")) {
            ClaudeShotRuntime.injector.requestAccessibilityIfNeeded()
        }

        Divider()

        Button(localizer.t("menu.quit")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Mirrors the registered global hotkey next to the menu item. Custom
    /// recorded keys that aren't single characters (F-keys, arrows) can't be
    /// expressed as a SwiftUI KeyEquivalent — the menu just shows no shortcut.
    private var menuShortcut: KeyboardShortcut? {
        let hotKey = controller.hotKey
        guard hotKey.keyName.count == 1,
              let char = hotKey.keyName.lowercased().first
        else { return nil }

        var modifiers: EventModifiers = []
        if hotKey.modifiers & AppshotHotKey.command != 0 { modifiers.insert(.command) }
        if hotKey.modifiers & AppshotHotKey.shift != 0 { modifiers.insert(.shift) }
        if hotKey.modifiers & AppshotHotKey.option != 0 { modifiers.insert(.option) }
        if hotKey.modifiers & AppshotHotKey.control != 0 { modifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(char), modifiers: modifiers)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar accessory app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        configureGlobalHotKey()
        _ = ClaudeShotRuntime.panel
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func configureGlobalHotKey() {
        let controller = ClaudeShotRuntime.controller
        let hotKeyController = ClaudeShotRuntime.globalHotKeyController
        hotKeyController.onPressed = {
            ClaudeShotRuntime.capture()
        }
        controller.hotKeyChanged = { hotKey in
            hotKeyController.register(hotKey)
        }
        hotKeyController.register(controller.hotKey)
    }
}
