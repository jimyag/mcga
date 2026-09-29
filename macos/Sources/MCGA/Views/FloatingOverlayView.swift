import AppKit
import MCGACore
import SwiftUI

@MainActor
final class OverlayCountdown: ObservableObject {
    /// Fraction of the display time left, 1 to 0.
    @Published var remaining: Double = 1
}

@MainActor
final class FloatingOverlayPresenter {
    static let width: CGFloat = 360
    private static let lifetime: TimeInterval = 5
    private var panels: [NSPanel] = []

    func show(
        content: String,
        results: [ParseResult],
        category: @escaping (String) -> ParserCategory,
        preferences: AppPreferences,
        copy: @escaping (String) -> Void,
        showHistory: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else { return }
        while panels.count >= 2 {
            panels.removeFirst().orderOut(nil)
        }

        let countdown = OverlayCountdown()
        let hostingView = NSHostingView(rootView: FloatingOverlayView(
            content: content,
            results: results,
            category: category,
            preferences: preferences,
            countdown: countdown,
            copy: copy,
            showHistory: showHistory
        ))
        let height = min(hostingView.fittingSize.height, screen.visibleFrame.height * 0.5)
        let panel = NonActivatingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView

        panels.append(panel)
        layoutPanels(on: screen)
        panel.orderFrontRegardless()
        dismissWhenIdle(panel, countdown: countdown, screen: screen)
    }

    /// Stacks the panels upward from the bottom-right corner, oldest lowest.
    private func layoutPanels(on screen: NSScreen) {
        let frame = screen.visibleFrame
        let marginRight = max(16, frame.width * 0.012)
        let gap = max(10, frame.height * 0.012)
        var y = frame.minY + max(36, frame.height * 0.07)
        for panel in panels {
            let target = NSRect(origin: NSPoint(x: frame.maxX - Self.width - marginRight, y: y), size: panel.frame.size)
            if panel.isVisible {
                NSAnimationContext.runAnimationGroup { _ in
                    panel.animator().setFrame(target, display: true)
                }
            } else {
                panel.setFrame(target, display: false)
            }
            y += panel.frame.height + gap
        }
    }

    /// Counts down only while the pointer is outside the panel, so a result being read stays.
    private func dismissWhenIdle(_ panel: NSPanel, countdown: OverlayCountdown, screen: NSScreen) {
        Task { [weak self, weak panel] in
            let step: TimeInterval = 0.1
            var remaining = Self.lifetime
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(step))
                guard let panel, panel.isVisible else { return }
                remaining = panel.frame.contains(NSEvent.mouseLocation) ? Self.lifetime : remaining - step
                // Unchanged values must not publish: a redraw resets any text selection in the panel.
                let fraction = max(0, remaining / Self.lifetime)
                if countdown.remaining != fraction {
                    countdown.remaining = fraction
                }
            }
            panel?.orderOut(nil)
            guard let self else { return }
            panels.removeAll { $0 === panel }
            layoutPanels(on: screen)
        }
    }
}

struct FloatingOverlayView: View {
    let content: String
    let results: [ParseResult]
    let category: (String) -> ParserCategory
    @ObservedObject var preferences: AppPreferences
    /// Observed only by the bar, so ticks do not redraw the selectable text.
    let countdown: OverlayCountdown
    let copy: (String) -> Void
    let showHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let primary = results.first {
                    let kind = category(primary.parserName)
                    VStack(alignment: .leading, spacing: 8) {
                        ParserBadge(name: primary.parserName, isPrimary: true)
                        ResultTextView(
                            text: primary.parsed,
                            showsFields: kind.showsFields,
                            headlineSize: 16,
                            selectableInPanel: true,
                            maxLines: 8
                        )
                        // Formatted data parsers only describe the input in `parsed`; the content is in details.
                        if kind == .dataFormat, let details = primary.details {
                            ResultTextView(text: details, showsFields: false, selectableInPanel: true, maxLines: 12)
                        }
                    }
                    .padding(.trailing, 4)
                }
                if results.count > 1 {
                    moreResultsButton
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.top, 12)
            .padding(.bottom, 14)

            CountdownBar(countdown: countdown)
        }
        .frame(width: FloatingOverlayPresenter.width)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            GlyphBadge(
                symbol: results.first.map { category($0.parserName).symbolName } ?? "text.alignleft",
                size: 22
            )
            Text(content.replacingOccurrences(of: "\n", with: " ").prefix(80))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                showHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(InteractiveIconButtonStyle())
            .help(preferences.text(.openInHistory))

            Button {
                if let first = results.first {
                    copy(first.parsed)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(InteractiveIconButtonStyle())
            .help(preferences.text(.copyFirstResult))
        }
    }

    private var moreResultsButton: some View {
        var names: [String] = []
        for result in results.dropFirst() where !names.contains(result.parserName) {
            names.append(result.parserName)
        }
        return Button {
            showHistory()
        } label: {
            HStack(spacing: 4) {
                Text(String(format: preferences.text(.moreResults), results.count - 1, names.joined(separator: ", ")))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.accentText)
        }
        .buttonStyle(.plain)
    }
}

struct CountdownBar: View {
    @ObservedObject var countdown: OverlayCountdown

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: FloatingOverlayPresenter.width * countdown.remaining)
                .animation(.linear(duration: 0.1), value: countdown.remaining)
        }
        .frame(height: 3)
    }
}

final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Selectable text for non-activating panels, where SwiftUI text selection never gets key status.
struct SelectableOverlayText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let maxLines: Int

    init(_ text: String, font: NSFont, textColor: NSColor, maxLines: Int = 0) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.maxLines = maxLines
    }

    func makeNSView(context: Context) -> OverlaySelectableTextField {
        let field = OverlaySelectableTextField(wrappingLabelWithString: text)
        field.isSelectable = true
        field.isEditable = false
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byWordWrapping
        field.font = font
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: OverlaySelectableTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.font = font
        field.textColor = textColor
        field.maximumNumberOfLines = maxLines
        field.cell?.truncatesLastVisibleLine = maxLines > 0
    }

    /// Wrapped labels report a one-line intrinsic size, so measure at the proposed width.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: OverlaySelectableTextField, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        let measured = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
        var height = ceil(measured.height)
        if maxLines > 0 {
            height = min(height, ceil(NSLayoutManager().defaultLineHeight(for: font) * CGFloat(maxLines)))
        }
        return CGSize(width: proposal.width ?? ceil(measured.width), height: height)
    }
}

final class OverlaySelectableTextField: NSTextField {
    override var needsPanelToBecomeKey: Bool { true }
}
