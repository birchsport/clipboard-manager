import SwiftUI

/// Multiplier applied to every font in the clipboard panel so users (notably
/// those with low vision) can enlarge the whole UI. `1.0` = the original
/// hardcoded sizes. Injected once at the panel root from
/// `Preferences.fontScale`; child views read it through `.scaledFont(_:)`
/// rather than declaring `@Environment` individually.
private struct PanelFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var panelFontScale: CGFloat {
        get { self[PanelFontScaleKey.self] }
        set { self[PanelFontScaleKey.self] = newValue }
    }
}

/// Applies `.font(.system(size: size * scale, …))`, reading the scale from the
/// environment so call sites only pass the *base* size — the same number that
/// used to live in `.font(.system(size: N))`.
private struct ScaledSystemFont: ViewModifier {
    @Environment(\.panelFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// Drop-in replacement for `.font(.system(size:weight:design:))` that scales
    /// with `panelFontScale`. Used by every text element in the panel.
    func scaledFont(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
