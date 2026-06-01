import SwiftUI

/// Cross-SDK canonical theme. Same 32-token surface as the React
/// Native, Flutter, and Android widgets — partners can take a theme
/// defined for one SDK and feed it into the others via field-by-field
/// translation.
///
/// Partners pass an `AddressIQThemeOverrides` (any subset of tokens)
/// via `AddressIQVerifyView(theme:)`; `mergeTheme(_:)` fills missing
/// fields from `AddressIQTheme.default` and auto-derives related shades
/// from any provided `primary` so a single brand color produces a
/// coherent palette.
///
/// Authoritative shape: `docs/sdk-contract.md` §1.5.
public struct AddressIQTheme {
    // Brand
    public var primary: Color
    public var primaryDark: Color
    public var primaryLight: Color
    public var secondary: Color
    public var secondaryDark: Color
    public var secondaryLight: Color
    public var accent: Color

    // Backgrounds
    public var background: Color
    public var surface: Color
    public var surfaceSecondary: Color
    public var modalOverlay: Color

    // Text
    public var text: Color
    public var textSecondary: Color
    public var textInverse: Color
    public var textLink: Color

    // Borders
    public var border: Color
    public var borderFocused: Color
    public var divider: Color

    // Status
    public var error: Color
    public var errorLight: Color
    public var success: Color
    public var successLight: Color
    public var warning: Color
    public var warningLight: Color
    public var info: Color
    public var infoLight: Color

    // Buttons
    public var buttonText: Color
    public var buttonSecondaryText: Color
    public var buttonDisabledBg: Color

    // Input
    public var inputBg: Color
    public var inputBorder: Color
    public var inputText: Color
    public var inputPlaceholder: Color

    // Card
    public var cardBg: Color
    public var cardBorder: Color

    // Typography
    public var fontFamily: String?    // System font when nil
    public var fontFamilyMono: String?

    // Radius
    public var borderRadius: CGFloat
    public var borderRadiusLg: CGFloat
    public var borderRadiusSm: CGFloat

    /// Default palette — partners typically override `primary` only.
    public static let `default` = AddressIQTheme(
        primary: Color(red: 0.31, green: 0.27, blue: 0.90),
        primaryDark: Color(red: 0.26, green: 0.22, blue: 0.79),
        primaryLight: Color(red: 0.93, green: 0.95, blue: 1.00),
        secondary: Color(red: 0.42, green: 0.45, blue: 0.50),
        secondaryDark: Color(red: 0.29, green: 0.33, blue: 0.39),
        secondaryLight: Color(red: 0.95, green: 0.96, blue: 0.96),
        accent: Color(red: 0.55, green: 0.36, blue: 0.96),

        background: Color(red: 0.97, green: 0.98, blue: 0.98),
        surface: .white,
        surfaceSecondary: Color(red: 0.95, green: 0.96, blue: 0.96),
        modalOverlay: Color.black.opacity(0.5),

        text: Color(red: 0.12, green: 0.16, blue: 0.22),
        textSecondary: Color(red: 0.42, green: 0.45, blue: 0.50),
        textInverse: .white,
        textLink: Color(red: 0.31, green: 0.27, blue: 0.90),

        border: Color(red: 0.90, green: 0.91, blue: 0.92),
        borderFocused: Color(red: 0.31, green: 0.27, blue: 0.90),
        divider: Color(red: 0.95, green: 0.96, blue: 0.96),

        error: Color(red: 0.86, green: 0.15, blue: 0.15),
        errorLight: Color(red: 1.00, green: 0.95, blue: 0.95),
        success: Color(red: 0.09, green: 0.64, blue: 0.29),
        successLight: Color(red: 0.94, green: 0.99, blue: 0.96),
        warning: Color(red: 0.96, green: 0.62, blue: 0.04),
        warningLight: Color(red: 1.00, green: 0.98, blue: 0.92),
        info: Color(red: 0.23, green: 0.51, blue: 0.96),
        infoLight: Color(red: 0.94, green: 0.96, blue: 1.00),

        buttonText: .white,
        buttonSecondaryText: Color(red: 0.22, green: 0.25, blue: 0.32),
        buttonDisabledBg: Color(red: 0.82, green: 0.84, blue: 0.86),

        inputBg: .white,
        inputBorder: Color(red: 0.82, green: 0.84, blue: 0.86),
        inputText: Color(red: 0.12, green: 0.16, blue: 0.22),
        inputPlaceholder: Color(red: 0.61, green: 0.64, blue: 0.69),

        cardBg: .white,
        cardBorder: Color(red: 0.90, green: 0.91, blue: 0.92),

        fontFamily: nil,
        fontFamilyMono: nil,

        borderRadius: 12,
        borderRadiusLg: 16,
        borderRadiusSm: 8
    )
}

/// Partial token surface partners hand in. All-optional so partners
/// only override what they care about; `mergeTheme(_:)` fills the rest
/// and auto-derives related shades from any provided `primary`.
public struct AddressIQThemeOverrides {
    public var primary: Color?
    public var primaryDark: Color?
    public var primaryLight: Color?
    public var secondary: Color?
    public var secondaryDark: Color?
    public var secondaryLight: Color?
    public var accent: Color?
    public var background: Color?
    public var surface: Color?
    public var surfaceSecondary: Color?
    public var modalOverlay: Color?
    public var text: Color?
    public var textSecondary: Color?
    public var textInverse: Color?
    public var textLink: Color?
    public var border: Color?
    public var borderFocused: Color?
    public var divider: Color?
    public var error: Color?
    public var errorLight: Color?
    public var success: Color?
    public var successLight: Color?
    public var warning: Color?
    public var warningLight: Color?
    public var info: Color?
    public var infoLight: Color?
    public var buttonText: Color?
    public var buttonSecondaryText: Color?
    public var buttonDisabledBg: Color?
    public var inputBg: Color?
    public var inputBorder: Color?
    public var inputText: Color?
    public var inputPlaceholder: Color?
    public var cardBg: Color?
    public var cardBorder: Color?
    public var fontFamily: String?
    public var fontFamilyMono: String?
    public var borderRadius: CGFloat?
    public var borderRadiusLg: CGFloat?
    public var borderRadiusSm: CGFloat?

    public init(
        primary: Color? = nil,
        primaryDark: Color? = nil,
        primaryLight: Color? = nil,
        secondary: Color? = nil,
        accent: Color? = nil,
        background: Color? = nil,
        surface: Color? = nil,
        text: Color? = nil,
        textSecondary: Color? = nil,
        border: Color? = nil,
        borderFocused: Color? = nil,
        error: Color? = nil,
        success: Color? = nil,
        buttonText: Color? = nil,
        borderRadius: CGFloat? = nil
    ) {
        self.primary = primary
        self.primaryDark = primaryDark
        self.primaryLight = primaryLight
        self.secondary = secondary
        self.accent = accent
        self.background = background
        self.surface = surface
        self.text = text
        self.textSecondary = textSecondary
        self.border = border
        self.borderFocused = borderFocused
        self.error = error
        self.success = success
        self.buttonText = buttonText
        self.borderRadius = borderRadius
    }
}

/// Merge a partial token override on top of `AddressIQTheme.default`.
/// When the partner provides only `primary`, this auto-derives
/// `primaryDark`, `primaryLight`, `borderFocused`, and `textLink` so a
/// single brand color yields a coherent palette (matches the RN +
/// Android SDKs' behavior).
@available(iOS 15.0, *)
public func mergeTheme(_ overrides: AddressIQThemeOverrides?) -> AddressIQTheme {
    var theme = AddressIQTheme.default
    guard let overrides = overrides else { return theme }

    if let primary = overrides.primary {
        theme.primary = primary
        theme.primaryDark = overrides.primaryDark ?? darken(primary, by: 0.15)
        theme.primaryLight = overrides.primaryLight ?? lighten(primary, by: 0.90)
        theme.borderFocused = overrides.borderFocused ?? primary
        theme.textLink = overrides.textLink ?? primary
    }

    if let v = overrides.primaryDark { theme.primaryDark = v }
    if let v = overrides.primaryLight { theme.primaryLight = v }
    if let v = overrides.secondary { theme.secondary = v }
    if let v = overrides.accent { theme.accent = v }
    if let v = overrides.background { theme.background = v }
    if let v = overrides.surface { theme.surface = v }
    if let v = overrides.text { theme.text = v }
    if let v = overrides.textSecondary { theme.textSecondary = v }
    if let v = overrides.border { theme.border = v }
    if let v = overrides.borderFocused { theme.borderFocused = v }
    if let v = overrides.error { theme.error = v }
    if let v = overrides.success { theme.success = v }
    if let v = overrides.buttonText { theme.buttonText = v }
    if let v = overrides.borderRadius { theme.borderRadius = v }

    return theme
}

@available(iOS 15.0, *)
private func darken(_ color: Color, by fraction: CGFloat) -> Color {
    let f = 1 - max(0, min(1, fraction))
    return color.scaleComponents(by: f)
}

@available(iOS 15.0, *)
private func lighten(_ color: Color, by fraction: CGFloat) -> Color {
    let f = max(0, min(1, fraction))
    return color.blendTowardWhite(by: f)
}

@available(iOS 15.0, *)
private extension Color {
    func scaleComponents(by f: CGFloat) -> Color {
        guard let (r, g, b, a) = rgba else { return self }
        return Color(red: Double(r * f), green: Double(g * f), blue: Double(b * f), opacity: Double(a))
    }

    func blendTowardWhite(by f: CGFloat) -> Color {
        guard let (r, g, b, a) = rgba else { return self }
        return Color(
            red: Double(r + (1 - r) * f),
            green: Double(g + (1 - g) * f),
            blue: Double(b + (1 - b) * f),
            opacity: Double(a)
        )
    }

    /// Best-effort decomposition. Returns nil for system / dynamic
    /// colors we can't introspect at runtime (rare for theme values
    /// which partners pass as concrete RGB).
    var rgba: (CGFloat, CGFloat, CGFloat, CGFloat)? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #else
        return nil
        #endif
    }
}

/// `EnvironmentKey` carrying the active theme through the verify-flow
/// widget tree. Screens read it via `@Environment(\.addressIQTheme)`.
private struct AddressIQThemeKey: EnvironmentKey {
    static let defaultValue: AddressIQTheme = .default
}

public extension EnvironmentValues {
    var addressIQTheme: AddressIQTheme {
        get { self[AddressIQThemeKey.self] }
        set { self[AddressIQThemeKey.self] = newValue }
    }
}
