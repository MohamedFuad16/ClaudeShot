import Foundation

// Ported 1:1 from Agent Swarm's Appshot toolkit.

struct AppshotSourceMetadata: Hashable {
    var appName: String
    var windowTitle: String
    var bundleIdentifier: String?
    var processIdentifier: pid_t?

    var displayTitle: String {
        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? appName : trimmedTitle
    }
}

enum AppshotCapturePhase: String, Hashable {
    case idle
    case flash
    case landing
    case settling
    case ready

    var isActive: Bool {
        self != .idle
    }

    var statusTitle: String {
        switch self {
        case .idle: "Ready"
        case .flash: "Capturing appshot"
        case .landing: "Landing appshot"
        case .settling: "Processing appshot"
        case .ready: "Sent to Claude"
        }
    }

    var localizationKey: String {
        switch self {
        case .idle, .flash: "phase.capturing"
        case .landing: "phase.landing"
        case .settling: "phase.processing"
        case .ready: "phase.ready"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "camera.viewfinder"
        case .flash: "viewfinder"
        case .landing: "rectangle.compress.vertical"
        case .settling: "arrow.down.to.line.compact"
        case .ready: "checkmark"
        }
    }
}

struct AppshotHotKey: Identifiable, Hashable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyName: String
    var displayName: String

    var id: String { "\(keyCode)-\(modifiers)" }

    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    static let defaultValue = AppshotHotKey(
        keyCode: 19,
        modifiers: command | shift,
        keyName: "2",
        displayName: "⇧⌘2"
    )

    static let presets: [AppshotHotKey] = [
        .defaultValue,
        AppshotHotKey(keyCode: 0, modifiers: command | shift, keyName: "A", displayName: "⇧⌘A"),
        AppshotHotKey(keyCode: 0, modifiers: command | option, keyName: "A", displayName: "⌥⌘A"),
        AppshotHotKey(keyCode: 8, modifiers: control | option, keyName: "C", displayName: "⌃⌥C"),
        AppshotHotKey(keyCode: 9, modifiers: command | shift, keyName: "V", displayName: "⇧⌘V")
    ]
}

extension AppshotHotKey {
    private static let storageKey = "ClaudeShot.appshotHotKey"

    static func load() -> AppshotHotKey {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let hotKey = try? JSONDecoder().decode(AppshotHotKey.self, from: data)
        else { return .defaultValue }
        return hotKey
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
