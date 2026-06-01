import SwiftUI
import CoreLocation

@available(iOS 15.0, *)
struct AddressView: View {
    let initial: AddressDraft
    let onNext: (AddressDraft) -> Void
    let onCancel: () -> Void

    @Environment(\.addressIQTheme) private var theme
    @State private var lat: Double?
    @State private var lon: Double?
    @State private var accuracy: Double = 0
    @State private var formatted: String
    @State private var loading: Bool = false
    @State private var locationDelegate: LocationOneShot?

    init(initial: AddressDraft, onNext: @escaping (AddressDraft) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onNext = onNext
        self.onCancel = onCancel
        _lat = State(initialValue: initial.lat)
        _lon = State(initialValue: initial.lon)
        _formatted = State(initialValue: initial.formattedAddress ?? "")
    }

    var canContinue: Bool { lat != nil && lon != nil && !formatted.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScreenScaffold(
            title: "Confirm your address",
            subtitle: "We'll use your current location and the address you enter to verify where you live.",
            step: 0,
            totalSteps: 3,
            onClose: onCancel,
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    // GPS card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 14))
                                .foregroundColor(theme.primary)
                            Text("CURRENT LOCATION")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(theme.textSecondary)
                        }
                        if loading {
                            HStack(spacing: 10) {
                                ProgressView().tint(theme.primary)
                                Text("Reading GPS…").font(.system(size: 13)).foregroundColor(theme.textSecondary)
                            }
                        } else if let lat = lat, let lon = lon {
                            Text(String(format: "%.6f, %.6f", lat, lon))
                                .font(.system(size: 16, weight: .bold).monospaced())
                                .foregroundColor(theme.text)
                            if accuracy > 0 {
                                Text("±\(Int(accuracy)) m accuracy")
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textSecondary)
                            }
                            Button(action: captureLocation) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                                    Text("Read again").font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(theme.primary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: theme.borderRadiusLg).stroke(theme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadiusLg))

                    Spacer().frame(height: 18)

                    Text("Formatted address")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.text)
                    Spacer().frame(height: 6)
                    TextEditor(text: $formatted)
                        .font(.system(size: 15))
                        .foregroundColor(theme.inputText)
                        .hiddenScrollBackground()
                        .background(theme.inputBg)
                        .frame(minHeight: 80)
                        .padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inputBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer().frame(height: 8)
                    Text("Enter your address exactly as it should appear on official records. The next screen captures property details.")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
                .onAppear { if lat == nil { captureLocation() } }
            },
            footer: {
                AddressIQButton(
                    title: "Continue",
                    action: {
                        var draft = initial
                        draft.lat = lat
                        draft.lon = lon
                        draft.formattedAddress = formatted.trimmingCharacters(in: .whitespaces)
                        onNext(draft)
                    },
                    enabled: canContinue
                )
            }
        )
    }

    private func captureLocation() {
        loading = true
        let delegate = LocationOneShot { loc in
            DispatchQueue.main.async {
                if let loc = loc {
                    self.lat = loc.coordinate.latitude
                    self.lon = loc.coordinate.longitude
                    self.accuracy = loc.horizontalAccuracy
                }
                self.loading = false
                self.locationDelegate = nil
            }
        }
        locationDelegate = delegate
        delegate.start()
    }
}

private final class LocationOneShot: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let onComplete: (CLLocation?) -> Void
    private var done = false

    init(onComplete: @escaping (CLLocation?) -> Void) {
        self.onComplete = onComplete
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !done, let loc = locations.last else { return }
        done = true
        onComplete(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !done else { return }
        done = true
        onComplete(nil)
    }
}
