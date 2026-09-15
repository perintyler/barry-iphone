import SwiftUI

/// One place for the app's small design vocabulary.
enum Theme {
    /// Barry purple — matches the repo accent used across barry.works.
    static let accent = Color(red: 0.655, green: 0.545, blue: 0.980)

    /// Soft accent background for chips/badges/active-picker-segments —
    /// pairs with `accent` the same way the web app's `--accent-soft`
    /// pairs with `--accent`.
    static var accentSoft: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.173, green: 0.141, blue: 0.251, alpha: 1) // #2c2440
                : UIColor(red: 0.937, green: 0.914, blue: 0.984, alpha: 1) // #efe9fb
        })
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "running": return .green
        case "pending", "planning", "starting": return .orange
        case "failed": return .red
        default: return Color(.systemGray3)
        }
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "running": return "Running"
        case "pending": return "Idle"
        case "planning": return "Planning"
        case "completed": return "Done"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        default: return status.capitalized
        }
    }

    /// Diff viewer's semantic colors — ported from the approved mockup's
    /// CSS custom properties (`--diff-add-bg`, `--diff-add-text`, etc),
    /// light/dark pair per token, distinct from the app accent.
    enum Diff {
        static var addBackground: Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.298, green: 0.749, blue: 0.498, alpha: 0.12) // rgba(76,191,127,.12)
                    : UIColor(red: 0.184, green: 0.620, blue: 0.349, alpha: 0.10) // rgba(47,158,89,.10)
            })
        }

        static var addText: Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.435, green: 0.847, blue: 0.608, alpha: 1) // #6fd89b
                    : UIColor(red: 0.118, green: 0.478, blue: 0.259, alpha: 1) // #1e7a42
            })
        }

        static var delBackground: Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.886, green: 0.408, blue: 0.373, alpha: 0.11) // rgba(226,104,95,.11)
                    : UIColor(red: 0.839, green: 0.271, blue: 0.271, alpha: 0.09) // rgba(214,69,69,.09)
            })
        }

        static var delText: Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.941, green: 0.541, blue: 0.502, alpha: 1) // #f08a80
                    : UIColor(red: 0.694, green: 0.200, blue: 0.200, alpha: 1) // #b13333
            })
        }
    }

    /// Bookkeeping ledger's semantic colors — ported from the mockup's
    /// `--success`/`--warn`/`--danger` CSS custom properties. `success` and
    /// `danger` are the exact same tokens as `Diff.addText`/`Diff.delText`
    /// (the mockup's `--success`/`--danger` and `--diff-add-text`/
    /// `--diff-del-text` are the same hex pairs), reused rather than
    /// redefined; `warn` (Open Loops' amber) has no existing equivalent, so
    /// it's added here.
    enum Bookkeeping {
        static var success: Color { Diff.addText }
        static var danger: Color { Diff.delText }

        static var warn: Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.851, green: 0.604, blue: 0.239, alpha: 1) // #d99a3d
                    : UIColor(red: 0.757, green: 0.478, blue: 0.122, alpha: 1) // #c17a1f
            })
        }
    }
}

/// Small colored dot used for session status.
struct StatusDot: View {
    let status: String
    var body: some View {
        Circle()
            .fill(Theme.statusColor(status))
            .frame(width: 8, height: 8)
    }
}
