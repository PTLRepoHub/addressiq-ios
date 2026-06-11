import SwiftUI

@available(iOS 15.0, *)
struct SuccessView: View {
    let locationCode: String
    let onDone: () -> Void

    @Environment(\.addressIQTheme) private var theme
    @State private var checkScale: CGFloat = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle().fill(theme.success).frame(width: 88, height: 88)
                    Image(systemName: "checkmark").font(.system(size: 48, weight: .bold)).foregroundColor(.white)
                }
                .scaleEffect(checkScale)

                Spacer().frame(height: 28)

                VStack(spacing: 10) {
                    Text("Address Collected")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(theme.text)
                    Text("Your address has been saved. We'll verify you live there once verification starts.")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)

                    Spacer().frame(height: 18)

                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb").font(.system(size: 20)).foregroundColor(theme.primary)
                        Text("Keep your location services turned on so verification can confirm you live here")
                            .font(.system(size: 13))
                            .foregroundColor(theme.text)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(theme.primaryLight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("Reference: \(locationCode)")
                        .font(.system(size: 11).monospaced())
                        .foregroundColor(theme.textSecondary)
                        .padding(.top, 18)
                }
                .opacity(textOpacity)
                .padding(.horizontal, 30)

                Spacer()
            }

            VStack(spacing: 12) {
                AddressIQButton(title: "Done", action: onDone)
                BrandingFooter()
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkScale = 1
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) {
                textOpacity = 1
            }
        }
    }
}
