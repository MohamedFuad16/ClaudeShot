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
            MenuContent(localizer: localizer)
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(localizer.t("menu.takeAppshot")) {
            ClaudeShotRuntime.capture()
        }
        .keyboardShortcut("2", modifiers: [.command, .shift])

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
