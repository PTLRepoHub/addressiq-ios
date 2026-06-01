import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 15.0, *)
struct ConsentView: View {
    let address: AddressDraft
    let submitting: Bool
    let privacyPolicyUrl: URL?
    let termsUrl: URL?
    let onSubmit: () -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme
    @State private var consented = false

    var body: some View {
        ScreenScaffold(
            title: "Almost done!",
            step: 2,
            totalSteps: 3,
            onBack: onBack,
            onClose: onCancel,
            content: {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    howItWorks
                    consentRow
                    if termsUrl != nil || privacyPolicyUrl != nil { policyLinks }
                }
            },
            footer: {
                AddressIQButton(
                    title: "Start Verification",
                    action: onSubmit,
                    enabled: consented,
                    loading: submitting
                )
            }
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR ADDRESS").font(.system(size: 11, weight: .bold)).foregroundColor(theme.textSecondary)
            if let formatted = address.formattedAddress, !formatted.isEmpty {
                Text(formatted).font(.system(size: 15, weight: .semibold)).foregroundColor(theme.text)
            }
            Text([address.propertyNumber, address.streetName].compactMap { $0 }.joined(separator: " "))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.text)
            if let color = address.buildingColor, !color.isEmpty {
                HStack(spacing: 6) {
                    Text("Building:").font(.system(size: 13)).foregroundColor(theme.textSecondary)
                    Text(color).font(.system(size: 13, weight: .semibold)).foregroundColor(theme.text)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 20)).foregroundColor(Color(red: 0.60, green: 0.20, blue: 0.07))
                Text("How it works").font(.system(size: 15, weight: .bold)).foregroundColor(Color(red: 0.60, green: 0.20, blue: 0.07))
            }
            ForEach(Array([
                "We'll collect your location in the background for 2-7 days",
                "Keep your location services turned on",
                "Use your phone normally — no action needed",
                "You'll be notified when verification completes",
            ].enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(Color(red: 0.99, green: 0.73, blue: 0.45)).frame(width: 22, height: 22)
                        Text("\(idx + 1)").font(.system(size: 12, weight: .bold)).foregroundColor(Color(red: 0.60, green: 0.20, blue: 0.07))
                    }
                    Text(line).font(.system(size: 13)).foregroundColor(Color(red: 0.47, green: 0.21, blue: 0.06))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1.0, green: 0.97, blue: 0.93))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.99, green: 0.84, blue: 0.66), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var consentRow: some View {
        Button(action: { consented.toggle() }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(consented ? theme.primary : Color.clear).frame(width: 24, height: 24)
                    RoundedRectangle(cornerRadius: 6).stroke(consented ? theme.primary : theme.border, lineWidth: 2).frame(width: 24, height: 24)
                    if consented {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                }
                Text("I agree to background location collection for address verification\((termsUrl != nil || privacyPolicyUrl != nil) ? " and accept the linked policies" : "").")
                    .font(.system(size: 14)).foregroundColor(theme.text)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var policyLinks: some View {
        HStack(spacing: 8) {
            if let termsUrl = termsUrl {
                policyLink("Terms & Conditions", url: termsUrl)
            }
            if let privacyPolicyUrl = privacyPolicyUrl {
                policyLink("Privacy Policy", url: privacyPolicyUrl)
            }
        }
    }

    private func policyLink(_ text: String, url: URL) -> some View {
        Button(action: {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.primary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
        }
    }
}
