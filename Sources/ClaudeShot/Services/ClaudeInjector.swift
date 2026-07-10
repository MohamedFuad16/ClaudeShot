import AppKit
import ApplicationServices

/// Outcome of a delivery attempt, reported back to the controller so the UI
/// never claims success for a paste that didn't actually land in the target.
enum DeliveryOutcome {
    /// The attachment was verified to appear in the target's composer.
    case pasted
    /// The composer already holds the per-message image limit; nothing pasted.
    case limitReached(count: Int)
    /// The shot is on the clipboard but couldn't be auto-pasted.
    case clipboardOnly(reason: String)
    /// The target app couldn't be found or launched.
    case appUnavailable
    /// A newer capture superseded this delivery before it finished.
    case superseded
}

/// Delivers a captured appshot into a target app: copy the PNG to the
/// pasteboard, bring the target forward, focus its composer, press ⌘V, and
/// verify the attachment actually appeared before reporting success.
@MainActor
final class ClaudeInjector {
    /// Whether we're allowed to post synthetic keystrokes (Accessibility perm).
    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Deliveries are serialized: a new capture cancels the in-flight one and
    /// only writes the clipboard when it's actually its turn, so a pending ⌘V
    /// can never paste a *different* shot than the one it was started for.
    private var deliveryTask: Task<DeliveryOutcome, Never>?

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Copies the image to the clipboard and (if `autoPaste`) pulls the target
    /// app to the foreground, focuses its text input, pastes, and verifies.
    func deliver(pngData: Data, to target: DeliveryTarget, autoPaste: Bool, maxImages: Int) async -> DeliveryOutcome {
        deliveryTask?.cancel()
        let previous = deliveryTask
        let task = Task { [weak self] () -> DeliveryOutcome in
            _ = await previous?.value
            guard let self, !Task.isCancelled else { return .superseded }
            return await self.performDelivery(
                pngData: pngData,
                target: target,
                autoPaste: autoPaste,
                maxImages: maxImages
            )
        }
        deliveryTask = task
        return await task.value
    }

    private func performDelivery(pngData: Data, target: DeliveryTarget, autoPaste: Bool, maxImages: Int) async -> DeliveryOutcome {
        copyToPasteboard(pngData)
        guard autoPaste else { return .clipboardOnly(reason: "autoPaste-off") }
        guard accessibilityTrusted else {
            NSLog("ClaudeShot: no Accessibility permission; image left on clipboard for manual ⌘V")
            return .clipboardOnly(reason: "accessibility-not-granted")
        }

        guard let pid = await bringToFront(bundleID: target.bundleID) else {
            NSLog("ClaudeShot: could not find or launch \(target.bundleID); image left on clipboard")
            return .appUnavailable
        }
        if Task.isCancelled { return .superseded }
        try? await Task.sleep(nanoseconds: 150_000_000)

        let appElement = makeAppElement(pid: pid)

        // Focus the composer — and REQUIRE success before pasting. ⌘V with no
        // focused editable element is a silent no-op in Electron, so pasting
        // blind only ever produces invisible failures.
        guard let composer = await ensureComposerFocused(pid: pid, appElement: appElement) else {
            NSLog("ClaudeShot: couldn't focus a text input; leaving shot on clipboard")
            return .clipboardOnly(reason: "composer-not-focused")
        }
        if Task.isCancelled { return .superseded }

        // Pre-flight the per-message image limit before touching the keyboard.
        let baseline = composerSnapshot(near: composer)
        if baseline.images >= maxImages {
            NSLog("ClaudeShot: composer already has \(baseline.images) image(s); limit is \(maxImages)")
            return .limitReached(count: baseline.images)
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            postCommandV()
            if await waitForAttachment(near: composer, baseline: baseline, timeout: 1.5) {
                return .pasted
            }
            // No menu-paste retry here: if ⌘V landed but verification missed
            // it, a second paste would duplicate the attachment.
            NSLog("ClaudeShot: ⌘V posted but no attachment appeared")
            return .clipboardOnly(reason: "paste-not-confirmed")
        }

        // macOS refused to give the target the foreground (cooperative
        // activation). Posting ⌘V into a background Chromium process via
        // postToPid is silently dropped, so drive Electron's own
        // Edit ▸ Paste menu item instead — it works without key-window focus.
        NSLog("ClaudeShot: target not frontmost; using Edit ▸ Paste menu item")
        if pressPasteMenuItem(appElement: appElement),
           await waitForAttachment(near: composer, baseline: baseline, timeout: 1.5) {
            return .pasted
        }
        return .clipboardOnly(reason: "target-not-frontmost")
    }

    /// App AX element with a short messaging timeout: the default is ~6 s per
    /// call, so a busy Electron renderer could otherwise stall a tree walk
    /// (thousands of calls) for a very long time.
    private func makeAppElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    private func copyToPasteboard(_ pngData: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Single pasteboard item with both representations — writing NSImage
        // as a second object made some targets see two attachments.
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let image = NSImage(data: pngData), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
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
        let appElement = makeAppElement(pid: pid)
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

    /// Makes sure a text input inside the target app has keyboard focus and
    /// returns it. Chromium often ignores AX focus writes, so this escalates
    /// to a real (hit-test-verified) mouse click on the composer. Returns nil
    /// when focus could not be verified — the caller must NOT paste blind.
    private func ensureComposerFocused(pid: pid_t, appElement: AXUIElement) async -> AXUIElement? {
        guard accessibilityTrusted else { return nil }

        // Wake Electron's dormant AX tree. AXManualAccessibility is the
        // modern Electron flag; the legacy AXEnhancedUserInterface is
        // deliberately NOT set — it has documented side effects on Chromium
        // window geometry (breaks window moves/resizes).
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // Fast path — but only trust Chromium's reported focus when the app is
        // actually frontmost; backgrounded it reports stale internal focus.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let focused = focusedTextInput(appElement) {
            return focused
        }

        // Poll for the composer while Electron materializes its lazy AX tree
        // (can take >500 ms on first touch after launch).
        var composer = findComposer(appElement: appElement)
        let treeDeadline = Date().addingTimeInterval(2.0)
        while composer == nil, Date() < treeDeadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return nil }
            composer = findComposer(appElement: appElement)
        }
        guard let composer else { return nil }

        for attempt in 0..<3 {
            // 1) Ask nicely via AX, then poll — Chromium applies it async.
            AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if await waitForFocusedTextInput(appElement, timeout: 0.4) { return composer }

            // 2) Chromium refused — click the composer like a human would,
            //    but only when the target is frontmost AND the point really
            //    belongs to it, so we can never click through to another app.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
               await clickCenterVerified(of: composer, expectedPid: pid) {
                if await waitForFocusedTextInput(appElement, timeout: 0.4) { return composer }
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return nil }
            }
        }
        return nil
    }

    private func waitForFocusedTextInput(_ appElement: AXUIElement, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if focusedTextInput(appElement) != nil { return true }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return focusedTextInput(appElement) != nil
    }

    private func focusedTextInput(_ appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement
        return isTextInput(element) ? element : nil
    }

    /// Finds the chat composer. Prefers the main window (the focused window
    /// can be Settings or Quick Entry), then picks the bottom-most *wide*
    /// text input in the lower half — narrow inputs near the top are search
    /// fields, not the composer.
    private func findComposer(appElement: AXUIElement) -> AXUIElement? {
        var window: AXUIElement?
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            window = windows.first { candidate in
                var mainRef: CFTypeRef?
                return AXUIElementCopyAttributeValue(candidate, kAXMainAttribute as CFString, &mainRef) == .success
                    && (mainRef as? Bool) == true
            } ?? windows.first
        }
        if window == nil {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                window = (windowRef as! AXUIElement)
            }
        }
        guard let window else { return nil }

        var inputs: [AXUIElement] = []
        var visited = 0
        collectTextInputs(in: window, depth: 0, visited: &visited, into: &inputs)
        NSLog("ClaudeShot: found \(inputs.count) text input(s) in target window")
        guard !inputs.isEmpty else { return nil }

        if let windowFrame = frame(of: window) {
            let plausible = inputs.filter { input in
                guard let inputFrame = frame(of: input) else { return false }
                return inputFrame.width > windowFrame.width * 0.35
                    && inputFrame.midY > windowFrame.midY
            }
            if !plausible.isEmpty {
                return plausible.max { bottomEdge(of: $0) < bottomEdge(of: $1) }
            }
        }
        return inputs.max { bottomEdge(of: $0) < bottomEdge(of: $1) }
    }

    private func collectTextInputs(in element: AXUIElement, depth: Int, visited: inout Int, into inputs: inout [AXUIElement]) {
        // Bounded search: Chromium AX trees nest deeply and can be huge.
        // Claude Desktop's composer currently sits at depth ~27, so the cap
        // must stay well above that — 24 silently missed it entirely (found
        // 0 inputs → every paste fell through to clipboard-only). The visited
        // budget is the real backstop against a pathological tree.
        guard depth < 60, visited < 4000, inputs.count < 8 else { return }
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
        // Combo boxes deliberately excluded: in Claude Desktop they are model
        // and style pickers, never paste targets.
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String
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
    /// Hit-tests the point first so the click can never land in another app,
    /// and defers the cursor restore — warping immediately after the up-event
    /// can make Chromium treat the click as a cancelled drag.
    private func clickCenterVerified(of element: AXUIElement, expectedPid: pid_t) async -> Bool {
        guard let frame = frame(of: element), frame.width > 1, frame.height > 1 else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)

        var hitRef: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        guard AXUIElementCopyElementAtPosition(systemWide, Float(center.x), Float(center.y), &hitRef) == .success,
              let hit = hitRef
        else { return false }
        var hitPid: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPid) == .success, hitPid == expectedPid else {
            NSLog("ClaudeShot: composer point is covered by another app; not clicking")
            return false
        }

        let restore = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
        else { return false }
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 30_000_000)
        up.post(tap: .cghidEventTap)
        NSLog("ClaudeShot: clicked composer at (\(Int(center.x)), \(Int(center.y)))")

        if let restore {
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                CGWarpMouseCursorPosition(restore)
            }
        }
        return true
    }

    // MARK: - Attachment counting / paste verification

    private struct ComposerSnapshot {
        var images: Int
        var nodes: Int
    }

    /// Smallest useful container around the composer (the form area at the
    /// window bottom): walk up a few ancestors so attachment chips are
    /// included but the conversation history is not.
    private func composerContainer(for composer: AXUIElement) -> AXUIElement {
        var node = composer
        for _ in 0..<3 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef, CFGetTypeID(parentRef) == AXUIElementGetTypeID()
            else { break }
            let parent = parentRef as! AXUIElement
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(parent, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String
            if role == kAXWindowRole as String || role == "AXWebArea" { break }
            node = parent
        }
        return node
    }

    /// Counts image attachments (and total visited nodes as a robustness
    /// fallback) in the composer area. Used both to pre-flight the image
    /// limit and to verify a paste actually took effect.
    private func composerSnapshot(near composer: AXUIElement) -> ComposerSnapshot {
        let container = composerContainer(for: composer)
        var images = 0
        var visited = 0
        countImages(in: container, depth: 0, visited: &visited, count: &images)
        return ComposerSnapshot(images: images, nodes: visited)
    }

    private func countImages(in element: AXUIElement, depth: Int, visited: inout Int, count: inout Int) {
        guard depth < 12, visited < 600 else { return }
        visited += 1
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           (roleRef as? String) == kAXImageRole as String {
            count += 1
            return // attachment thumbnails don't nest further images
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            countImages(in: child, depth: depth + 1, visited: &visited, count: &count)
        }
    }

    /// Polls until the composer area shows a new image (or grows at all — the
    /// chip adds nodes even if its thumbnail isn't exposed as AXImage), or
    /// times out.
    private func waitForAttachment(near composer: AXUIElement, baseline: ComposerSnapshot, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let now = composerSnapshot(near: composer)
            if now.images > baseline.images || now.nodes > baseline.nodes { return true }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        let now = composerSnapshot(near: composer)
        return now.images > baseline.images || now.nodes > baseline.nodes
    }

    // MARK: - Paste

    private func postCommandV() {
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
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Presses Edit ▸ Paste via the AX menu bar. Locale-independent: matched
    /// by ⌘V command character, not the localized "Paste"/"ペースト" title.
    /// Menu items perform their action even when the app isn't frontmost,
    /// which makes this the reliable replacement for postToPid key events.
    private func pressPasteMenuItem(appElement: AXUIElement) -> Bool {
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef, CFGetTypeID(menuBarRef) == AXUIElementGetTypeID()
        else { return false }
        return pressMenuItem(withCmdChar: "V", in: menuBarRef as! AXUIElement, depth: 0)
    }

    private func pressMenuItem(withCmdChar target: String, in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 5 else { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return false }
        for child in children {
            var cmdCharRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXMenuItemCmdCharAttribute as CFString, &cmdCharRef) == .success,
               (cmdCharRef as? String)?.uppercased() == target {
                var modsRef: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXMenuItemCmdModifiersAttribute as CFString, &modsRef)
                // 0 == plain ⌘ (no shift/option/control) — plain ⌘V only.
                if (modsRef as? Int ?? 0) == 0 {
                    return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
                }
            }
            if pressMenuItem(withCmdChar: target, in: child, depth: depth + 1) { return true }
        }
        return false
    }
}
