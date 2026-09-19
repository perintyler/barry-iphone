import Foundation
import SwiftUI

/// App-wide state: server config, session list, connectivity.
@MainActor
final class AppStore: ObservableObject {
    @Published var config: ServerConfig
    @Published var sessions: [Session] = []
    @Published var nextCursor: String?
    @Published var listError: String?
    @Published var isLoading = false
    @Published var connected = true

    var client: BarryClient { BarryClient(config: config) }

    private var refreshTimer: Timer?

    init(config: ServerConfig = .load()) {
        self.config = config
    }

    func updateConfig(_ newConfig: ServerConfig) {
        config = newConfig
        newConfig.save()
        Task { await refreshSessions() }
    }

    func refreshSessions() async {
        if sessions.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let page = try await client.sessions()
            sessions = page.sessions.sorted { sortKey($0) > sortKey($1) }
            nextCursor = page.nextCursor
            listError = nil
            connected = true
        } catch {
            listError = error.localizedDescription
            connected = false
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor else { return }
        do {
            let page = try await client.sessions(cursor: cursor)
            let known = Set(sessions.map(\.id))
            // Re-sort the whole list, never just append: the appended page is
            // in server order, and dropping it on the end unsorted made time
            // run BACKWARDS across the page seam (row 51 older than row 52).
            sessions = (sessions + page.sessions.filter { !known.contains($0.id) })
                .sorted { sortKey($0) > sortKey($1) }
            nextCursor = page.nextCursor
        } catch {
            // Keep the list we have; pagination can retry on next scroll.
        }
    }

    /// Running sessions first, then by recency.
    private func sortKey(_ s: Session) -> (Int, Date) {
        (s.isRunning ? 1 : 0, s.activityDate)
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshSessions() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
