import SwiftUI

/// Common screen scaffold for the verify-flow views. Owns the header
/// bar (back / step indicator / close), the scrollable content column,
/// and the optional footer slot for action buttons + branding.
@available(iOS 15.0, *)
struct ScreenScaffold<Content: View, Footer: View>: View {
    let title: String?
    let subtitle: String?
    let step: Int?
    let totalSteps: Int?
    let onBack: (() -> Void)?
    let onClose: (() -> Void)?
    let scrollable: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.addressIQTheme) private var theme

    init(
        title: String? = nil,
        subtitle: String? = nil,
        step: Int? = nil,
        totalSteps: Int? = nil,
        onBack: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        scrollable: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.step = step
        self.totalSteps = totalSteps
        self.onBack = onBack
        self.onClose = onClose
        self.scrollable = scrollable
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            body_content
            footer_content
        }
        .background(theme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            if let onBack = onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(theme.text)
                        .frame(width: 44, height: 44)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            if let step = step, let totalSteps = totalSteps {
                StepIndicator(totalSteps: totalSteps, currentStep: step)
            }

            Spacer()

            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var body_content: some View {
        if scrollable {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var titleBlock: some View {
        if title != nil || subtitle != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let title = title {
                    Text(title)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(theme.text)
                }
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var footer_content: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 14) {
                footer()
                BrandingFooter()
            }
            .padding(20)
            .background(theme.background)
        }
    }
}

@available(iOS 15.0, *)
extension ScreenScaffold where Footer == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        step: Int? = nil,
        totalSteps: Int? = nil,
        onBack: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        scrollable: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            step: step,
            totalSteps: totalSteps,
            onBack: onBack,
            onClose: onClose,
            scrollable: scrollable,
            content: content,
            footer: { EmptyView() }
        )
    }
}
