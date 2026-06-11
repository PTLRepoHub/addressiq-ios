// Addresses screen (§6 canon, P1-1): lists collected location codes;
// tapping one re-verifies via `startVerification`.
import SwiftUI
import AddressIQ

struct AddressesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var busyCode: String?

    var body: some View {
        Form {
            if model.locationCodes.isEmpty {
                Section {
                    Text("No addresses yet. Collect one from the Verify tab.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section("Collected location codes") {
                    ForEach(model.locationCodes, id: \.self) { code in
                        Button {
                            reverify(code)
                        } label: {
                            HStack {
                                Label(code, systemImage: "mappin.circle")
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                if busyCode == code {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .disabled(busyCode != nil)
                    }
                }
            }
        }
        .navigationTitle("Addresses")
    }

    private func reverify(_ code: String) {
        busyCode = code
        Task {
            do {
                let result = try await AddressIQ.shared.startVerification(
                    StartDigitalArgs(locationCode: code)
                )
                model.refreshLifecycle()
                model.present(ResultModal(
                    title: "Re-verified",
                    type: "DIGITAL",
                    verificationCode: result.verificationCode,
                    locationCode: code,
                    status: result.status
                ))
            } catch {
                model.present(ResultModal(title: "Re-verify failed", error: error))
            }
            busyCode = nil
        }
    }
}
