import AppKit
import MCGACore
import SwiftUI

enum AppSymbols {
    static var primary: NSImage? {
        NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "MCGA")
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MCGA")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MCGA")
    }
}

extension Color {
    /// Secondary text that stays readable at caption sizes; `.secondary` is too faint there.
    static var mutedText: Color {
        Color(nsColor: .mutedText)
    }

    /// Accent-colored text with enough contrast on light accent tints.
    static var accentText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor
            let blended = appearance.isDark
                ? accent.blended(withFraction: 0.3, of: .white)
                : accent.blended(withFraction: 0.25, of: .black)
            return blended ?? accent
        })
    }

    static var warningText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(srgbRed: 1, green: 0.71, blue: 0.28, alpha: 1)
                : NSColor(srgbRed: 0.6, green: 0.29, blue: 0, alpha: 1)
        })
    }
}

extension NSColor {
    static var mutedText: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(white: 1, alpha: 0.66) : NSColor(white: 0, alpha: 0.62)
        }
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension ParserCategory {
    var symbolName: String {
        switch self {
        case .custom: "terminal"
        case .generator: "wand.and.stars"
        case .identifier: "number"
        case .network: "globe"
        case .time: "clock"
        case .dataFormat: "curlybraces"
        case .text: "textformat"
        }
    }

    var title: TextKey {
        switch self {
        case .custom: .categoryCustom
        case .generator: .categoryGenerator
        case .identifier: .categoryIdentifier
        case .network: .categoryNetwork
        case .time: .categoryTime
        case .dataFormat: .categoryDataFormat
        case .text: .categoryText
        }
    }
}

struct InteractiveIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background(configuration: configuration))
            )
            .foregroundStyle(Color.mutedText)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private func background(configuration: Configuration) -> Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.14)
        }
        if isHovered {
            return Color.primary.opacity(0.07)
        }
        return Color.clear
    }
}

struct GlyphBadge: View {
    let symbol: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(Color.mutedText)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .accessibilityHidden(true)
    }
}

struct ParserBadge: View {
    let name: String
    var isPrimary = false

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isPrimary ? Color.accentText : Color.mutedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(isPrimary ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
    }
}

struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.mutedText)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

/// Parser output as "label：value" rows when it reads that way, otherwise verbatim.
struct ResultTextView: View {
    let text: String
    let showsFields: Bool
    var headlineSize: CGFloat = 15
    var muted = false
    /// Non-activating panels need AppKit text fields for selection to work.
    var selectableInPanel = false
    var maxLines = 0

    var body: some View {
        switch showsFields ? ResultTextLayout(text) : .plain(text) {
        case .fields(let headline, let fields):
            VStack(alignment: .leading, spacing: 6) {
                if let headline {
                    value(headline, font: .systemFont(ofSize: headlineSize, weight: .semibold))
                }
                if selectableInPanel {
                    // AppKit text fields have no ideal width to size Grid columns with.
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            HStack(alignment: .top, spacing: 12) {
                                label(field.label)
                                    .frame(width: 64, alignment: .leading)
                                value(field.value, font: .monospacedSystemFont(ofSize: 12.5, weight: .regular))
                            }
                        }
                    }
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            GridRow {
                                label(field.label)
                                    .fixedSize()
                                value(field.value, font: .monospacedSystemFont(ofSize: 12.5, weight: .regular))
                            }
                        }
                    }
                }
            }
        case .plain(let text):
            value(text, font: .monospacedSystemFont(ofSize: 12.5, weight: .regular))
        }
    }

    private func label(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 12))
            .foregroundStyle(Color.mutedText)
    }

    @ViewBuilder
    private func value(_ string: String, font: NSFont) -> some View {
        let color: NSColor = muted ? .mutedText : .labelColor
        if selectableInPanel {
            SelectableOverlayText(string, font: font, textColor: color, maxLines: maxLines)
        } else {
            Text(string)
                .font(Font(font as CTFont))
                .foregroundStyle(Color(nsColor: color))
                .lineLimit(maxLines > 0 ? maxLines : nil)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
