import AppKit
import SwiftUI

extension Color {
    static let appshotBorder = Color.white.opacity(0.14)
}

/// Full-screen camera flash: a bright white pop that eases straight out, like
/// the macOS screenshot flash. Deliberately a **solid fill + pure opacity** so
/// Core Animation drives it on the GPU with no per-frame redraw — that's what
/// keeps it buttery. (An animated full-screen gradient re-rasterizes every
/// frame and stutters; don't reintroduce one here.) The overlay keys this view
/// on the capture's flashToken, so it always plays its full duration regardless
/// of how fast the capture itself finishes.
struct AppshotFlashView: View {
    /// Flash fade duration in seconds. Lower = faster/snappier.
    var duration: Double = 0.35
    @State private var opacity: Double = 0

    var body: some View {
        Rectangle()
            .fill(.white)
            .ignoresSafeArea()
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                opacity = 0.9
                withAnimation(.easeOut(duration: duration)) { opacity = 0 }
            }
    }
}

/// Small "Capturing appshot" pill shown during the flash phase — exact port of
/// Agent Swarm's composer pill.
struct AppshotCapturePill: View {
    var phase: AppshotCapturePhase

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(Localizer.shared.t(phase.localizationKey))
                .font(.caption.weight(.semibold))
            Text(Localizer.shared.t("pill.frontmost"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlass(in: Capsule())
        .overlay(Capsule().stroke(Color.appshotBorder))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}

/// Rotating progress ring that resolves to a green checkmark when ready.
/// Exact port of Agent Swarm's AppshotPhaseBadge.
struct AppshotPhaseBadge: View {
    var phase: AppshotCapturePhase
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(phase == .ready ? Color.green : Color.black.opacity(0.45))
            if phase == .ready {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 2)
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(phase == .settling ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: phase == .settling)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.42)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

/// The 178×122 appshot card wrapped in Agent Swarm's AttachmentPreview chrome
/// (thin material, radius-18, accent-glow border, landing press-scale). This is
/// the exact "landed appshot" look from the Agent Swarm composer.
struct AppshotAttachmentChrome: View {
    var fileURL: URL
    var metadata: AppshotSourceMetadata?
    var phase: AppshotCapturePhase

    var body: some View {
        AppshotAttachmentCard(fileURL: fileURL, metadata: metadata, phase: phase)
            .padding(5)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(phase.isActive ? 0.58 : 0.34),
                        lineWidth: phase.isActive ? 1.5 : 1
                    )
            )
            .scaleEffect(phase == .landing ? 0.985 : 1)
            .animation(.snappy(duration: 0.22, extraBounce: 0.018), value: phase)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }
}

/// Exact port of Agent Swarm's AppshotAttachmentCard.
struct AppshotAttachmentCard: View {
    var fileURL: URL
    var metadata: AppshotSourceMetadata?
    var phase: AppshotCapturePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            AppshotThumbnail(fileURL: fileURL)
                .frame(width: 178, height: 122)
                .overlay {
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.08),
                            .black.opacity(0.48)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 6) {
                AppIconView(metadata: metadata, size: 31)
                    .shadow(color: .black.opacity(0.24), radius: 8, y: 4)

                Text(appTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)

                if subtitle != Localizer.shared.t("card.captured") {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .shadow(color: .black.opacity(0.34), radius: 4, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
            .frame(width: 178)

            if phase.isActive {
                AppshotPhaseBadge(phase: phase, size: 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .frame(width: 178, height: 122)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var appTitle: String {
        let title = metadata?.appName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Appshot" : title
    }

    private var subtitle: String {
        let captured = Localizer.shared.t("card.captured")
        if phase == .ready { return Localizer.shared.t("card.pasted") }
        guard let metadata else { return captured }
        let title = metadata.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = metadata.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return captured }
        return title.caseInsensitiveCompare(appName) == .orderedSame ? captured : title
    }
}

struct AppshotThumbnail: View {
    var fileURL: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: fileURL) {
            image = await Self.loadThumbnail(from: fileURL)
        }
    }

    private static func loadThumbnail(from url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
    }
}

/// Exact port of Agent Swarm's AppIconView.
struct AppIconView: View {
    var metadata: AppshotSourceMetadata?
    var size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).stroke(.white.opacity(0.16)))
    }

    private var icon: NSImage? {
        if let processIdentifier = metadata?.processIdentifier,
           let appIcon = NSRunningApplication(processIdentifier: processIdentifier)?.icon {
            return appIcon
        }
        if let bundleIdentifier = metadata?.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }
}
