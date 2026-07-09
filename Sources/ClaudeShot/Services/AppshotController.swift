import AppKit
import CoreGraphics
import Observation
import ScreenCaptureKit
import UniformTypeIdentifiers

private enum AppshotCaptureScope {
    case frontmostWindow
    case activeDisplay
}

private struct AppshotCaptureTarget {
    var windowID: CGWindowID?
    var displayID: CGDirectDisplayID?
    var metadata: AppshotSourceMetadata
}

/// Drives the appshot capture pipeline and the flash → landing → settling →
/// ready animation phases. Ported from Agent Swarm's SwarmStore, trimmed to
/// just the screenshot concern and wired to ClaudeBridge instead of a chat.
@MainActor
@Observable
final class AppshotController {
    var capturePhase: AppshotCapturePhase = .idle
    var previewURL: URL?
    var lastMetadata: AppshotSourceMetadata?

    /// Bumped every time a flash should play. The overlay keys its flash view on
    /// this, so the flash always runs its full choreographed duration regardless
    /// of how quickly ScreenCaptureKit returns (which is what used to make the
    /// visible flash length feel random).
    var flashToken = 0

    @ObservationIgnored private var isShowingAccessibilityAlert = false
    var permissionMessage: String? {
        didSet {
            guard let message = permissionMessage else { return }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                if self?.permissionMessage == message { self?.permissionMessage = nil }
            }
        }
    }

    var hotKey = AppshotHotKey.load() {
        didSet {
            guard hotKey != oldValue else { return }
            hotKey.save()
            hotKeyChanged?(hotKey)
        }
    }

    var hotKeyChanged: ((AppshotHotKey) -> Void)?

    let injector: ClaudeInjector
    let settings: AppSettings
    let localizer: Localizer
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    init(injector: ClaudeInjector, settings: AppSettings, localizer: Localizer) {
        self.injector = injector
        self.settings = settings
        self.localizer = localizer
    }

    // MARK: - Entry points

    /// Plays just the flash pulse (no capture) so the flash-speed slider can be
    /// previewed from Settings.
    func previewFlash() {
        guard !capturePhase.isActive else { return }
        flashToken += 1
        capturePhase = .flash
        Task { [weak self] in
            guard let self else { return }
            let hold = UInt64((self.settings.flashDuration + 0.15) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: hold)
            if self.capturePhase == .flash { self.capturePhase = .idle }
        }
    }

    func takeAppshot() {
        NSLog("ClaudeShot appshot requested")
        guard !capturePhase.isActive else { return }

        guard CGPreflightScreenCaptureAccess() else {
            previewURL = nil
            capturePhase = .idle
            permissionMessage = localizer.t("perm.screenDenied")
            _ = CGRequestScreenCaptureAccess()
            return
        }

        permissionMessage = nil
        resetTask?.cancel()
        previewURL = nil
        flashToken += 1
        capturePhase = .flash

        let target = appshotCaptureTarget(for: .frontmostWindow)
        let windowID = target.windowID
        let displayID = target.displayID
        let metadata = target.metadata
        let scaleFactor = captureScaleFactor(for: target)

        Task { [weak self] in
            do {
                let directory = try Self.captureDirectory()
                let destination = directory.appendingPathComponent("appshot-\(Int(Date().timeIntervalSince1970)).png")
                let (url, pngData) = try await Self.captureAppshot(
                    to: destination,
                    windowID: windowID,
                    displayID: displayID,
                    scaleFactor: scaleFactor
                )
                guard let self else { return }

                // Always copy to clipboard and auto-paste. (Image-count limit
                // handling was removed for now — to be reintroduced later.)
                self.injector.deliver(pngData: pngData, to: self.settings.deliveryTarget, autoPaste: true)

                self.previewURL = url
                self.lastMetadata = metadata
                self.capturePhase = .landing
                self.settings.captureSound.play() // user-selectable capture sound

                self.scheduleSettling(for: url)

                // Without Accessibility we can't press ⌘V — the shot only reached
                // the clipboard. Tell the user instead of failing silently.
                if !self.injector.accessibilityTrusted {
                    self.presentAccessibilityAlert()
                }
            } catch {
                guard let self else { return }
                NSLog("ClaudeShot capture failed: \(error.localizedDescription)")
                self.capturePhase = .idle
                self.previewURL = nil
                self.permissionMessage = String(format: self.localizer.t("perm.captureFailed"), error.localizedDescription)
            }
        }
    }

    // MARK: - Accessibility prompt

    /// Shows a popup when a capture was delivered but Accessibility isn't granted
    /// (so ⌘V couldn't be pressed). Guarded so rapid captures don't stack alerts.
    private func presentAccessibilityAlert() {
        guard !isShowingAccessibilityAlert else { return }
        isShowingAccessibilityAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.t("alert.accessibilityTitle")
        alert.informativeText = localizer.t("alert.accessibilityBody")
        alert.addButton(withTitle: localizer.t("alert.openSettings"))
        alert.addButton(withTitle: localizer.t("alert.later"))

        let response = alert.runModal()
        isShowingAccessibilityAlert = false

        if response == .alertFirstButtonReturn {
            // Trigger the system prompt, then open the pane so they can toggle it.
            injector.requestAccessibilityIfNeeded()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Phase machine

    private func scheduleSettling(for url: URL) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled, self?.previewURL == url else { return }
            self?.capturePhase = .settling
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled, self?.previewURL == url else { return }
            self?.capturePhase = .ready
            try? await Task.sleep(nanoseconds: 760_000_000)
            guard !Task.isCancelled, self?.previewURL == url else { return }
            self?.capturePhase = .idle
            self?.previewURL = nil
        }
    }

    // MARK: - Capture

    private static func captureDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeShot", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated private static func captureAppshot(
        to destination: URL,
        windowID: CGWindowID?,
        displayID: CGDirectDisplayID?,
        scaleFactor: CGFloat
    ) async throws -> (URL, Data) {
        let image = try await captureScreenImage(windowID: windowID, displayID: displayID, scaleFactor: scaleFactor)
        let data = try writePNG(image, to: destination)
        return (destination, data)
    }

    nonisolated private static func captureScreenImage(
        windowID: CGWindowID?,
        displayID: CGDirectDisplayID?,
        scaleFactor: CGFloat
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.showsCursor = true
        // SCWindow/SCDisplay frames are in points; render at native pixel
        // resolution (Retina = 2×) so shots match ⌘⇧4 quality.
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        let scale = max(scaleFactor, 1)

        if let windowID, let window = content.windows.first(where: { $0.windowID == windowID }) {
            configuration.width = max(Int(window.frame.width * scale), 1)
            configuration.height = max(Int(window.frame.height * scale), 1)
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }

        let matchedDisplay = displayID.flatMap { targetID in
            content.displays.first { $0.displayID == targetID }
        }
        guard let display = matchedDisplay ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        configuration.width = max(Int(CGFloat(display.width) * scale), 1)
        configuration.height = max(Int(CGFloat(display.height) * scale), 1)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    nonisolated private static func writePNG(_ image: CGImage, to destination: URL) throws -> Data {
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try Data(contentsOf: destination)
    }

    // MARK: - Targeting

    /// Native pixel density to render the capture at. For a display target,
    /// that display's factor; for a window, the densest attached screen
    /// (windows can straddle displays, so err on the sharp side).
    private func captureScaleFactor(for target: AppshotCaptureTarget) -> CGFloat {
        if let displayID = target.displayID {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            for screen in NSScreen.screens {
                if let number = screen.deviceDescription[key] as? NSNumber,
                   number.uint32Value == displayID {
                    return screen.backingScaleFactor
                }
            }
        }
        return NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    private func appshotCaptureTarget(for scope: AppshotCaptureScope) -> AppshotCaptureTarget {
        switch scope {
        case .frontmostWindow:
            return frontmostCaptureTarget() ?? activeDisplayCaptureTarget()
        case .activeDisplay:
            return activeDisplayCaptureTarget()
        }
    }

    private func frontmostCaptureTarget() -> AppshotCaptureTarget? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var candidates: [AppshotCaptureTarget] = []
        let currentProcessID = NSRunningApplication.current.processIdentifier

        for window in windows {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 160,
                  (bounds["Height"] ?? 0) > 120,
                  let number = window[kCGWindowNumber as String] as? UInt32
            else { continue }

            let ownerName = (window[kCGWindowOwnerName as String] as? String) ?? "Appshot"
            let windowTitle = (window[kCGWindowName as String] as? String) ?? ""
            let processID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let runningApp = processID.flatMap { NSRunningApplication(processIdentifier: $0) }
            let appName = runningApp?.localizedName ?? ownerName
            let metadata = AppshotSourceMetadata(
                appName: appName,
                windowTitle: windowTitle,
                bundleIdentifier: runningApp?.bundleIdentifier,
                processIdentifier: processID
            )
            candidates.append(AppshotCaptureTarget(windowID: CGWindowID(number), displayID: nil, metadata: metadata))
        }
        return candidates.first { $0.metadata.processIdentifier != currentProcessID } ?? candidates.first
    }

    private func activeDisplayCaptureTarget() -> AppshotCaptureTarget {
        let displayID = activeDisplayIDUnderPointer()
        let screenName = screenName(for: displayID) ?? "Active Display"
        let metadata = AppshotSourceMetadata(
            appName: screenName,
            windowTitle: "Full screen appshot",
            bundleIdentifier: nil,
            processIdentifier: nil
        )
        return AppshotCaptureTarget(windowID: nil, displayID: displayID, metadata: metadata)
    }

    private func screenName(for displayID: CGDirectDisplayID?) -> String? {
        guard let displayID else { return NSScreen.main?.localizedName }
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber,
               number.uint32Value == displayID {
                return screen.localizedName
            }
        }
        return NSScreen.main?.localizedName
    }

    private func activeDisplayIDUnderPointer() -> CGDirectDisplayID? {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber {
                return CGDirectDisplayID(number.uint32Value)
            }
        }
        return nil
    }
}
