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

    @State private var selectedProvider: String?
    @State private var selectedModel: String?
    @State private var resolvedDefaultProvider = "claude"
    @State private var resolvedDefaultModel: String?
    @State private var modelCatalog: ModelsResponse?
    @State private var modelCatalogError: String?
    @State private var showProviderPicker = false
    @State private var showModelPicker = false

    // No resolved-default concept for traits (unlike provider/model) -- the
    // web app default is also zero-selected, so an empty Set here is simply
    // correct, not a placeholder awaiting resolution.
    @State private var selectedTraits: Set<String> = []
    @State private var showTraitPicker = false

    /// What the form displays and what actually gets sent — an explicit
    /// choice if the user made one, otherwise the real resolved default.
    private var effectiveProvider: String { selectedProvider ?? resolvedDefaultProvider }

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
                            Text(modelCatalog?.label(for: effectiveProvider) ?? effectiveProvider.capitalized)
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
                    Button { showTraitPicker = true } label: {
                        HStack {
                            Text("Traits").foregroundStyle(.primary)
                            Spacer()
                            Text(traitsRowValue)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("traitsRow")
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
                    selection: Binding(get: { effectiveProvider }, set: { provider in
                        if provider != effectiveProvider { selectedModel = nil }
                        selectedProvider = provider
                    }),
                    defaultProvider: resolvedDefaultProvider,
                    catalog: modelCatalog,
                    loadError: modelCatalogError
                )
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(
                    provider: effectiveProvider,
                    selection: $selectedModel,
                    resolvedDefaultModel: effectiveProvider == resolvedDefaultProvider ? resolvedDefaultModel : nil,
                    catalog: modelCatalog,
                    loadError: modelCatalogError
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showTraitPicker) {
                TraitPickerView(selection: $selectedTraits)
                    .environmentObject(store)
            }
            .task {
                repos = (try? await store.client.repos()) ?? []
                if selectedRepoPath == nil { selectedRepoPath = repos.first?.path }
                await resolveDefaults()
                await loadModels()
            }
            .onChange(of: selectedRepoPath) { previous, _ in
                guard previous != nil else { return }
                selectedModel = nil
                modelCatalog = nil
                Task {
                    await resolveDefaults()
                    await loadModels()
                }
            }
            // An alert, not an inline Form section: the prior inline error
            // rendered at the BOTTOM of the form, below Repository/First
            // message/Provider/Model/Traits -- invisible without scrolling
            // down, which from the user's actual scroll position after
            // tapping Start read as "nothing happened" (confirmed: a real
            // create() failure with no visible feedback). An alert can't be
            // missed regardless of scroll position or keyboard state.
            .alert("Couldn't start session", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    /// "claude-opus-5" when a real default is known and nothing's
    /// overridden, "Default" as a last-resort fallback if resolution
    /// hasn't completed yet, or the explicit override once one is picked.
    private var modelRowValue: String {
        if let selectedModel { return selectedModel }
        if effectiveProvider == resolvedDefaultProvider {
            return resolvedDefaultModel ?? modelCatalog?.providers[effectiveProvider]?.defaultModel ?? "Provider default"
        }
        return modelCatalog?.providers[effectiveProvider]?.defaultModel ?? "Provider default"
    }

    /// "None" with zero picked (the normal starting state, not an error),
    /// the trait name when exactly one is picked, otherwise a count --
    /// mirrors the web app's zero-default chip picker having no traits
    /// checked until the user opts in.
    private var traitsRowValue: String {
        switch selectedTraits.count {
        case 0: return "None"
        case 1: return selectedTraits.first ?? "None"
        default: return "\(selectedTraits.count) selected"
        }
    }

    private func resolveDefaults() async {
        guard let repoPath = selectedRepoPath else { return }
        do {
            let effective = try await store.client.effectiveIdentity(repoPath: repoPath)
            if selectedProvider == nil && resolvedDefaultProvider != effective.defaultProvider {
                selectedModel = nil
            }
            resolvedDefaultProvider = effective.defaultProvider
            resolvedDefaultModel = effective.identity.defaultModel
        } catch {
            // Resolution failing shouldn't block starting a session — the
            // form still works with "Claude" / "Default" shown, same as
            // before this feature existed.
            resolvedDefaultProvider = "claude"
            resolvedDefaultModel = nil
        }
    }

    private func loadModels() async {
        guard let selectedRepoPath else { return }
        do {
            modelCatalog = try await store.client.models(repoPath: selectedRepoPath)
            modelCatalogError = nil
        } catch {
            modelCatalogError = error.localizedDescription
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
                provider: selectedProvider,
                model: selectedModel,
                traits: Array(selectedTraits)
            )
            try await store.client.sendMessage(sessionId: session.id, content: prompt)
            await store.refreshSessions()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
