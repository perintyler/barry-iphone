import SwiftUI

/// One place for the app's small design vocabulary.
enum Theme {
    /// Barry purple — matches the repo accent used across barry.works.
    static let accent = Color(red: 0.655, green: 0.545, blue: 0.980)

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
