import Combine
import SwiftUI

struct PreferencesView: View {
    @Bindable var controller: AppshotController
    @Bindable var localizer: Localizer
    @Bindable var settings: AppSettings
    @State private var permissions = PermissionsModel()

    // Poll TCC while the window is open so grants reflect without a restart.
    private let pollTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            GlassContainer(spacing: 18) {
              VStack(alignment: .leading, spacing: 18) {
                header

                GlassCard(title: localizer.t("settings.language"), systemImage: "globe") {
                    Row(label: localizer.t("settings.languageLabel")) {
                        Picker("", selection: $localizer.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                    }
                    caption(localizer.t("settings.languageCaption"))
                }

                GlassCard(title: localizer.t("settings.hotkey"), systemImage: "command") {
                    Row(label: localizer.t("settings.globalShortcut")) {
                        Picker("", selection: hotKeyBinding) {
                            ForEach(AppshotHotKey.presets) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    caption(localizer.t("settings.hotkeyCaption"))
                }

                GlassCard(title: localizer.t("settings.delivery"), systemImage: "paperplane") {
                    VStack(spacing: 6) {
                        ForEach(DeliveryTarget.allCases) { target in
                            DeliveryOptionRow(
                                title: localizer.t(target.localizationKey),
                                comingSoonText: localizer.t("settings.comingSoon"),
                                isAvailable: target.isAvailable,
                                isSelected: settings.deliveryTarget == target
                            ) {
                                if target.isAvailable { settings.deliveryTarget = target }
                            }
                        }
                    }
                    caption(localizer.t("settings.deliveryCaption"))
                }

                GlassCard(title: localizer.t("settings.sound"), systemImage: "speaker.wave.2.fill") {
                    Row(label: localizer.t("settings.soundLabel")) {
                        Picker("", selection: soundBinding) {
                            ForEach(CaptureSound.allCases) { sound in
                                Text(sound == .none ? localizer.t("settings.soundNone") : sound.menuTitle)
                                    .tag(sound)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    caption(localizer.t("settings.soundCaption"))
                }

                GlassCard(title: localizer.t("settings.flash"), systemImage: "bolt.fill") {
                    Row(label: localizer.t("settings.flashSpeed")) {
                        Button(localizer.t("settings.test")) {
                            ClaudeShotRuntime.previewFlash()
                        }
                        .glassButton()
                    }
                    HStack(spacing: 10) {
                        Text(localizer.t("settings.faster"))
                            .font(.caption).foregroundStyle(.secondary)
                        Slider(
                            value: $settings.flashDuration,
                            in: AppSettings.minFlashDuration...AppSettings.maxFlashDuration
                        )
                        Text(localizer.t("settings.smoother"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    caption(localizer.t("settings.flashCaption"))
                }

                GlassCard(title: localizer.t("settings.screenRecording"), systemImage: "rectangle.dashed.badge.record") {
                    PermissionRow(
                        label: localizer.t("settings.capturePermission"),
                        granted: permissions.screenRecording,
                        grantedText: localizer.t("settings.granted"),
                        actionTitle: localizer.t("settings.openSystemSettings")
                    ) {
                        openPrivacy("Privacy_ScreenCapture")
                    }
                    caption(localizer.t("settings.screenCaption"))
                }

                GlassCard(title: localizer.t("settings.accessibility"), systemImage: "hand.point.up.braille") {
                    PermissionRow(
                        label: localizer.t("settings.pastePermission"),
                        granted: permissions.accessibility,
                        grantedText: localizer.t("settings.granted"),
                        actionTitle: localizer.t("settings.grant")
                    ) {
                        if !controller.injector.requestAccessibilityIfNeeded() {
                            openPrivacy("Privacy_Accessibility")
                        }
                    }
                    caption(localizer.t("settings.accessibilityCaption"))
                }
              }
              .padding(22)
            }
        }
        .background(backdrop)
        .onAppear { permissions.refresh() }
        .onReceive(pollTimer) { _ in permissions.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("ClaudeShot")
                    .font(.title2.weight(.semibold))
                Text(localizer.t("settings.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.16), Color.clear, Color.accentColor.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hotKeyBinding: Binding<AppshotHotKey> {
        Binding(
            get: { closestPreset(for: controller.hotKey) },
            set: { controller.hotKey = $0 }
        )
    }

    private var soundBinding: Binding<CaptureSound> {
        Binding(
            get: { settings.captureSound },
            set: { newValue in
                settings.captureSound = newValue
                newValue.play() // preview the chosen sound
            }
        )
    }

    private func closestPreset(for hotKey: AppshotHotKey) -> AppshotHotKey {
        AppshotHotKey.presets.first { $0 == hotKey } ?? AppshotHotKey.presets[0]
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Building blocks

private struct GlassCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // macOS 27 "Golden Gate" direction: bright specular top highlight,
        // darkened bottom edge for more depth/separation.
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.38),
                            .white.opacity(0.06),
                            .black.opacity(0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

private struct Row<Trailing: View>: View {
    var label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            trailing()
        }
    }
}

private struct PermissionRow: View {
    var label: String
    var granted: Bool
    var grantedText: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
            Spacer()
            if granted {
                GrantedChip(text: grantedText)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                Button(actionTitle, action: action)
                    .glassButton()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.28), value: granted)
    }
}

private struct DeliveryOptionRow: View {
    var title: String
    var comingSoonText: String
    var isAvailable: Bool
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .font(.body)
                Text(title)
                    .foregroundStyle(isAvailable ? .primary : .secondary)
                Spacer()
                if !isAvailable {
                    ComingSoonBadge(text: comingSoonText)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.6)
    }
}

private struct ComingSoonBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.secondary.opacity(0.14)))
            .overlay(Capsule().stroke(.secondary.opacity(0.22), lineWidth: 1))
    }
}

/// Clean status chip that replaces the old floating dot.
private struct GrantedChip: View {
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption.weight(.bold))
            Text(text)
                .font(.callout.weight(.semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.green.opacity(0.14))
        )
        .overlay(
            Capsule().stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
    }
}
