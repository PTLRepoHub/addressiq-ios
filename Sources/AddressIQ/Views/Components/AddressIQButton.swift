import SwiftUI

public enum AddressIQButtonVariant {
    case primary, secondary, outline, text
}

/// Theme-aware button used throughout the verify flow. Reads the
/// active theme from the SwiftUI environment.
@available(iOS 15.0, *)
struct AddressIQButton: View {
    let title: String
    let action: () -> Void
    var variant: AddressIQButtonVariant = .primary
    var enabled: Bool = true
    var loading: Bool = false

    @Environment(\.addressIQTheme) private var theme

    var body: some View {
        Button(action: { if !loading { action() } }) {
            content
        }
        .disabled(!enabled || loading)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
        .overlay(overlay)
        .opacity((enabled && !loading) ? 1.0 : 0.5)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView()
                .tint(variant == .primary ? theme.buttonText : theme.primary)
        } else {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textColor)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .primary:
            theme.primary
        case .secondary:
            theme.secondaryLight
        case .outline, .text:
            Color.clear
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if variant == .outline {
            RoundedRectangle(cornerRadius: theme.borderRadius)
                .stroke(theme.primary, lineWidth: 1.5)
        } else {
            EmptyView()
        }
    }

    private var textColor: Color {
        switch variant {
        case .primary: return theme.buttonText
        case .secondary: return theme.buttonSecondaryText
        case .outline: return theme.primary
        case .text: return theme.textLink
        }
    }
}

@available(iOS 15.0, *)
struct BrandingFooter: View {
    @Environment(\.addressIQTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11))
                .foregroundColor(theme.textSecondary)
            Text("Powered by AddressIQ")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.top, 8)
    }
}
