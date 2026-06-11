// Settings screen (§6 canon): `logout` / `reset`.
import SwiftUI
import AddressIQ

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var busy = false

    var body: some View {
        Form {
            Section("Session") {
                LabeledRow("App user", model.appUserId)
                LabeledRow("Environment", model.environment.rawValue)
                LabeledRow("Lifecycle", model.lifecycle)
            }

            Section {
                Button {
                    busy = true
                    Task { await model.logout(); busy = false }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(busy)

                Button(role: .destructive) {
                    busy = true
                    Task { await model.reset(); busy = false }
                } label: {
                    Label("Reset SDK", systemImage: "trash")
                }
                .disabled(busy)
            } footer: {
                Text("Log out calls AddressIQ.shared.logout(); Reset calls reset() and clears collected addresses.")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct LabeledRow: View {
    let key: String
    let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }

    var body: some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
