import SwiftUI

struct ModelPickerView: View {
    let provider: String
    @Binding var selection: String?
    let resolvedDefaultModel: String?
    let catalog: ModelsResponse?
    let loadError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var providerModels: ProviderModels? { catalog?.providers[provider] }

    private var matches: [ModelOption] {
        let models = providerModels?.models ?? []
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(query)
                || $0.label.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let providerModels {
                    List {
                        if providerModels.stale == true || providerModels.source != "live" {
                            Section {
                                Label("This is Barry's saved list. It may omit models available from \(catalog?.label(for: provider) ?? provider). Search to enter another model ID.",
                                      systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            Button {
                                selection = nil
                                dismiss()
                            } label: {
                                row(title: "Inherit", subtitle: "Uses \(resolvedDefaultModel ?? providerModels.defaultModel ?? "the provider default")",
                                    note: nil, isSelected: selection == nil)
                            }
                            .buttonStyle(.plain)
                        }

                        Section("Available models") {
                            ForEach(matches) { model in
                                Button {
                                    selection = model.id
                                    dismiss()
                                } label: {
                                    row(title: model.label, subtitle: model.id, note: model.note,
                                        isSelected: selection == model.id)
                                }
                                .buttonStyle(.plain)
                            }

                            let customID = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !customID.isEmpty && !providerModels.models.contains(where: { $0.id == customID }) {
                                Button("Use model ID “\(customID)”") {
                                    selection = customID
                                    dismiss()
                                }
                            }
                        }
                    }
                    .searchable(text: $query, prompt: "Search models or enter an ID")
                } else {
                    ContentUnavailableView {
                        Label("Models unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError ?? "Loading the model catalog…")
                    }
                }
            }
            .navigationTitle("\(catalog?.label(for: provider) ?? provider) Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, subtitle: String, note: String?, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).monospaced()
                if let note { Text(note).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 2)
    }
}
