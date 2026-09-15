import SwiftUI

/// Floating jump controls over the message list -- hidden by default,
/// appearing only once there's somewhere useful to jump to (approved
/// design: "appear only when useful," matching a Messages/Slack-style
/// jump-to-bottom affordance rather than permanent chrome).
///
/// Two independent affordances share one floating stack:
/// - A "scroll to bottom" arrow, shown once scrolled away from the bottom.
/// - Previous/next-user-message arrows, for jumping between the questions
///   *you* asked in a long back-and-forth -- useful specifically because a
///   long tool-call-heavy reply can put many screens of content between one
///   user message and the next, more than a plain scroll gesture is
///   pleasant to cover.
///
/// The actual previous/next/hasPrevious/hasNext decisions live in
/// `JumpNavigation`, a plain struct with no view dependency, so those
/// boundary conditions are unit-tested directly rather than through this
/// view's lifecycle.
struct JumpControls: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var visibility: VisibleUserMessages
    let proxy: ScrollViewProxy
    let isNearBottom: Bool

    private var navigation: JumpNavigation {
        JumpNavigation(
            sequences: chat.userMessageSequences,
            topmostVisible: visibility.topmostVisible(in: chat.userMessageSequences),
            isNearBottom: isNearBottom
        )
    }

    var body: some View {
        let nav = navigation
        VStack(spacing: 8) {
            if nav.hasPrevious {
                jumpButton(systemImage: "chevron.up", identifier: "jumpToPreviousUserMessage") {
                    jump(to: nav.previousTarget)
                }
            }
            if nav.hasNext {
                jumpButton(systemImage: "chevron.down", identifier: "jumpToNextUserMessage") {
                    jump(to: nav.nextTarget)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: nav.hasPrevious)
        .animation(.easeOut(duration: 0.15), value: nav.hasNext)
    }

    private func jump(to sequence: Int?) {
        withAnimation(.easeOut(duration: 0.25)) {
            if let sequence {
                proxy.scrollTo(sequence, anchor: .top)
            } else {
                proxy.scrollTo("bottom")
            }
        }
    }

    private func jumpButton(systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.thickMaterial, in: Circle())
                .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .accessibilityIdentifier(identifier)
        .transition(.scale.combined(with: .opacity))
    }
}
