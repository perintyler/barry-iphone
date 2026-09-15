import SwiftUI
import MarkdownUI

/// MarkdownUI theme for assistant messages -- ports the mockup's approved
/// look (inline code in accent purple on a soft accent chip, code blocks in
/// the same secondarySystemBackground card surface `DiffView` and
/// `ToolRunGroupView` already use) onto MarkdownUI's theming API, instead of
/// starting from one of the library's bundled themes (`.gitHub`, `.docC`,
/// `.basic`) and overriding pieces -- those are tuned for document reading,
/// not a chat bubble's tighter type scale and lack of a surrounding card.
///
/// Deliberately un-contained: per the approved mockup (Option A, "stays
/// bare" -- the request was explicit: "i kind of like not having a
/// container for the assistant messages"), paragraph and list text carry no
/// background of their own. Only code blocks and tables get a card, because
/// those genuinely need a visual boundary to read as a distinct region
/// (monospaced text, columns) -- everything else sits directly on the
/// screen background like it does today.
extension MarkdownUI.Theme {
    /// Slightly lighter/darker than `Theme.accent` per-appearance, for AA
    /// contrast against `Theme.accentSoft`'s chip background -- broken out
    /// as its own property because the trailing-closure form inline inside
    /// the theme builder chain below was too complex for the type checker
    /// to solve in reasonable time (a real compiler error, not a style
    /// preference).
    static var inlineCodeColor: SwiftUI.Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.784, green: 0.706, blue: 1.0, alpha: 1)
                : UIColor(red: 0.502, green: 0.361, blue: 0.918, alpha: 1)
        })
    }

    static let barry = MarkdownUI.Theme()
        .text {
            FontSize(17) // matches `.body` in AssistantText today
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(MarkdownUI.Theme.inlineCodeColor)
            BackgroundColor(Barry.Theme.accentSoft)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(Barry.Theme.accent)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.22))
                .markdownMargin(top: 0, bottom: 8)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.3)) }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.15)) }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.05)) }
                .markdownMargin(top: 10, bottom: 4)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Barry.Theme.accent)
                    .relativeFrame(width: .em(0.2))
                configuration.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
                    .relativePadding(.horizontal, length: .em(0.9))
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 4, bottom: 8)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.82))
                    }
                    .padding(12)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
            .markdownMargin(top: 4, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color(.separator)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color(.secondarySystemBackground).opacity(0.5))
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 { FontWeight(.semibold) }
                    BackgroundColor(nil)
                    FontSize(.em(0.92))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
        }
        .thematicBreak {
            Divider()
                .markdownMargin(top: 8, bottom: 8)
        }
}
