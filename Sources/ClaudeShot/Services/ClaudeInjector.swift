import AppKit
import ApplicationServices

/// Delivers a captured appshot into a target app: copy the PNG to the
/// pasteboard, bring the target forward, focus its composer, and synthesize ⌘V.
@MainActor
final class ClaudeInjector {
    /// Whether we're allowed to post synthetic keystrokes (Accessibility perm).
    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Copies the image to the clipboard and (if `autoPaste`) pulls the target
    /// app to the foreground, focuses its text input, and presses ⌘V.
    func deliver(pngData: Data, to target: DeliveryTarget, autoPaste: Bool) {
        copyToPasteboard(pngData)
        guard autoPaste else { return }

        Task { [weak self] in
            guard let self else { return }
            guard let pid = await self.bringToFront(bundleID: target.bundleID) else {
                NSLog("ClaudeShot: could not find or launch \(target.bundleID); image left on clipboard")
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)

            // Focus the composer so ⌘V lands even if the user never clicked it.
            if await !self.ensureComposerFocused(pid: pid) {
                NSLog("ClaudeShot: couldn't focus a text input; pasting anyway")
            }
            try? await Task.sleep(nanoseconds: 90_000_000)

            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                self.postCommandV()
            } else {
                // macOS refused to give us the foreground (cooperative
                // activation). Deliver the paste straight to the app so it
                // never fires into whatever the user is looking at.
                NSLog("ClaudeShot: target not frontmost; posting ⌘V directly to pid \(pid)")
                self.postCommandV(toPid: pid)
            }
        }
    }

    private func copyToPasteboard(_ pngData: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        if let image = NSImage(data: pngData) {
            pasteboard.writeObjects([image])
        }
    }

    // MARK: - Activation ladder

    /// Brings the app forward using escalating strategies; returns its pid.
    /// From a background agent, plain `activate()` is often refused under
    /// macOS 14+ cooperative activation — the AX raise is what actually works.
    private func bringToFront(bundleID: String) async -> pid_t? {
        var app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first

        if app == nil {
            await launch(bundleID: bundleID)
            let deadline = Date().addingTimeInterval(6)
            while app == nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
                app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            }
        }
        guard let app else { return nil }
        let pid = app.processIdentifier

        // 1) Polite request. Kept short: under macOS 14+ cooperative
        // activation an accessory app's activate() is often silently refused,
        // and waiting the full budget here is the main source of paste lag.
        // The AX raise below is what actually works, and if we still can't get
        // frontmost the paste is posted straight to `pid` — so being impatient
        // here is safe.
        app.activate(options: [.activateAllWindows])
        if await waitUntilFrontmost(pid: pid, timeout: 0.4) { return pid }

        // 2) Accessibility: set frontmost + raise the window.
        axRaise(pid: pid)
        if await waitUntilFrontmost(pid: pid, timeout: 0.6) { return pid }

        // 3) Launch Services re-open with explicit activation.
        await launch(bundleID: bundleID)
        _ = await waitUntilFrontmost(pid: pid, timeout: 1.2)
        return pid
    }

    private func launch(bundleID: String) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func axRaise(pid: pid_t) {
        guard accessibilityTrusted else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement], let window = windows.first {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    private func waitUntilFrontmost(pid: pid_t, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return true
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    // MARK: - Composer focus (Accessibility)

    /// Makes sure a text input inside the target app has keyboard focus.
    /// Chromium often ignores AX focus writes, so this escalates to a real
    /// mouse click on the composer (bottom-most text input), restoring the
    /// cursor afterwards. Retries because Electron builds its AX tree lazily.
    private func ensureComposerFocused(pid: pid_t) async -> Bool {
        guard accessibilityTrusted else { return false }
        let appElement = AXUIElementCreateApplication(pid)

        // Wake Electron's dormant AX tree (legacy + modern flags; harmless elsewhere).
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // Already good? (e.g. the user had clicked the composer earlier.)
        if focusedElementIsTextInput(appElement) { return true }

        // Locate the composer ONCE. Walking Electron's AX tree is thousands of
        // cross-process calls; re-walking it every retry was the dominant paste
        // delay. Cache it and only re-walk if it wasn't there yet (lazy tree).
        var composer = findComposer(appElement: appElement)

        let attempts = 3
        for attempt in 0..<attempts {
            if let composer {
                // 1) Ask nicely via AX.
                AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                try? await Task.sleep(nanoseconds: 90_000_000)
                if focusedElementIsTextInput(appElement) { return true }

                // 2) Chromium refused — click the composer like a human would.
                if clickCenter(of: composer) {
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    if focusedElementIsTextInput(appElement) { return true }
                }
            }

            // Only pay the settle-and-retry cost when there are tries left, and
            // only re-walk the tree if we never found the composer (Electron
            // builds its AX tree lazily on first access).
            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if composer == nil { composer = findComposer(appElement: appElement) }
            }
        }
        return focusedElementIsTextInput(appElement)
    }

    private func focusedElementIsTextInput(_ appElement: AXUIElement) -> Bool {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        return isTextInput(focused as! AXUIElement)
    }

    /// Finds the chat composer: of all text inputs in the front window, the
    /// bottom-most one (chat composers live at the bottom of the window).
    private func findComposer(appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        var window: AXUIElement?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success {
            window = (windowRef as! AXUIElement)
        } else {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {
                window = windows.first
            }
        }
        guard let window else { return nil }

        var inputs: [AXUIElement] = []
        var visited = 0
        collectTextInputs(in: window, depth: 0, visited: &visited, into: &inputs)
        NSLog("ClaudeShot: found \(inputs.count) text input(s) in target window")
        guard !inputs.isEmpty else { return nil }

        return inputs.max { bottomEdge(of: $0) < bottomEdge(of: $1) }
    }

    private func collectTextInputs(in element: AXUIElement, depth: Int, visited: inout Int, into inputs: inout [AXUIElement]) {
        // Bounded search: Chromium AX trees nest deeply and can be huge.
        guard depth < 24, visited < 2500, inputs.count < 8 else { return }
        visited += 1

        if isTextInput(element) {
            inputs.append(element)
            return
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            collectTextInputs(in: child, depth: depth + 1, visited: &visited, into: &inputs)
        }
    }

    private func isTextInput(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return false }
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String || role == kAXComboBoxRole as String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func bottomEdge(of element: AXUIElement) -> CGFloat {
        guard let frame = frame(of: element) else { return -.infinity }
        return frame.maxY
    }

    /// Posts a real left-click at the element's center (global, top-left-origin
    /// coordinates — the same space CGEvent uses), then restores the cursor.
    private func clickCenter(of element: AXUIElement) -> Bool {
        guard let frame = frame(of: element), frame.width > 1, frame.height > 1 else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let restore = CGEvent(source: nil)?.location

        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        NSLog("ClaudeShot: clicked composer at (\(Int(center.x)), \(Int(center.y)))")

        if let restore {
            CGWarpMouseCursorPosition(restore)
        }
        return true
    }

    // MARK: - Paste

    private func postCommandV(toPid pid: pid_t? = nil) {
        guard accessibilityTrusted else {
            NSLog("ClaudeShot: no Accessibility permission; image left on clipboard for manual ⌘V")
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        if let pid {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
