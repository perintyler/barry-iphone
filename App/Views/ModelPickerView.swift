import SwiftUI

/// Full-screen model picker for the currently selected provider. Loads
/// the real catalog from GET /api/v1/models — never a hardcoded list, so
/// it can't silently drift from what the server actually supports.
///
/// "Inherit" is always the first row and is a real, selectable option
/// (nil model id), not a placeholder state — selecting it is how the
/// session ends up using the resolved default shown in its subtitle.
struct ModelPickerView: View {
    let provider: ProviderId
    @Binding var selection: String?
    let resolvedDefaultModel: String?
    @Environment(\.dismiss) private var dismiss

    @State private var models: [ModelOption] = []
    @State private var loadError: String?
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load models", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    }
                } else {
                    List {
                        Button {
                            selection = nil
                            dismiss()
                        } label: {
                            row(
                                title: "Inherit",
                                subtitle: resolvedDefaultModel.map { "Resolves to \($0)" } ?? "Account or repo default",
                                isSelected: selection == nil
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selection == nil ? Theme.accent.opacity(0.08) : Color.clear)

                        ForEach(models) { model in
                            Button {
                                selection = model.id
                                dismiss()
                            } label: {
                                row(title: model.label, subtitle: model.id, isSelected: selection == model.id)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(selection == model.id ? Theme.accent.opacity(0.08) : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(provider.displayName) Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                do {
                    let response = try await store.client.models()
                    models = response.models(for: provider)
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    private func row(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.accent : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospaced()
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary.opacity(0.5))
            }
        }
        .padding(.vertical, 2)
    }
}
