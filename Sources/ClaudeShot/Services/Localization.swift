import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        }
    }
}

/// Lightweight in-app localizer (EN/JA) that switches live. SwiftUI views that
/// call `loc.t(...)` re-render when `language` changes because it's @Observable.
@MainActor
@Observable
final class Localizer {
    static let shared = Localizer()

    private static let storageKey = "ClaudeShot.language"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else if Locale.preferredLanguages.first?.hasPrefix("ja") == true {
            language = .japanese
        } else {
            language = .english
        }
    }

    func t(_ key: String) -> String {
        switch language {
        case .english: Self.en[key] ?? key
        case .japanese: Self.ja[key] ?? Self.en[key] ?? key
        }
    }

    /// Format helper for strings with a single %d.
    func t(_ key: String, _ count: Int) -> String {
        String(format: t(key), count)
    }

    static let en: [String: String] = [
        "menu.takeAppshot": "Take Appshot",
        "menu.preferences": "Preferences…",
        "menu.grantAccessibility": "Grant Accessibility Permission…",
        "menu.resetCount": "Reset Image Count",
        "menu.quit": "Quit ClaudeShot",

        "phase.capturing": "Capturing appshot",
        "phase.landing": "Landing appshot",
        "phase.processing": "Processing appshot",
        "phase.ready": "Sent to Claude",
        "pill.frontmost": "Frontmost window",
        "card.pasted": "Pasted into Claude",
        "card.captured": "Captured window",

        "settings.subtitle": "Capture a window → paste into Claude",
        "settings.hotkey": "Appshot Hotkey",
        "settings.globalShortcut": "Global shortcut",
        "settings.hotkeyCaption": "Press this shortcut anywhere to capture the frontmost window and paste it into Claude. Pick a preset, or record any combination of your own (Esc cancels recording).",
        "settings.recordShortcut": "Record Shortcut…",
        "settings.recordingHint": "Press keys…",
        "settings.delivery": "Delivery",
        "settings.deliverTo": "Deliver to",
        "settings.deliveryCaption": "Where captured shots are pasted. Terminal targets paste into Claude Code running in that app.",
        "settings.language": "Language",
        "settings.languageLabel": "App language",
        "settings.languageCaption": "Switch the ClaudeShot interface between English and Japanese.",
        "settings.screenRecording": "Screen Recording",
        "settings.capturePermission": "Capture permission",
        "settings.screenCaption": "Required to capture windows. If captures fail, enable ClaudeShot here and restart the app.",
        "settings.accessibility": "Accessibility",
        "settings.pastePermission": "Paste permission",
        "settings.accessibilityCaption": "Required so ClaudeShot can press ⌘V into Claude for you. Without it, the shot is still copied to the clipboard — just paste it yourself.",
        "settings.granted": "Granted",
        "settings.openSystemSettings": "Open System Settings",
        "settings.grant": "Grant…",
        "settings.sound": "Capture Sound",
        "settings.soundLabel": "Sound",
        "settings.soundNone": "None",
        "settings.soundCaption": "Sound played when an appshot is captured. Pick one to preview it.",
        "settings.flash": "Flash Animation",
        "settings.flashSpeed": "Flash speed",
        "settings.faster": "Faster",
        "settings.smoother": "Smoother",
        "settings.flashCaption": "How quickly the capture flash fades. Left is snappy, right is smooth.",
        "settings.test": "Test",

        "target.claudeDesktop": "Claude (Desktop app)",
        "target.terminal": "Terminal — Claude CLI",
        "target.iterm": "iTerm2 — Claude CLI",
        "target.ghostty": "Ghostty — Claude CLI",
        "settings.comingSoon": "Coming soon",

        "warn.limit": "Claude accepts up to %d images per message. Send or clear the message, then reset the image count.",
        "toast.copied": "Image copied — paste into Claude with ⌘V.",
        "perm.screenDenied": "ClaudeShot needs Screen Recording permission. Enable ClaudeShot in System Settings › Privacy & Security › Screen Recording, then restart the app.",
        "perm.captureFailed": "Couldn't capture the appshot: %@",
    ]

    static let ja: [String: String] = [
        "menu.takeAppshot": "アプリショットを撮る",
        "menu.preferences": "環境設定…",
        "menu.grantAccessibility": "アクセシビリティ許可を付与…",
        "menu.resetCount": "画像カウントをリセット",
        "menu.quit": "ClaudeShot を終了",

        "phase.capturing": "アプリショットを撮影中",
        "phase.landing": "配置中",
        "phase.processing": "処理中",
        "phase.ready": "Claude に送信しました",
        "pill.frontmost": "最前面のウィンドウ",
        "card.pasted": "Claude に貼り付けました",
        "card.captured": "キャプチャしたウィンドウ",

        "settings.subtitle": "ウィンドウをキャプチャ → Claude に貼り付け",
        "settings.hotkey": "アプリショットのショートカット",
        "settings.globalShortcut": "グローバルショートカット",
        "settings.hotkeyCaption": "このショートカットをどこでも押すと、最前面のウィンドウをキャプチャして Claude に貼り付けます。プリセットから選ぶか、好きなキーの組み合わせを記録できます（Esc でキャンセル）。",
        "settings.recordShortcut": "ショートカットを記録…",
        "settings.recordingHint": "キーを押してください…",
        "settings.delivery": "送信先",
        "settings.deliverTo": "貼り付け先",
        "settings.deliveryCaption": "キャプチャした画像の貼り付け先です。ターミナルを選ぶと、そのアプリで動作している Claude Code に貼り付けます。",
        "settings.language": "言語",
        "settings.languageLabel": "アプリの言語",
        "settings.languageCaption": "ClaudeShot の表示を英語と日本語で切り替えます。",
        "settings.screenRecording": "画面収録",
        "settings.capturePermission": "キャプチャ許可",
        "settings.screenCaption": "ウィンドウのキャプチャに必要です。失敗する場合はここで ClaudeShot を有効にし、アプリを再起動してください。",
        "settings.accessibility": "アクセシビリティ",
        "settings.pastePermission": "貼り付け許可",
        "settings.accessibilityCaption": "ClaudeShot が代わりに ⌘V を押すために必要です。許可がなくても画像はクリップボードにコピーされるので、手動で貼り付けられます。",
        "settings.granted": "許可済み",
        "settings.openSystemSettings": "システム設定を開く",
        "settings.grant": "許可…",
        "settings.sound": "キャプチャ音",
        "settings.soundLabel": "サウンド",
        "settings.soundNone": "なし",
        "settings.soundCaption": "アプリショット撮影時に再生される音です。選ぶとプレビューできます。",
        "settings.flash": "フラッシュアニメーション",
        "settings.flashSpeed": "フラッシュの速さ",
        "settings.faster": "速い",
        "settings.smoother": "滑らか",
        "settings.flashCaption": "キャプチャ時のフラッシュが消える速さです。左は素早く、右は滑らかになります。",
        "settings.test": "テスト",

        "target.claudeDesktop": "Claude（デスクトップアプリ）",
        "target.terminal": "ターミナル — Claude CLI",
        "target.iterm": "iTerm2 — Claude CLI",
        "target.ghostty": "Ghostty — Claude CLI",
        "settings.comingSoon": "近日公開",

        "warn.limit": "Claude は 1 メッセージにつき最大 %d 枚の画像を受け付けます。メッセージを送信またはクリアしてから、画像カウントをリセットしてください。",
        "toast.copied": "画像をコピーしました — ⌘V で Claude に貼り付けてください。",
        "perm.screenDenied": "ClaudeShot には画面収録の許可が必要です。システム設定 › プライバシーとセキュリティ › 画面収録 で ClaudeShot を有効にし、アプリを再起動してください。",
        "perm.captureFailed": "アプリショットをキャプチャできませんでした: %@",
    ]
}
