import SwiftUI

@available(iOS 15.0, *)
struct LocationPermissionView: View {
    let onGranted: () -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme
    @State private var requesting = false
    @State private var denied = false

    var body: some View {
        ScreenScaffold(
            onClose: onCancel,
            scrollable: false,
            content: {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)
                    ZStack {
                        Circle()
                            .fill(theme.primaryLight)
                            .frame(width: 80, height: 80)
                        Image(systemName: "location.fill")
                            .font(.system(size: 40))
                            .foregroundColor(theme.primary)
                    }
                    Spacer().frame(height: 20)
                    Text("Enable Location")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(theme.text)
                    Spacer().frame(height: 12)
                    Text("To verify your address, we need access to your location. Please keep location services turned on during the verification period (2-7 days).")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)

                    if denied {
                        Spacer().frame(height: 20)
                        Text("Location permission was denied. Please go to Settings and enable location access for this app.")
                            .font(.system(size: 13))
                            .foregroundColor(theme.error)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(theme.errorLight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.error, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer().frame(height: 24)

                    VStack(spacing: 10) {
                        infoRow(icon: "lock.fill", text: "Your location data is encrypted and secure")
                        infoRow(icon: "clock", text: "Location is collected periodically, not continuously")
                        infoRow(icon: "hand.raised.fill", text: "You can opt out at any time")
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            },
            footer: {
                VStack(spacing: 10) {
                    AddressIQButton(
                        title: "Enable Location",
                        action: {
                            Task {
                                requesting = true
                                let state = await AddressIQ.shared.requestPermissions()
                                requesting = false
                                if state["foregroundLocation"] == "GRANTED" {
                                    onGranted()
                                } else {
                                    denied = true
                                }
                            }
                        },
                        loading: requesting
                    )
                    if denied {
                        AddressIQButton(
                            title: "Open Settings",
                            action: { Task { _ = await AddressIQ.shared.openSettings() } },
                            variant: .outline
                        )
                    }
                }
            }
        )
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.primaryLight)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(theme.primary)
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(theme.text)
            Spacer()
        }
        .padding(14)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
