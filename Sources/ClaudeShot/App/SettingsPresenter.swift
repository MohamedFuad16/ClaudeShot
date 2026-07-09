import AppKit
import SwiftUI

/// Brings the Settings window to the foreground for a menu-bar (accessory) app.
/// Accessory apps can't own a front window, so we temporarily switch to a
/// regular activation policy while Settings is open, then revert on close.
@MainActor
enum SettingsPresenter {
    static func present(using openSettings: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let window = settingsWindow() else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            observeClose(of: window)
        }
    }

    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.styleMask.contains(.titled) && $0.isVisible && !($0 is NSPanel)
        }
    }

    private static func observeClose(of window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Revert to menu-bar-only once no titled window remains.
                if settingsWindow() == nil {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
