import SwiftUI

/// Start a new session: pick a repo, write the first message, optionally
/// override provider/model. Provider and model rows always show a real
/// resolved value (never a bare "Default" placeholder) — selecting a repo
/// fetches what that repo would actually use via
/// GET /api/v1/identities/effective, the same resolution a session start
/// performs server-side.
struct NewSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var repos: [Repo] = []
    @State private var selectedRepoPath: String?
    @State private var prompt = ""
    @State private var creating = false
    @State private var error: String?

    @State private var selectedProvider: ProviderId?
    @State private var selectedModel: String?
    @State private var resolvedDefaultProvider: ProviderId = .claude
    @State private var resolvedDefaultModel: String?
    @State private var showProviderPicker = false
    @State private var showModelPicker = false

    /// What the form displays and what actually gets sent — an explicit
    /// choice if the user made one, otherwise the real resolved default.
    private var effectiveProvider: ProviderId { selectedProvider ?? resolvedDefaultProvider }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    if repos.isEmpty {
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Repository", selection: $selectedRepoPath) {
                            ForEach(repos) { repo in
                                Text(repo.name).tag(Optional(repo.path))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                Section("First message") {
                    TextField("What should Barry do?", text: $prompt, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("newSessionPrompt")
                }
                Section {
                    Button { showProviderPicker = true } label: {
                        HStack {
                            Text("Provider").foregroundStyle(.primary)
                            Spacer()
                            Text(effectiveProvider.displayName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button { showModelPicker = true } label: {
                        HStack {
                            Text("Model").foregroundStyle(.primary)
                            Spacer()
                            Text(modelRowValue)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if creating {
                        ProgressView()
                    } else {
                        Button("Start") { Task { await create() } }
                            .disabled(selectedRepoPath == nil || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("startSessionButton")
                    }
                }
            }
            .sheet(isPresented: $showProviderPicker) {
                ProviderPickerView(
                    selection: Binding(get: { effectiveProvider }, set: { selectedProvider = $0 }),
                    defaultProvider: resolvedDefaultProvider
                )
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(
                    provider: effectiveProvider,
                    selection: $selectedModel,
                    resolvedDefaultModel: resolvedDefaultModel
                )
                .environmentObject(store)
            }
            .task {
                repos = (try? await store.client.repos()) ?? []
                if selectedRepoPath == nil { selectedRepoPath = repos.first?.path }
                await resolveDefaults()
            }
            .onChange(of: selectedRepoPath) { _, _ in
                Task { await resolveDefaults() }
            }
        }
    }

    /// "claude-opus-5" when a real default is known and nothing's
    /// overridden, "Default" as a last-resort fallback if resolution
    /// hasn't completed yet, or the explicit override once one is picked.
    private var modelRowValue: String {
        if let selectedModel { return selectedModel }
        return resolvedDefaultModel ?? "Default"
    }

    private func resolveDefaults() async {
        guard let repoPath = selectedRepoPath else { return }
        do {
            let effective = try await store.client.effectiveIdentity(repoPath: repoPath)
            resolvedDefaultProvider = effective.defaultProvider
            resolvedDefaultModel = effective.identity.defaultModel
        } catch {
            // Resolution failing shouldn't block starting a session — the
            // form still works with "Claude" / "Default" shown, same as
            // before this feature existed.
            resolvedDefaultProvider = .claude
            resolvedDefaultModel = nil
        }
    }

    private func create() async {
        guard let repoPath = selectedRepoPath else { return }
        creating = true
        defer { creating = false }
        do {
            let session = try await store.client.createDraft(
                repoPath: repoPath,
                systemPrompt: prompt,
                name: nil,
                provider: selectedProvider?.rawValue,
                model: selectedModel
            )
            try await store.client.sendMessage(sessionId: session.id, content: prompt)
            await store.refreshSessions()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
