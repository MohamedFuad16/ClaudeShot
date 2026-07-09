import AppKit
import Carbon.HIToolbox
import SwiftUI

/// "Record Shortcut…" button: click it, press any key combo, and that combo
/// becomes the global appshot hotkey. Esc cancels. Requires at least one of
/// ⌘/⌃/⌥ so a bare letter can't be hijacked system-wide.
struct HotKeyRecorderButton: View {
    @Bindable var controller: AppshotController
    @Bindable var localizer: Localizer
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Label(
                isRecording ? localizer.t("settings.recordingHint") : localizer.t("settings.recordShortcut"),
                systemImage: isRecording ? "record.circle.fill" : "record.circle"
            )
            .foregroundStyle(isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
        .glassButton()
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event // swallow handled keystrokes
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Returns true when the event was consumed (recorded or cancelled).
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }

        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return true
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= AppshotHotKey.command }
        if event.modifierFlags.contains(.shift) { modifiers |= AppshotHotKey.shift }
        if event.modifierFlags.contains(.option) { modifiers |= AppshotHotKey.option }
        if event.modifierFlags.contains(.control) { modifiers |= AppshotHotKey.control }

        // Shift alone isn't enough — the hotkey would fire while typing.
        guard modifiers & (AppshotHotKey.command | AppshotHotKey.control | AppshotHotKey.option) != 0 else {
            NSSound.beep()
            return true
        }

        let keyName = Self.keyName(for: event)
        controller.hotKey = AppshotHotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyName: keyName,
            displayName: AppshotHotKey.displayName(keyName: keyName, modifiers: modifiers)
        )
        stopRecording()
        return true
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static func keyName(for event: NSEvent) -> String {
        if let special = specialKeyNames[Int(event.keyCode)] { return special }
        let raw = event.charactersIgnoringModifiers ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Key\(event.keyCode)" : trimmed.uppercased()
    }
}
