import AppKit
import Foundation
import Observation

/// Where a captured appshot should be delivered.
enum DeliveryTarget: String, CaseIterable, Identifiable {
    case claudeDesktop
    case terminal
    case iterm
    case ghostty

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .claudeDesktop: "com.anthropic.claudefordesktop"
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    /// Terminal targets run Claude Code, which reads the clipboard image on paste.
    var isTerminal: Bool { self != .claudeDesktop }

    /// Only Claude Desktop ships in v1; terminal targets are "coming soon".
    var isAvailable: Bool { self == .claudeDesktop }

    var localizationKey: String {
        switch self {
        case .claudeDesktop: "target.claudeDesktop"
        case .terminal: "target.terminal"
        case .iterm: "target.iterm"
        case .ghostty: "target.ghostty"
        }
    }
}

/// System sound played when an appshot is captured. `nil` name = silent.
enum CaptureSound: String, CaseIterable, Identifiable {
    case none, pop, glass, tink, ping, bottle, submarine, funk, hero, frog

    var id: String { rawValue }

    var systemName: String? {
        switch self {
        case .none: nil
        case .pop: "Pop"
        case .glass: "Glass"
        case .tink: "Tink"
        case .ping: "Ping"
        case .bottle: "Bottle"
        case .submarine: "Submarine"
        case .funk: "Funk"
        case .hero: "Hero"
        case .frog: "Frog"
        }
    }

    /// Menu label ("None" is localized by the caller).
    var menuTitle: String { systemName ?? "—" }

    func play() {
        guard let name = systemName else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private static let targetKey = "ClaudeShot.deliveryTarget"
    private static let soundKey = "ClaudeShot.captureSound"
    private static let flashKey = "ClaudeShot.flashDuration"
    private static let defaultsVersionKey = "ClaudeShot.defaultsVersion"

    /// Bump when the built-in defaults change and existing installs should be
    /// reset to them. v5 = back to the fast 0.35s easeOut flash (the preferred
    /// live feel; use the slider toward "Smoother" when recording a demo).
    private static let currentDefaultsVersion = 5

    /// Max images Claude accepts per message (reserved for future limit UI).
    let maxImages = 5

    static let minFlashDuration = 0.12
    static let maxFlashDuration = 0.65
    static let defaultFlashDuration = 0.35

    var deliveryTarget: DeliveryTarget {
        didSet {
            // v1 only ships Claude Desktop; never persist a "coming soon" target.
            guard deliveryTarget.isAvailable else {
                deliveryTarget = .claudeDesktop
                return
            }
            UserDefaults.standard.set(deliveryTarget.rawValue, forKey: Self.targetKey)
        }
    }

    var captureSound: CaptureSound {
        didSet { UserDefaults.standard.set(captureSound.rawValue, forKey: Self.soundKey) }
    }

    /// Flash fade duration in seconds. Lower = faster/snappier, higher = smoother.
    var flashDuration: Double {
        didSet {
            let clamped = min(max(flashDuration, Self.minFlashDuration), Self.maxFlashDuration)
            if clamped != flashDuration { flashDuration = clamped; return }
            UserDefaults.standard.set(flashDuration, forKey: Self.flashKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.targetKey),
           let stored = DeliveryTarget(rawValue: raw), stored.isAvailable {
            deliveryTarget = stored
        } else {
            deliveryTarget = .claudeDesktop
        }

        if let raw = UserDefaults.standard.string(forKey: Self.soundKey),
           let stored = CaptureSound(rawValue: raw) {
            captureSound = stored
        } else {
            captureSound = .pop
        }

        // Reset the flash to the new default for installs from before the
        // smoother-animation update (or on a fresh install).
        let defaults = UserDefaults.standard
        let storedVersion = defaults.integer(forKey: Self.defaultsVersionKey)
        let storedFlash = defaults.object(forKey: Self.flashKey) as? Double
        if storedVersion < Self.currentDefaultsVersion || storedFlash == nil {
            flashDuration = Self.defaultFlashDuration
            defaults.set(Self.defaultFlashDuration, forKey: Self.flashKey)
            defaults.set(Self.currentDefaultsVersion, forKey: Self.defaultsVersionKey)
        } else {
            flashDuration = min(max(storedFlash!, Self.minFlashDuration), Self.maxFlashDuration)
        }
    }
}
