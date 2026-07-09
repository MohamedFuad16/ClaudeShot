import ApplicationServices
import CoreGraphics
import Observation

/// Live-refreshing view of the two permissions ClaudeShot needs. TCC changes
/// don't push notifications, so the UI polls `refresh()` while Settings is open.
@MainActor
@Observable
final class PermissionsModel {
    var screenRecording: Bool = CGPreflightScreenCaptureAccess()
    var accessibility: Bool = AXIsProcessTrusted()

    func refresh() {
        let sr = CGPreflightScreenCaptureAccess()
        let ax = AXIsProcessTrusted()
        if sr != screenRecording { screenRecording = sr }
        if ax != accessibility { accessibility = ax }
    }
}
