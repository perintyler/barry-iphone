import SwiftUI

struct ProviderPickerView: View {
    @Binding var selection: String
    let defaultProvider: String
    let catalog: ModelsResponse?
    let loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let catalog {
                    List(catalog.providerIDs, id: \.self) { provider in
                        Button {
                            selection = provider
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(catalog.label(for: provider))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(provider == defaultProvider ? "Current default" : provider)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if provider == selection {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Providers unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError ?? "Loading the provider catalog…")
                    }
                }
            }
            .navigationTitle("Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
