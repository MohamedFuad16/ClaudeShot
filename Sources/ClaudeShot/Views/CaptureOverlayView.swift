import SwiftUI

/// Bottom-right corner overlay that plays the capture choreography. Rendered
/// inside a transparent, click-through floating panel that spans the screen.
struct CaptureOverlayView: View {
    @Bindable var controller: AppshotController

    var body: some View {
        ZStack {
            // Flash is keyed on flashToken (not the phase): each capture spins up
            // a fresh view that runs its full choreography, so the visible flash
            // length no longer depends on how fast the capture returns.
            if controller.flashToken > 0 {
                AppshotFlashView(duration: controller.settings.flashDuration)
                    .id(controller.flashToken)
            }

            VStack(alignment: .trailing, spacing: 10) {
                Spacer()
                HStack {
                    Spacer()
                    cluster
                }
            }
            .padding(24)
        }
        // Match Agent Swarm's composer phase easing exactly.
        .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: controller.capturePhase)
        .animation(.smooth(duration: 0.24), value: controller.previewURL != nil)
    }

    @ViewBuilder
    private var cluster: some View {
        if let message = controller.permissionMessage {
            PermissionCard(message: message) { controller.permissionMessage = nil }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let previewURL = controller.previewURL, controller.capturePhase != .flash {
            AppshotAttachmentChrome(
                fileURL: previewURL,
                metadata: controller.lastMetadata,
                phase: controller.capturePhase
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if controller.capturePhase == .flash {
            AppshotCapturePill(phase: controller.capturePhase)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct PermissionCard: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 380)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appshotBorder))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
    }
}
