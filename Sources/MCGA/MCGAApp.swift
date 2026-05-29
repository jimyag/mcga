import AppKit
import MCGACore
import SwiftUI

@main
struct MCGAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ClipboardModel()
    private let overlayPresenter = FloatingOverlayPresenter()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        model.onNewResults = { [weak self] content, results in
            guard let self else { return }
            self.overlayPresenter.show(
                content: content,
                results: results,
                copy: { [weak self] value in self?.model.copy(value) },
                showHistory: { [weak self] in self?.showPopover() }
            )
        }
        model.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = AppSymbols.primary
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.title = " MCGA"
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 560)
        popover.contentViewController = NSHostingController(rootView: ClipboardPopoverView(model: model))
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

enum AppSymbols {
    static var primary: NSImage? {
        NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "MCGA")
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MCGA")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MCGA")
    }
}

@MainActor
final class ClipboardModel: ObservableObject {
    @Published var isPaused = false
    @Published var currentContent = ""
    @Published var results: [ParseResult] = []
    @Published var history: [HistoryEntry] = []
    @Published var lastUpdated: Date?
    var onNewResults: ((String, [ParseResult]) -> Void)?

    private let engine = ParserEngine()
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var previousContent = ""

    var parserNames: [String] {
        engine.parserNames
    }

    func start() {
        refreshHistory()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollClipboard()
            }
        }
        timer?.tolerance = 0.1
    }

    func togglePaused() {
        isPaused.toggle()
    }

    func clearHistory() {
        Task {
            await HistoryStore.shared.clear()
            refreshHistory()
        }
    }

    func refreshHistory() {
        Task {
            let entries = await HistoryStore.shared.recent(30)
            await MainActor.run {
                self.history = entries
            }
        }
    }

    func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    private func pollClipboard() {
        guard !isPaused else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let content = pasteboard.string(forType: .string), content != currentContent else { return }

        let parsed = engine.parseAll(content, previousContent: previousContent)
        previousContent = content
        guard !parsed.isEmpty else { return }

        currentContent = content
        results = parsed
        lastUpdated = Date()
        onNewResults?(content, parsed)
        Task {
            await HistoryStore.shared.append(original: content, results: parsed)
            refreshHistory()
        }
    }
}

@MainActor
final class FloatingOverlayPresenter {
    private var panels: [NSPanel] = []

    func show(
        content: String,
        results: [ParseResult],
        copy: @escaping (String) -> Void,
        showHistory: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else { return }
        while panels.count >= 2 {
            let oldest = panels.removeFirst()
            oldest.orderOut(nil)
        }

        let frame = screen.visibleFrame
        let width = max(380, min(frame.width * 0.28, 520))
        let height = max(280, min(frame.height * 0.38, 420))
        let marginRight = max(16, frame.width * 0.012)
        let marginBottom = max(36, frame.height * 0.07)
        let gap = max(10, frame.height * 0.012)
        let slot = panels.count
        let origin = NSPoint(
            x: frame.maxX - width - marginRight,
            y: frame.minY + marginBottom + CGFloat(slot) * (height + gap)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FloatingOverlayView(
            content: content,
            results: results,
            copy: copy,
            showHistory: showHistory
        ))

        panels.append(panel)
        panel.orderFrontRegardless()

        Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let panel else { return }
            while panel.frame.contains(NSEvent.mouseLocation) {
                try? await Task.sleep(for: .milliseconds(300))
            }
            panel.orderOut(nil)
            self.panels.removeAll { $0 === panel }
        }
    }
}

struct FloatingOverlayView: View {
    let content: String
    let results: [ParseResult]
    let copy: (String) -> Void
    let showHistory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: AppSymbols.primary ?? NSImage())
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Button {
                    showHistory()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("历史记录")
                Button {
                    if let first = results.first {
                        copy(first.details ?? first.parsed)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制第一条结果")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(OverlayPalette.header)

            Divider().opacity(0.18)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("[ \(result.parserName) ]")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Spacer()
                                Button {
                                    copy(result.details ?? result.parsed)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .help("复制解析结果")
                            }
                            Text(result.parsed)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(OverlayPalette.text)
                                .textSelection(.enabled)
                            if let details = result.details, details != result.parsed {
                                Text(details)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(OverlayPalette.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(OverlayPalette.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(OverlayPalette.border, lineWidth: 1)
                        )
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(OverlayPalette.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OverlayPalette.border, lineWidth: 1)
        )
        .foregroundStyle(OverlayPalette.text)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        let parser = results.first?.parserName ?? "MCGA"
        let preview = content.replacingOccurrences(of: "\n", with: " ")
        return "[\(parser)] \(String(preview.prefix(40)))"
    }
}

enum OverlayPalette {
    static let header = Color(red: 0.10, green: 0.34, blue: 0.38)
    static let background = Color(red: 0.94, green: 0.97, blue: 0.96).opacity(0.98)
    static let card = Color.white.opacity(0.92)
    static let border = Color(red: 0.35, green: 0.47, blue: 0.48).opacity(0.28)
    static let text = Color(red: 0.08, green: 0.13, blue: 0.14)
    static let secondaryText = Color(red: 0.30, green: 0.38, blue: 0.39)
}

struct ClipboardPopoverView: View {
    @ObservedObject var model: ClipboardModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.results.isEmpty {
                        emptyState
                    } else {
                        currentContent
                        resultList
                    }
                    historyView
                }
                .padding(14)
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppSymbols.primary ?? NSImage())
                .symbolRenderingMode(.hierarchical)
            Text("MCGA")
                .font(.headline)
            Spacer()
            Button {
                model.togglePaused()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
            }
            .help(model.isPaused ? "继续监听" : "暂停监听")

            Button {
                model.refreshHistory()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新历史")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isPaused ? "已暂停监听" : "等待剪切板内容")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当前剪切板")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.copy(model.currentContent)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制原文")
            }
            Text(model.currentContent)
                .font(.system(.body, design: .monospaced))
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.results) { result in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(result.parserName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            model.copy(result.details ?? result.parsed)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("复制解析结果")
                    }
                    Text(result.parsed)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let details = result.details, details != result.parsed {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("历史")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .help("清空历史")
            }
            if model.history.isEmpty {
                Text("暂无历史")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.history) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.results.map(\.parserName).joined(separator: ", "))
                            .font(.caption.weight(.semibold))
                        Text(entry.originalPreview)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
