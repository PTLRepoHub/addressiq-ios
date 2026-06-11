// Login screen (§6 canon): environment picker + appUserId field →
// `initialize` + `setUser`.
import SwiftUI
import AddressIQ

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var busy = false

    var body: some View {
        NavigationView {
            Form {
                Section("Credentials") {
                    TextField("API key", text: $model.apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("App user ID", text: $model.appUserId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Environment") {
                    Picker("Environment", selection: $model.environment) {
                        Text("Sandbox").tag(AddressIQEnvironment.sandbox)
                        Text("Production").tag(AddressIQEnvironment.production)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button {
                        busy = true
                        Task { await model.login(); busy = false }
                    } label: {
                        HStack {
                            Text("Log in")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || model.apiKey.isEmpty || model.appUserId.isEmpty)
                } footer: {
                    Text("Calls AddressIQ.shared.initialize(config:) then setUser(_:).")
                }
            }
            .navigationTitle("AddressIQ Sample")
        }
    }
}
