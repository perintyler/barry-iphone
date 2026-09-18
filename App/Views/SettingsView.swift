import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var secret = ""
    @State private var outcome: ProbeOutcome?
    @State private var isProbing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(ServerConfig.defaultDeviceURL, text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverURLField")
                    SecureField("BARRY_SECRET (required on the tailnet)", text: $secret)
                        .accessibilityIdentifier("secretField")
                } header: {
                    Text("Server")
                } footer: {
                    Text("On a phone the app reaches the Mac over the tailnet at "
                         + "\(ServerConfig.defaultDeviceURL). The secret is required "
                         + "there — the server rejects an unauthenticated request.")
                }
                Section {
                    Button {
                        Task { await probe() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if isProbing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isProbing)
                    .accessibilityIdentifier("testConnectionButton")

                    if let outcome {
                        Label {
                            Text(outcome.message)
                        } icon: {
                            Image(systemName: icon(for: outcome))
                        }
                        .foregroundStyle(tint(for: outcome))
                        .font(.footnote)
                        .accessibilityIdentifier("probeResult")
                    }
                } footer: {
                    Text("Makes a real request. It tells apart a server that is not "
                         + "reachable from one that is reachable but refused the secret.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.updateConfig(currentConfig())
                        dismiss()
                    }
                }
            }
            .onAppear {
                baseURL = store.config.baseURL
                secret = store.config.secret
            }
        }
    }

    /// Three states, not two: a 403 proved the network path works, so it must
    /// not wear the same red X as a host that never answered.
    private func icon(for outcome: ProbeOutcome) -> String {
        if outcome.isFullyWorking { return "checkmark.circle" }
        return outcome.isReachable ? "exclamationmark.triangle" : "xmark.circle"
    }

    private func tint(for outcome: ProbeOutcome) -> Color {
        if outcome.isFullyWorking { return .green }
        return outcome.isReachable ? .orange : .red
    }

    private func currentConfig() -> ServerConfig {
        ServerConfig(
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            secret: secret
        )
    }

    /// Probes with the values currently ON SCREEN, not the saved ones, so the
    /// button answers "will these work" rather than "did the old ones".
    private func probe() async {
        isProbing = true
        defer { isProbing = false }
        outcome = await ConnectionProbe(config: currentConfig()).run()
    }
}
