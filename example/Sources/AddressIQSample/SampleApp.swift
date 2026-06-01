// AddressIQ iOS SDK — minimal example.
//
// Imports `AddressIQ`, linked to the LOCAL SDK at the repo root via
// `.package(path: "..")`. Drives the core lifecycle on AddressIQ.shared.
import SwiftUI
import AddressIQ

@main
struct AddressIQSampleApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var log: [String] = []
    @State private var lifecycle = "uninitialized"

    private let config = AddressIQConfig(
        apiKey: "aiq_test_demo_bank_seed01",
        environment: .sandbox
    )

    var body: some View {
        VStack(spacing: 16) {
            Text("AddressIQ — iOS SDK").font(.title2).bold()
            Text("Lifecycle: \(lifecycle)").foregroundColor(.secondary)
            Button("initialize → setUser") { Task { await run() } }
                .buttonStyle(.borderedProminent)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    @MainActor
    private func run() async {
        AddressIQ.shared.initialize(config: config)
        append("initialized (\(config.resolvedApiUrl.absoluteString))")
        do {
            try await AddressIQ.shared.setUser(SDKUser(appUserId: "cust_sample_001"))
            let state = AddressIQ.shared.getVerificationState()
            lifecycle = state.state.rawValue
            append("user set; lifecycle = \(state.state.rawValue)")
        } catch {
            append("error: \(error)")
        }
    }

    private func append(_ line: String) { log.append(line) }
}
