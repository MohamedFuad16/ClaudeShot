import AppKit
import SwiftUI

/// A transparent, click-through, always-on-top panel that spans the active
/// screen and hosts the capture overlay animation. It stays ordered front for
/// the app's lifetime; the SwiftUI content shows/hides itself per phase.
@MainActor
final class CapturePanel {
    private let panel: NSPanel

    init(controller: AppshotController) {
        panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: CaptureOverlayView(controller: controller))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    /// Position over the screen containing the pointer and order front.
    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }
}
