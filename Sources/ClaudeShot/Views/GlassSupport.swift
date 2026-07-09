import SwiftUI

/// Apple Liquid Glass helpers with graceful fallback to materials on older macOS.
extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func liquidGlass<S: Shape>(tint: Color, interactive: Bool = false, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.fill(tint.opacity(0.12)))
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Wraps glass children so Liquid Glass can blend/merge them correctly
/// (`GlassEffectContainer` on macOS 26; a plain stack as fallback).
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
