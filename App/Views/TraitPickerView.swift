import SwiftUI

/// Full-screen trait picker: every trait filterable by search, tap to
/// toggle. Same visual language as ProviderPickerView (name + description
/// row, filled/empty circle for selection state, accent-tinted row
/// background while selected) but multi-select -- tapping a row toggles it
/// in place rather than dismissing the screen, mirroring the CLI's
/// trait-picker Space key (~/repos/barry/cli/src/prompts/trait-picker.ts)
/// translated to touch. Search mirrors that same picker's type-to-filter --
/// with 119 real traits (confirmed against the live API), a flat list
/// without it is not usable.
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
    @State private var searchText = ""

    /// Name match first (what someone actually types to find a specific
    /// trait), description match second -- both case-insensitive substring,
    /// matching the CLI picker's own fuzzy-but-simple filtering rather than
    /// requiring an exact prefix.
    private var filteredTraits: [Trait] {
        guard !searchText.isEmpty else { return traits }
        let query = searchText.lowercased()
        return traits.filter {
            $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)
        }
    }

    /// Traits the user already picked stay visible above the fold even
    /// while a search query hides them from the filtered list below --
    /// losing sight of a selection because it scrolled off-filter would be
    /// a real usability trap with 119 items.
    private var selectedNotInFilter: [Trait] {
        guard !searchText.isEmpty else { return [] }
        let filteredNames = Set(filteredTraits.map(\.name))
        return traits.filter { selection.contains($0.name) && !filteredNames.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load traits", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    }
                } else if traits.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !selectedNotInFilter.isEmpty {
                            Section("Selected") {
                                ForEach(selectedNotInFilter) { trait in
                                    traitRow(trait)
                                }
                            }
                        }
                        Section {
                            ForEach(filteredTraits) { trait in
                                traitRow(trait)
                            }
                        }
                        if filteredTraits.isEmpty && !searchText.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search traits")
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

    private func traitRow(_ trait: Trait) -> some View {
        let isSelected = selection.contains(trait.name)
        return Button {
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

    private func toggle(_ name: String) {
        if selection.contains(name) {
            selection.remove(name)
        } else {
            selection.insert(name)
        }
    }
}
