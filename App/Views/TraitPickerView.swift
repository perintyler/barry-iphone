import SwiftUI

/// Full-screen trait picker: every trait always visible, tap to toggle.
/// Same visual language as ProviderPickerView (name + description row,
/// filled/empty circle for selection state, accent-tinted row background
/// while selected) but multi-select -- tapping a row toggles it in place
/// rather than dismissing the screen, mirroring the CLI's trait-picker
/// Space key (~/repos/barry/cli/src/prompts/trait-picker.ts) translated
/// to touch.
///
/// Zero traits selected is the normal, fully-supported starting state
/// (matches the web app's NewSessionModal, which also defaults to none
/// selected) -- this picker never nudges toward picking something, and
/// there is no "select all" or required-minimum affordance.
struct TraitPickerView: View {
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var traits: [Trait] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load traits", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    }
                } else {
                    List(traits) { trait in
                        let isSelected = selection.contains(trait.name)
                        Button {
                            toggle(trait.name)
                        } label: {
                            HStack(spacing: 11) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(trait.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(isSelected ? Theme.accent : .primary)
                                    if !trait.description.isEmpty {
                                        Text(trait.description)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary.opacity(0.5))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(isSelected ? Theme.accent.opacity(0.08) : Color.clear)
                        .accessibilityIdentifier("trait-\(trait.name)")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Traits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A subtitle under the nav title, not a separate footer row --
                // keeps the live count visible no matter how far the list is
                // scrolled, matching the CLI's pinned Selected region.
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Traits").font(.headline)
                        Text(selection.isEmpty ? "None selected" : "\(selection.count) selected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("traitPickerDone")
                }
            }
            .task {
                do {
                    traits = try await store.client.traits()
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    private func toggle(_ name: String) {
        if selection.contains(name) {
            selection.remove(name)
        } else {
            selection.insert(name)
        }
    }
}
