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

struct SettingsView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var preferences: AppPreferences
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preferences.text(.settings))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.close))
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingPickers
                    parserList
                }
                .padding(16)
            }
        }
        .frame(width: 620, height: 680)
        .preferredColorScheme(preferences.theme == .dark ? .dark : .light)
    }

    private var settingPickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(preferences.text(.language))
                .font(.subheadline.weight(.semibold))
            Picker(preferences.text(.language), selection: $preferences.language) {
                Text(preferences.text(.chinese)).tag(AppLanguage.zh)
                Text(preferences.text(.english)).tag(AppLanguage.en)
            }
            .pickerStyle(.segmented)

            Text(preferences.text(.theme))
                .font(.subheadline.weight(.semibold))
                .padding(.top, 6)
            Picker(preferences.text(.theme), selection: $preferences.theme) {
                Text(preferences.text(.light)).tag(AppTheme.light)
                Text(preferences.text(.dark)).tag(AppTheme.dark)
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .interactiveCard()
    }

    private var parserList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preferences.text(.parsers))
                .font(.subheadline.weight(.semibold))
            ForEach(model.parserInfos) { info in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { preferences.isParserEnabled(info.name) },
                        set: { preferences.setParser(info.name, enabled: $0) }
                    )) {
                        Text(info.name)
                            .font(.headline)
                    }
                    .toggleStyle(.checkbox)

                    Text(description(for: info))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !info.examples.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(preferences.text(.examples))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(info.examples) { example in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(preferences.text(.clipboardContent))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(example.input)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(preferences.text(.expectedOutput))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 3)
                                    Text(expected(for: example))
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.separator, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(12)
                .interactiveCard()
            }
        }
    }

    private func description(for info: ParserInfo) -> String {
        preferences.language == .zh ? info.zhDescription : info.enDescription
    }

    private func expected(for example: ParserExample) -> String {
        preferences.language == .zh ? example.zhExpected : example.enExpected
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private lazy var model = ClipboardModel(preferences: preferences)
    private let overlayPresenter = FloatingOverlayPresenter()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var popoverHoverTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        model.onNewResults = { [weak self] content, results in
            guard let self else { return }
            self.overlayPresenter.show(
                content: content,
                results: results,
                preferences: self.preferences,
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
        popover.contentViewController = NSHostingController(rootView: ClipboardPopoverView(
            model: model,
            preferences: preferences,
            openSettings: { [weak self] in self?.openSettingsWindow() }
        ))
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
        startPopoverHoverMonitor()
    }

    private func startPopoverHoverMonitor() {
        popoverHoverTimer?.invalidate()
        popoverHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfMouseOutside()
            }
        }
    }

    private func closePopoverIfMouseOutside() {
        guard popover.isShown else {
            popoverHoverTimer?.invalidate()
            popoverHoverTimer = nil
            return
        }

        let mouse = NSEvent.mouseLocation
        let popoverFrame = popover.contentViewController?.view.window?.frame ?? .zero
        let buttonFrame = statusItem?.button?.window?.frame ?? .zero
        if popoverFrame.insetBy(dx: -8, dy: -8).contains(mouse) || buttonFrame.insetBy(dx: -8, dy: -8).contains(mouse) {
            return
        }

        popover.performClose(nil)
        popoverHoverTimer?.invalidate()
        popoverHoverTimer = nil
    }

    private func openSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = preferences.text(.settings)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(
            model: model,
            preferences: preferences,
            close: { [weak self] in self?.settingsWindow?.close() }
        ))
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh
    case en

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published private(set) var disabledParserNames: Set<String> {
        didSet { defaults.set(Array(disabledParserNames).sorted(), forKey: Keys.disabledParsers) }
    }

    private let defaults = UserDefaults.standard

    init() {
        self.language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .zh
        self.theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .light
        self.disabledParserNames = Set(defaults.stringArray(forKey: Keys.disabledParsers) ?? [])
    }

    func isParserEnabled(_ name: String) -> Bool {
        !disabledParserNames.contains(name)
    }

    func setParser(_ name: String, enabled: Bool) {
        if enabled {
            disabledParserNames.remove(name)
        } else {
            disabledParserNames.insert(name)
        }
    }

    func enabledParserNames(from allNames: [String]) -> Set<String> {
        Set(allNames.filter { isParserEnabled($0) })
    }

    func text(_ key: TextKey) -> String {
        key.value(language)
    }

    private enum Keys {
        static let language = "app.language"
        static let theme = "app.theme"
        static let disabledParsers = "app.disabledParsers"
    }
}

enum TextKey {
    case history
    case copyFirstResult
    case copyResult
    case currentClipboard
    case copyOriginal
    case paused
    case waiting
    case emptyHint
    case refreshHistory
    case quit
    case clearHistory
    case noHistory
    case settings
    case language
    case chinese
    case english
    case theme
    case light
    case dark
    case parsers
    case pause
    case resume
    case copyHistoryResult
    case copied
    case openSettings
    case close
    case description
    case examples
    case clipboardContent
    case expectedOutput

    func value(_ language: AppLanguage) -> String {
        switch (language, self) {
        case (.zh, .history): "历史"
        case (.en, .history): "History"
        case (.zh, .copyFirstResult): "复制第一条结果"
        case (.en, .copyFirstResult): "Copy first result"
        case (.zh, .copyResult): "复制解析结果"
        case (.en, .copyResult): "Copy result"
        case (.zh, .currentClipboard): "当前剪切板"
        case (.en, .currentClipboard): "Current clipboard"
        case (.zh, .copyOriginal): "复制原文"
        case (.en, .copyOriginal): "Copy original"
        case (.zh, .paused): "已暂停监听"
        case (.en, .paused): "Paused"
        case (.zh, .waiting): "等待剪切板内容"
        case (.en, .waiting): "Waiting for clipboard"
        case (.zh, .emptyHint): "复制可解析内容后会在这里显示。"
        case (.en, .emptyHint): "Copy supported content to show parsed results here."
        case (.zh, .refreshHistory): "刷新历史"
        case (.en, .refreshHistory): "Refresh history"
        case (.zh, .quit): "退出"
        case (.en, .quit): "Quit"
        case (.zh, .clearHistory): "清空历史"
        case (.en, .clearHistory): "Clear history"
        case (.zh, .noHistory): "暂无历史"
        case (.en, .noHistory): "No history"
        case (.zh, .settings): "设置"
        case (.en, .settings): "Settings"
        case (.zh, .language): "语言"
        case (.en, .language): "Language"
        case (.zh, .chinese): "中文"
        case (.en, .chinese): "Chinese"
        case (.zh, .english): "英文"
        case (.en, .english): "English"
        case (.zh, .theme): "主题"
        case (.en, .theme): "Theme"
        case (.zh, .light): "浅色"
        case (.en, .light): "Light"
        case (.zh, .dark): "深色"
        case (.en, .dark): "Dark"
        case (.zh, .parsers): "解析器"
        case (.en, .parsers): "Parsers"
        case (.zh, .pause): "暂停监听"
        case (.en, .pause): "Pause"
        case (.zh, .resume): "继续监听"
        case (.en, .resume): "Resume"
        case (.zh, .copyHistoryResult): "复制这条历史结果"
        case (.en, .copyHistoryResult): "Copy this history result"
        case (.zh, .copied): "已复制"
        case (.en, .copied): "Copied"
        case (.zh, .openSettings): "打开设置"
        case (.en, .openSettings): "Open settings"
        case (.zh, .close): "关闭"
        case (.en, .close): "Close"
        case (.zh, .description): "说明"
        case (.en, .description): "Description"
        case (.zh, .examples): "示例"
        case (.en, .examples): "Examples"
        case (.zh, .clipboardContent): "剪切板内容"
        case (.en, .clipboardContent): "Clipboard content"
        case (.zh, .expectedOutput): "预期输出"
        case (.en, .expectedOutput): "Expected output"
        }
    }
}

enum AppSymbols {
    static var primary: NSImage? {
        NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "MCGA")
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MCGA")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MCGA")
    }
}

struct InteractiveIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(background(configuration: configuration))
            )
            .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.70), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }

    private func background(configuration: Configuration) -> Color {
        if configuration.isPressed {
            return Color.accentColor.opacity(0.28)
        }
        if isHovered {
            return Color.accentColor.opacity(0.16)
        }
        return Color.clear
    }
}

private struct InteractiveCardModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.006 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func interactiveCard() -> some View {
        modifier(InteractiveCardModifier())
    }
}

@MainActor
final class ClipboardModel: ObservableObject {
    @Published var isPaused = false
    @Published var currentContent = ""
    @Published var results: [ParseResult] = []
    @Published var history: [HistoryEntry] = []
    @Published var lastUpdated: Date?
    @Published var copyNotice: String?
    var onNewResults: ((String, [ParseResult]) -> Void)?

    private let engine = ParserEngine()
    private let preferences: AppPreferences
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var previousContent = ""

    var parserNames: [String] {
        engine.parserNames
    }

    var parserInfos: [ParserInfo] {
        engine.parserInfos
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
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
        copyNotice = preferences.text(.copied)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run {
                if self?.copyNotice == self?.preferences.text(.copied) {
                    self?.copyNotice = nil
                }
            }
        }
    }

    private func pollClipboard() {
        guard !isPaused else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let content = pasteboard.string(forType: .string), content != currentContent else { return }

        let parsed = engine.parseAll(
            content,
            previousContent: previousContent,
            enabledParserNames: preferences.enabledParserNames(from: engine.parserNames)
        )
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
        preferences: AppPreferences,
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
            preferences: preferences,
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
    @ObservedObject var preferences: AppPreferences
    let copy: (String) -> Void
    let showHistory: () -> Void

    var body: some View {
        let palette = OverlayPalette(theme: preferences.theme)
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
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.history))
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
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(palette.header)

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
                                    copy(result.parsed)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(InteractiveIconButtonStyle())
                                .help(preferences.text(.copyResult))
                            }
                            Text(result.parsed)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(palette.text)
                                .textSelection(.enabled)
                            if let details = result.details, details != result.parsed {
                                Text(details)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(palette.border, lineWidth: 1)
                        )
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.border, lineWidth: 1)
        )
        .foregroundStyle(palette.text)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        let parser = results.first?.parserName ?? "MCGA"
        let preview = content.replacingOccurrences(of: "\n", with: " ")
        return "[\(parser)] \(String(preview.prefix(40)))"
    }
}

struct OverlayPalette {
    let header: Color
    let background: Color
    let card: Color
    let border: Color
    let text: Color
    let secondaryText: Color

    init(theme: AppTheme) {
        switch theme {
        case .light:
            self.header = Color(red: 0.10, green: 0.34, blue: 0.38)
            self.background = Color(red: 0.94, green: 0.97, blue: 0.96).opacity(0.98)
            self.card = Color.white.opacity(0.92)
            self.border = Color(red: 0.35, green: 0.47, blue: 0.48).opacity(0.28)
            self.text = Color(red: 0.08, green: 0.13, blue: 0.14)
            self.secondaryText = Color(red: 0.30, green: 0.38, blue: 0.39)
        case .dark:
            self.header = Color(red: 0.05, green: 0.24, blue: 0.29)
            self.background = Color(red: 0.10, green: 0.13, blue: 0.14).opacity(0.98)
            self.card = Color(red: 0.16, green: 0.20, blue: 0.21).opacity(0.96)
            self.border = Color.white.opacity(0.16)
            self.text = Color.white.opacity(0.92)
            self.secondaryText = Color.white.opacity(0.68)
        }
    }
}

struct ClipboardPopoverView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var preferences: AppPreferences
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let notice = model.copyNotice {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .transition(.opacity)
            }
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
        .preferredColorScheme(preferences.theme == .dark ? .dark : .light)
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
            .help(model.isPaused ? preferences.text(.resume) : preferences.text(.pause))

            Button {
                model.refreshHistory()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(preferences.text(.refreshHistory))

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help(preferences.text(.openSettings))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help(preferences.text(.quit))
        }
        .buttonStyle(InteractiveIconButtonStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isPaused ? preferences.text(.paused) : preferences.text(.waiting))
                .font(.title3.weight(.semibold))
            Text(preferences.text(.emptyHint))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(preferences.text(.currentClipboard))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.copy(model.currentContent)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.copyOriginal))
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
                            model.copy(result.parsed)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(InteractiveIconButtonStyle())
                        .help(preferences.text(.copyResult))
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
                .interactiveCard()
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
                Text(preferences.text(.history))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.clearHistory))
            }
            if model.history.isEmpty {
                Text(preferences.text(.noHistory))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.history) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.results.map(\.parserName).joined(separator: ", "))
                            .font(.caption.weight(.semibold))
                        Text(entry.originalPreview)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entry.results.enumerated()), id: \.offset) { _, result in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.parserName)
                                            .font(.caption.weight(.semibold))
                                        Text(result.parsed)
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(4)
                                            .textSelection(.enabled)
                                        if let details = result.details, details != result.parsed {
                                            Text(details)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(6)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        model.copy(result.parsed)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(InteractiveIconButtonStyle())
                                    .help(preferences.text(.copyHistoryResult))
                                }
                                .padding(8)
                                .interactiveCard()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
