import SwiftUI

/// Start a new session: pick a repo, write the first message.
struct NewSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var repos: [Repo] = []
    @State private var selectedRepoPath: String?
    @State private var prompt = ""
    @State private var creating = false
    @State private var error: String?

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
            .task {
                repos = (try? await store.client.repos()) ?? []
                if selectedRepoPath == nil { selectedRepoPath = repos.first?.path }
            }
        }
    }

    private func create() async {
        guard let repoPath = selectedRepoPath else { return }
        creating = true
        defer { creating = false }
        do {
            let session = try await store.client.createDraft(
                repoPath: repoPath, name: nil, provider: nil, model: nil
            )
            try await store.client.sendMessage(sessionId: session.id, content: prompt)
            await store.refreshSessions()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
