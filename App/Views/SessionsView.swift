import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false
    @State private var showNewSession = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.sessions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.listError, store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("Can't reach Barry", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Settings") { showSettings = true }
                        Button("Retry") { Task { await store.refreshSessions() } }
                    }
                } else {
                    sessionList
                }
            }
            .navigationTitle("Barry")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewSession = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityIdentifier("newSessionButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showNewSession) {
                NewSessionView()
            }
            .task {
                await store.refreshSessions()
                store.startAutoRefresh()
            }
            .onDisappear { store.stopAutoRefresh() }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(store.sessions) { session in
                NavigationLink(value: session.id) {
                    SessionRow(session: session)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .onAppear {
                    if session.id == store.sessions.last?.id {
                        Task { await store.loadMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refreshSessions() }
        .navigationDestination(for: String.self) { sessionId in
            if let session = store.sessions.first(where: { $0.id == sessionId }) {
                ChatView(session: session, config: store.config)
            }
        }
        .accessibilityIdentifier("sessionsList")
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusDot(status: session.status)
                Text(session.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(ISO8601.compactAge(session.lastMessageAt ?? session.createdAt))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                if let repo = session.repoName {
                    Text(repo)
                }
                if let update = session.statusUpdate?.summary, session.isRunning {
                    Text(update)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
        }
        .padding(.vertical, 6)
    }
}
