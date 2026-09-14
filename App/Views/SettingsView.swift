import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var hostHeader = ""
    @State private var secret = ""
    @State private var testResult: TestResult?

    enum TestResult { case ok, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverURLField")
                    TextField("Host header (optional)", text: $hostHeader)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret (optional)", text: $secret)
                } header: {
                    Text("Server")
                } footer: {
                    Text("On Tailscale, use your Mac's address with host header barry.lan.")
                }
                Section {
                    Button("Test connection") { Task { await test() } }
                    switch testResult {
                    case .ok:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let reason):
                        Label(reason, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    case nil:
                        EmptyView()
                    }
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
                hostHeader = store.config.hostHeader
                secret = store.config.secret
            }
        }
    }

    private func currentConfig() -> ServerConfig {
        ServerConfig(
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            hostHeader: hostHeader.trimmingCharacters(in: .whitespaces),
            secret: secret
        )
    }

    private func test() async {
        let client = BarryClient(config: currentConfig())
        do {
            testResult = try await client.health() ? .ok : .failed("Server said not-ok")
        } catch {
            testResult = .failed(error.localizedDescription)
        }
    }
}
