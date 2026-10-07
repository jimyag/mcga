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
    private var panels: [NSPanel] = []
    /// The newest copy's panel, updated in place as slower results arrive.
    private var latest: (id: UInt64, panel: NSPanel, view: NSHostingView<FloatingOverlayView>)?

    func show(
        id: UInt64,
        content: String,
        results: [ParseResult],
        lifetime: TimeInterval,
        category: @escaping (String) -> ParserCategory,
        preferences: AppPreferences,
        copy: @escaping (String) -> Void,
        showHistory: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else { return }
        if let latest, latest.id == id {
            // Once its panel is gone, a copy's later results stay in history instead of popping up again.
            guard latest.panel.isVisible else { return }
            latest.view.rootView.results = results
            latest.panel.setContentSize(NSSize(width: Self.width, height: fittingHeight(of: latest.view, on: screen)))
            layoutPanels(on: screen)
            return
        }
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
            maxHeight: screen.visibleFrame.height * 0.5,
            copy: copy,
            showHistory: showHistory
        ))
        let panel = NonActivatingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: fittingHeight(of: hostingView, on: screen)),
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
        panel.copySelection = copy

        panels.append(panel)
        latest = (id, panel, hostingView)
        layoutPanels(on: screen)
        panel.orderFrontRegardless()
        dismissWhenIdle(panel, countdown: countdown, lifetime: lifetime, screen: screen)
    }

    private func fittingHeight(of view: NSView, on screen: NSScreen) -> CGFloat {
        min(view.fittingSize.height, screen.visibleFrame.height * 0.5)
    }

    /// Stacks the panels downward from the top-right corner, newest highest.
    private func layoutPanels(on screen: NSScreen) {
        let frame = screen.visibleFrame
        let marginRight = max(16, frame.width * 0.012)
        let gap = max(10, frame.height * 0.012)
        var y = frame.maxY - max(16, frame.height * 0.012)
        for panel in panels.reversed() {
            y -= panel.frame.height
            let target = NSRect(origin: NSPoint(x: frame.maxX - Self.width - marginRight, y: y), size: panel.frame.size)
            if panel.isVisible {
                NSAnimationContext.runAnimationGroup { _ in
                    panel.animator().setFrame(target, display: true)
                }
            } else {
                panel.setFrame(target, display: false)
            }
            y -= gap
        }
    }

    /// Counts down only while the pointer is outside the panel, so a result being read stays.
    private func dismissWhenIdle(_ panel: NSPanel, countdown: OverlayCountdown, lifetime: TimeInterval, screen: NSScreen) {
        Task { [weak self, weak panel] in
            let step: TimeInterval = 0.1
            var remaining = lifetime
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(step))
                guard let panel, panel.isVisible else { return }
                remaining = panel.frame.contains(NSEvent.mouseLocation) ? lifetime : remaining - step
                // Unchanged values must not publish: a redraw resets any text selection in the panel.
                let fraction = max(0, remaining / lifetime)
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
    /// Grows while slow parsers report.
    var results: [ParseResult]
    let category: (String) -> ParserCategory
    @ObservedObject var preferences: AppPreferences
    /// Observed only by the bar, so ticks do not redraw the selectable text.
    let countdown: OverlayCountdown
    let maxHeight: CGFloat
    let copy: (String) -> Void
    let showHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    ForEach(results) { result in
                        let kind = category(result.parserName)
                        if result.id != results.first?.id {
                            Divider()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ParserBadge(name: result.parserName, isPrimary: result.id == results.first?.id)
                            // Formatted data parsers only describe the input in `parsed`; the content follows it.
                            ResultTextView(
                                text: kind == .dataFormat ? result.parsed : kind.content(parsed: result.parsed, details: result.details),
                                showsFields: kind.showsFields,
                                headlineSize: 16,
                                selectableInPanel: true
                            )
                            if kind == .dataFormat, let details = result.details {
                                ResultTextView(text: details, showsFields: false, selectableInPanel: true)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: maxHeight - 3)

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
                    copy(category(first.parserName).content(parsed: first.parsed, details: first.details))
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(InteractiveIconButtonStyle())
            .help(preferences.text(.copyFirstResult))
        }
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
    /// Receives the text a click or drag selects, copied as a terminal does.
    var copySelection: ((String) -> Void)?
    /// Whether the button went down on selectable text, so its release ends a selection.
    private var selecting = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            selecting = isSelectableText(at: event.locationInWindow)
        }
        super.sendEvent(event)
        // The selection is final once the mouse-up is handled: as its own event, or inside
        // mouseDown when a text view tracks the drag itself.
        guard selecting, NSApp.currentEvent?.type == .leftMouseUp else { return }
        selecting = false
        guard let editor = firstResponder as? NSTextView else { return }
        let range = editor.selectedRange()
        if range.length > 0 {
            copySelection?((editor.string as NSString).substring(with: range))
        }
    }

    /// Clicks elsewhere, such as on the copy button, must not copy an earlier selection again.
    private func isSelectableText(at point: NSPoint) -> Bool {
        guard let hit = contentView?.hitTest(point) else { return false }
        return sequence(first: hit, next: \.superview).contains { $0 is OverlaySelectableTextField }
    }
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
