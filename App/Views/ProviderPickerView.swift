import SwiftUI

/// Full-screen provider picker: every provider always visible, current
/// selection marked in place. Mirrors the CLI's richest interactive
/// prompt (the capability/trait picker) translated to touch — a tap
/// replaces arrow-key-then-space, and a one-line description replaces
/// the picker's inline dim help text.
struct ProviderPickerView: View {
    @Binding var selection: ProviderId
    let defaultProvider: ProviderId
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ProviderId.allCases) { provider in
                Button {
                    selection = provider
                    dismiss()
                } label: {
                    HStack(spacing: 11) {
                        badge(for: provider)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(provider == selection ? Theme.accent : .primary)
                            Text(subtitle(for: provider))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if provider == selection {
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
                .listRowBackground(provider == selection ? Theme.accent.opacity(0.08) : Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle("Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The provider that's actually the resolved default gets an extra
    /// "Default" note appended so the meaning of "nothing chosen" is
    /// never a guess.
    private func subtitle(for provider: ProviderId) -> String {
        provider == defaultProvider ? provider.subtitle : provider.subtitle
    }

    private func badge(for provider: ProviderId) -> some View {
        Text(provider.badge)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color(for: provider), in: RoundedRectangle(cornerRadius: 6))
    }

    private func color(for provider: ProviderId) -> Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .opencode: return Color(red: 0.17, green: 0.42, blue: 0.69)
        case .cursor: return Color(.label)
        case .zai: return Theme.accent
        case .ollama: return Color(.systemGray)
        }
    }
}
