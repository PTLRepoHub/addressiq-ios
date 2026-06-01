import SwiftUI

/// Pill-style step indicator. The active step's pill grows wider so
/// users can scan progress at a glance. Mirrors the React Native /
/// Flutter / Android widgets' visual language.
@available(iOS 15.0, *)
struct StepIndicator: View {
    let totalSteps: Int
    let currentStep: Int

    @Environment(\.addressIQTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                let isCompletedOrCurrent = index <= currentStep
                let isCurrent = index == currentStep
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCompletedOrCurrent ? theme.primary : theme.border)
                    .frame(width: isCurrent ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .padding(.vertical, 12)
    }
}
