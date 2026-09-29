import AppKit
import MCGACore
import SwiftUI

struct ClipboardPopoverView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var preferences: AppPreferences
    let openSettings: () -> Void
    let checkForUpdates: () -> Void
    let close: () -> Void
    let paste: (ClipboardPayload) -> Void
    /// Opens an image in the viewer window; the URL is the file "Open in Preview" hands over.
    let showImage: (NSImage, URL) -> Void
    @State private var searchText = ""
    @State private var selectedHistoryID: UInt64?
    @State private var focusedPane: HistoryFocusPane = .original
    @State private var selectedResultIndex = 0
    /// Clearing asks inline: an alert or a sheet would take key status and close the panel.
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isPaused {
                pausedBanner
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The panel's visual effect view draws the translucent background behind this view.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(HistoryKeyboardCaptureView { handleHistoryKeyAction($0) })
        .overlay(alignment: .top) {
            if let notice = model.copyNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.copyNotice)
        .onAppear {
            selectFirstHistoryIfNeeded()
        }
        .onChange(of: model.history) {
            reconcileHistorySelection()
        }
        .onChange(of: searchText) {
            reconcileHistorySelection()
        }
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mutedText)
                HistorySearchField(
                    text: $searchText,
                    placeholder: preferences.text(.searchHistory)
                )
                .frame(height: 24)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.mutedText)
                    .help(preferences.text(.close))
                }
            }
            .padding(.leading, 6)
            .frame(height: 32)

            if let version = model.availableUpdateVersion {
                Button {
                    checkForUpdates()
                } label: {
                    Label(String(format: preferences.text(.updateAvailable), version), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentText)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            monitoringButton

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(InteractiveIconButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            .help(preferences.text(.openSettings))
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    private var monitoringButton: some View {
        Button {
            model.togglePaused()
        } label: {
            HStack(spacing: 6) {
                if model.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Circle()
                        .fill(Color(nsColor: .systemGreen))
                        .frame(width: 7, height: 7)
                }
                Text(preferences.text(model.isPaused ? .paused : .monitoring))
            }
            .font(.system(size: 12, weight: model.isPaused ? .semibold : .regular))
            .foregroundStyle(model.isPaused ? Color.warningText : Color.mutedText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(model.isPaused ? Color.orange.opacity(0.14) : Color.clear))
            .overlay(
                Capsule().strokeBorder(
                    model.isPaused ? Color.orange.opacity(0.4) : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(preferences.text(model.isPaused ? .resume : .pause))
    }

    private var pausedBanner: some View {
        HStack(spacing: 10) {
            Text(preferences.text(.pausedBanner))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.warningText)
            Spacer(minLength: 8)
            Button(preferences.text(.resume)) {
                model.togglePaused()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.orange.opacity(0.12))
    }

    @ViewBuilder
    private var content: some View {
        let entries = filteredHistory
        if model.history.isEmpty {
            ContentUnavailableView {
                Label(preferences.text(.noHistory), systemImage: "tray")
            } description: {
                Text(preferences.text(.emptyHint))
            }
        } else if entries.isEmpty {
            ContentUnavailableView {
                Label(preferences.text(.noSearchResults), systemImage: "magnifyingglass")
            }
        } else {
            HStack(spacing: 0) {
                historyList(entries)
                    .frame(width: 292)
                Divider()
                detailPane
            }
            .overlay(alignment: .bottomTrailing) {
                actions
                    .frame(maxWidth: 400, alignment: .trailing)
                    .padding(14)
            }
        }
    }

    private func historyList(_ entries: [HistoryEntry]) -> some View {
        // ⌘1 to ⌘9 paste the first nine rows as shown.
        let shortcuts = Dictionary(entries.prefix(9).enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { first, _ in first })
        let clearable = model.history.count { !$0.isPinned }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                if confirmingClear {
                    Text(String(format: preferences.text(.clearHistoryPrompt), clearable))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.warningText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(preferences.text(.cancel)) {
                        confirmingClear = false
                    }
                    .controlSize(.small)
                    Button(preferences.text(.clear), role: .destructive) {
                        confirmingClear = false
                        model.clearHistory()
                        selectedHistoryID = nil
                    }
                    .controlSize(.small)
                } else {
                    Text(String(format: preferences.text(.historyCount), entries.count))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mutedText)
                    Spacer()
                    Button {
                        confirmingClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(InteractiveIconButtonStyle())
                    .help(preferences.text(.clearHistory))
                    .disabled(clearable == 0)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 38)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(dayGroups(entries)) { group in
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.mutedText)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                            ForEach(group.entries) { entry in
                                historyRow(entry, shortcut: shortcuts[entry.id])
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .onChange(of: selectedHistoryID) {
                    if let selectedHistoryID {
                        proxy.scrollTo(selectedHistoryID)
                    }
                }
            }

            // Below the list rather than over it: scrolling to a selected row only makes it
            // visible within the scroll view, so a floating overlay could cover it.
            keyHints
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
    }

    private func historyRow(_ entry: HistoryEntry, shortcut: Int?) -> some View {
        let isSelected = selectedHistoryID == entry.id
        let isActive = isSelected && focusedPane == .original
        return Button {
            selectedHistoryID = entry.id
            focusedPane = .original
            selectedResultIndex = 0
        } label: {
            HStack(spacing: 10) {
                GlyphBadge(symbol: symbolName(for: entry))
                VStack(alignment: .leading, spacing: 3) {
                    Text(rowTitle(entry))
                        .font(.system(size: 13.5))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if entry.originalContentTruncated == true {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.warningText)
                        }
                        Text(rowSubtitle(entry))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.mutedText)
                }
                Spacer(minLength: 0)
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mutedText)
                }
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mutedText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowBackground(isSelected: isSelected, isActive: isActive))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(preferences.text(entry.isPinned ? .unpin : .pin)) {
                model.setPinned(!entry.isPinned, forEntry: entry.id)
            }
            Button(preferences.text(.delete), role: .destructive) {
                delete(entry)
            }
        }
    }

    /// A light accent tint marks the pane that Return acts on; gray keeps the row found when it doesn't.
    private func rowBackground(isSelected: Bool, isActive: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.18)
        }
        if isSelected {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedHistoryEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    originalSection(entry)
                    if entry.attachment == nil {
                        resultsSection(entry)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                // Room to scroll the last result above the floating actions.
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A new entry starts at its top instead of the previous entry's scroll offset.
            .id(entry.id)
        } else {
            Text(preferences.text(.selectHistoryEntry))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func originalSection(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(preferences.text(.historyOriginal))
                    .font(.system(size: 12, weight: .semibold))
                Text(originalMeta(entry))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    model.setPinned(!entry.isPinned, forEntry: entry.id)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(entry.isPinned ? .unpin : .pin))
                Button {
                    delete(entry)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.deleteHelp))
                Button {
                    copyPayload(originalPayload(entry), entry: entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.copyOriginal))
            }
            .foregroundStyle(Color.mutedText)

            if let attachment = entry.attachment {
                attachmentPreview(attachment)
            } else {
                originalText(entry)
            }

            if entry.originalContentTruncated == true {
                Label(preferences.text(.historyOriginalTruncated), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.warningText)
            }
        }
    }

    private func originalText(_ entry: HistoryEntry) -> some View {
        let text = entry.originalContent ?? entry.originalPreview
        let isShort = text.utf8.count <= 96 && !text.contains(where: \.isNewline)
        // Laying out the whole of a 256 KiB clipboard is slow; the full text stays copyable.
        return Text(String(text.prefix(4000)))
            .font(.system(size: isShort ? 20 : 12.5, design: .monospaced))
            .lineLimit(isShort ? 2 : 14)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachmentPreview(_ attachment: HistoryAttachment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if attachment.fileName != nil || attachment.filePath != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let fileName = attachment.fileName {
                        Text(fileName)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    if let filePath = attachment.filePath {
                        Text(filePath)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.mutedText)
                            .textSelection(.enabled)
                    }
                }
            }
            switch attachment.previewKind {
            case .image:
                if let path = attachment.assetPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // The preview is at most 900 pixels; show the copied file or the kept image.
                            if let full = attachment.filePath ?? attachment.originalAssetPath,
                               let original = NSImage(contentsOfFile: full) {
                                showImage(original, URL(fileURLWithPath: full))
                            } else {
                                showImage(image, URL(fileURLWithPath: path))
                            }
                        }
                        .help(preferences.text(.clickToEnlarge))
                } else {
                    Text(preferences.text(.previewUnavailable))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.mutedText)
                }
            case .text:
                Text(String((attachment.textPreview ?? "").prefix(4000)))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(18)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .none:
                Text(preferences.text(.noPreviewForBinary))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultsSection(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(preferences.text(.historyParsed))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mutedText)
                if !entry.results.isEmpty {
                    Text("\(entry.results.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.mutedText)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
            if entry.results.isEmpty {
                Text(preferences.text(.noParsedResults))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.mutedText)
            } else {
                ForEach(Array(entry.results.enumerated()), id: \.offset) { index, result in
                    resultCard(entry: entry, result: result, index: index)
                }
            }
        }
    }

    private func resultCard(entry: HistoryEntry, result: HistoryResult, index: Int) -> some View {
        let isPrimary = index == 0
        let isFocused = focusedPane == .parsed && selectedResultIndex == index
        let showsFields = model.category(forParser: result.parserName).showsFields
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ParserBadge(name: result.parserName, isPrimary: isPrimary)
                Spacer()
                Button {
                    copyPayload(.text(result.parsed), entry: entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(InteractiveIconButtonStyle())
                .help(preferences.text(.copyResult))
            }
            ResultTextView(text: result.parsed, showsFields: showsFields, headlineSize: isPrimary ? 17 : 13.5)
            if let details = result.details, details != result.parsed {
                Divider()
                Text(preferences.text(.details))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mutedText)
                ResultTextView(text: details, showsFields: showsFields, headlineSize: 13, muted: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isPrimary ? 14 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusedPane = .parsed
            selectedResultIndex = index
        }
    }

    /// Esc needs no hint; the arrows are the part of the keyboard model nothing else shows.
    private var keyHints: some View {
        HStack(spacing: 10) {
            keyHint(["↑", "↓"], preferences.text(.selectHint))
            keyHint(["←", "→"], preferences.text(.switchPaneHint))
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private var actions: some View {
        HStack(spacing: 0) {
            Button {
                handleHistoryKeyAction(.paste)
            } label: {
                HStack(spacing: 8) {
                    Text(pasteLabel)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    KeyCap(key: "↩")
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
                .frame(height: 16)
            Button {
                handleHistoryKeyAction(.copy)
            } label: {
                HStack(spacing: 4) {
                    Text(preferences.text(focusedPane == .original ? .copyOriginal : .copyResult))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.mutedText)
                        .lineLimit(1)
                        .padding(.trailing, 2)
                    KeyCap(key: "⌘")
                    KeyCap(key: "↩")
                }
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .disabled(selectedHistoryEntry == nil)
    }

    private func keyHint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                KeyCap(key: key)
            }
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.mutedText)
                .lineLimit(1)
                .padding(.leading, 2)
        }
        .fixedSize()
    }

    private var pasteLabel: String {
        let isOriginal = focusedPane == .original
        if let name = model.pasteTargetName {
            return String(format: preferences.text(isOriginal ? .pasteOriginalInto : .pasteResultInto), name)
        }
        return preferences.text(isOriginal ? .pasteOriginal : .pasteResult)
    }

    private struct HistoryDayGroup: Identifiable {
        let id: Int
        let day: Date
        let title: String
        var entries: [HistoryEntry]
    }

    /// Pinned entries lead, as `HistoryStore.allRecent` orders them.
    private func dayGroups(_ entries: [HistoryEntry]) -> [HistoryDayGroup] {
        let calendar = Calendar.current
        let pinned = entries.filter(\.isPinned)
        var groups = pinned.isEmpty
            ? []
            : [HistoryDayGroup(id: -1, day: .distantFuture, title: preferences.text(.pinned), entries: pinned)]
        for entry in entries where !entry.isPinned {
            let day = calendar.startOfDay(for: entry.timestamp)
            if groups.last?.day == day {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(HistoryDayGroup(id: groups.count, day: day, title: dayTitle(day), entries: [entry]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return preferences.text(.today)
        }
        if calendar.isDateInYesterday(day) {
            return preferences.text(.yesterday)
        }
        return day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: preferences.locale))
    }

    private func symbolName(for entry: HistoryEntry) -> String {
        if let parserName = entry.results.first?.parserName {
            return model.category(forParser: parserName).symbolName
        }
        switch entry.contentKind ?? .text {
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        case .file:
            return "doc"
        }
    }

    private func rowTitle(_ entry: HistoryEntry) -> String {
        switch entry.contentKind ?? .text {
        case .text:
            return entry.originalPreview.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .image:
            return preferences.text(.kindImage)
        case .file:
            return entry.attachment?.fileName ?? entry.originalPreview
        }
    }

    private func rowSubtitle(_ entry: HistoryEntry) -> String {
        [kindSummary(entry), relativeTime(entry.timestamp)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func kindSummary(_ entry: HistoryEntry) -> String {
        if let first = entry.results.first?.parserName {
            let names = entry.results.map(\.parserName)
            let repeats = names.filter { $0 == first }.count
            let others = Set(names).count - 1
            return first + (repeats > 1 ? " ×\(repeats)" : "") + (others > 0 ? " +\(others)" : "")
        }
        switch entry.contentKind ?? .text {
        case .text:
            return preferences.text(.kindText)
        case .image:
            guard let width = entry.attachment?.imageWidth, let height = entry.attachment?.imageHeight else { return "" }
            return "\(width) × \(height)"
        case .file:
            return entry.attachment?.fileType ?? preferences.text(.kindFile)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        guard Calendar.current.isDate(date, inSameDayAs: now) else {
            return date.formatted(Date.FormatStyle(time: .shortened, locale: preferences.locale))
        }
        if now.timeIntervalSince(date) < 60 {
            return preferences.text(.justNow)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = preferences.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func originalMeta(_ entry: HistoryEntry) -> String {
        var parts: [String] = []
        if let attachment = entry.attachment {
            parts.append(attachment.metadataText(
                imageLabel: entry.contentKind == .image ? preferences.text(.kindImage) : nil,
                fileLabel: preferences.text(.kindFile)
            ))
        } else if entry.originalContentTruncated != true {
            parts.append(String(format: preferences.text(.characterCount), (entry.originalContent ?? entry.originalPreview).count))
        }
        parts.append(timestampText(entry.timestamp))
        return parts.joined(separator: " · ")
    }

    private func timestampText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(Date.FormatStyle(time: .standard, locale: preferences.locale))
        if calendar.isDateInToday(date) {
            return "\(preferences.text(.today)) \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "\(preferences.text(.yesterday)) \(time)"
        }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: preferences.locale))
    }

    private var filteredHistory: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.history }
        return model.history.filter { $0.matchesHistoryQuery(query) }
    }

    private var selectedHistoryEntry: HistoryEntry? {
        guard let selectedHistoryID else { return nil }
        return filteredHistory.first { $0.id == selectedHistoryID }
    }

    private var focusedContentPayload: ClipboardPayload? {
        guard let entry = selectedHistoryEntry else { return nil }
        switch focusedPane {
        case .original:
            return originalPayload(entry)
        case .parsed:
            return parsedOrPreviewPayload(entry)
        }
    }

    private func copyPayload(_ payload: ClipboardPayload, entry: HistoryEntry) {
        model.promoteHistoryEntry(id: entry.id)
        model.copy(payload)
    }

    private func originalPayload(_ entry: HistoryEntry) -> ClipboardPayload {
        if let original = entry.originalContent {
            return .text(original)
        }
        if let filePath = entry.attachment?.filePath {
            return .file(URL(fileURLWithPath: filePath))
        }
        if let image = imagePayload(entry) {
            return image
        }
        return .text(entry.originalPreview)
    }

    /// The image as copied; entries from before it was kept have only the preview.
    private func imagePayload(_ entry: HistoryEntry) -> ClipboardPayload? {
        guard entry.contentKind == .image,
              let path = entry.attachment?.originalAssetPath ?? entry.attachment?.assetPath
        else { return nil }
        return .image(URL(fileURLWithPath: path))
    }

    private func parsedOrPreviewPayload(_ entry: HistoryEntry) -> ClipboardPayload {
        if !entry.results.isEmpty {
            let index = min(max(selectedResultIndex, 0), entry.results.count - 1)
            return .text(entry.results[index].parsed)
        }
        if let textPreview = entry.attachment?.textPreview, !textPreview.isEmpty {
            return .text(textPreview)
        }
        if let filePath = entry.attachment?.filePath {
            return .file(URL(fileURLWithPath: filePath))
        }
        if let image = imagePayload(entry) {
            return image
        }
        return .text(entry.originalPreview)
    }

    /// Keeps the selection in place: the next entry, or the previous one at the end.
    private func delete(_ entry: HistoryEntry) {
        let entries = filteredHistory
        if selectedHistoryID == entry.id, let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let neighbor = index + 1 < entries.count ? index + 1 : index - 1
            selectedHistoryID = entries.indices.contains(neighbor) ? entries[neighbor].id : nil
            selectedResultIndex = 0
        }
        model.deleteHistoryEntry(id: entry.id)
    }

    private func selectFirstHistoryIfNeeded() {
        guard selectedHistoryID == nil else { return }
        selectedHistoryID = filteredHistory.first?.id
    }

    private func reconcileHistorySelection() {
        let entries = filteredHistory
        if let selectedHistoryID, entries.contains(where: { $0.id == selectedHistoryID }) {
            clampSelectedResultIndex()
            return
        }
        selectedHistoryID = entries.first?.id
        selectedResultIndex = 0
    }

    private func handleHistoryKeyAction(_ action: HistoryKeyAction) {
        switch action {
        case .moveUp:
            if focusedPane == .parsed {
                moveParsedSelection(.previous)
            } else {
                moveHistorySelection(.previous)
            }
        case .moveDown:
            if focusedPane == .parsed {
                moveParsedSelection(.next)
            } else {
                moveHistorySelection(.next)
            }
        case .focusOriginal:
            focusedPane = .original
        case .focusParsed:
            focusedPane = .parsed
            clampSelectedResultIndex()
        case .copy:
            if let entry = selectedHistoryEntry, let payload = focusedContentPayload {
                copyPayload(payload, entry: entry)
            }
        case .paste:
            if let entry = selectedHistoryEntry, let payload = focusedContentPayload {
                model.promoteHistoryEntry(id: entry.id)
                paste(payload)
            }
        case .pasteEntry(let index):
            let entries = filteredHistory
            guard entries.indices.contains(index) else { return }
            model.promoteHistoryEntry(id: entries[index].id)
            paste(originalPayload(entries[index]))
        case .delete:
            if let entry = selectedHistoryEntry {
                delete(entry)
            }
        case .close:
            close()
        }
    }

    private func moveHistorySelection(_ direction: HistorySelectionDirection) {
        let entries = filteredHistory
        guard !entries.isEmpty else {
            selectedHistoryID = nil
            return
        }
        guard let selectedHistoryID,
              let currentIndex = entries.firstIndex(where: { $0.id == selectedHistoryID }) else {
            selectedHistoryID = entries.first?.id
            return
        }

        let nextIndex: Int
        switch direction {
        case .previous:
            nextIndex = max(entries.startIndex, currentIndex - 1)
        case .next:
            nextIndex = min(entries.index(before: entries.endIndex), currentIndex + 1)
        }
        self.selectedHistoryID = entries[nextIndex].id
        selectedResultIndex = 0
    }

    private func moveParsedSelection(_ direction: HistorySelectionDirection) {
        guard let entry = selectedHistoryEntry, !entry.results.isEmpty else { return }
        switch direction {
        case .previous:
            selectedResultIndex = max(0, selectedResultIndex - 1)
        case .next:
            selectedResultIndex = min(entry.results.count - 1, selectedResultIndex + 1)
        }
    }

    private func clampSelectedResultIndex() {
        guard let entry = selectedHistoryEntry, !entry.results.isEmpty else {
            selectedResultIndex = 0
            return
        }
        selectedResultIndex = min(max(selectedResultIndex, 0), entry.results.count - 1)
    }
}

struct HistorySearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        focus(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        focus(field)
    }

    private func focus(_ field: NSTextField) {
        DispatchQueue.main.async {
            guard let window = field.window, window.firstResponder !== field.currentEditor() else { return }
            window.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

enum HistorySelectionDirection {
    case previous
    case next
}

enum HistoryFocusPane {
    case original
    case parsed
}

enum HistoryKeyAction {
    case moveUp
    case moveDown
    case focusOriginal
    case focusParsed
    case copy
    case paste
    /// ⌘1 to ⌘9: paste the original of that row, counting from zero.
    case pasteEntry(Int)
    case delete
    case close
}

struct HistoryKeyboardCaptureView: NSViewRepresentable {
    let onAction: (HistoryKeyAction) -> Void

    func makeNSView(context: Context) -> HistoryKeyboardCaptureNSView {
        let view = HistoryKeyboardCaptureNSView()
        view.onAction = onAction
        return view
    }

    func updateNSView(_ view: HistoryKeyboardCaptureNSView, context: Context) {
        view.onAction = onAction
    }
}

final class HistoryKeyboardCaptureNSView: NSView {
    var onAction: ((HistoryKeyAction) -> Void)?
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
        } else {
            installEventMonitor()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window else {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// The digit row by key code, the same keys on every layout.
    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        if command, let digit = Self.digitKeyCodes[event.keyCode] {
            onAction?(.pasteEntry(digit - 1))
            return true
        }
        switch event.keyCode {
        case 36:
            onAction?(command ? .copy : .paste)
        case 51 where command:
            onAction?(.delete)
        case 53:
            onAction?(.close)
        case 123:
            onAction?(.focusOriginal)
        case 124:
            onAction?(.focusParsed)
        case 126:
            onAction?(.moveUp)
        case 125:
            onAction?(.moveDown)
        default:
            return false
        }
        return true
    }
}

private extension HistoryEntry {
    func matchesHistoryQuery(_ query: String) -> Bool {
        var fields = [originalContent ?? originalPreview, originalPreview]
        for result in results {
            fields.append(result.parserName)
            fields.append(result.parsed)
            if let details = result.details {
                fields.append(details)
            }
        }
        if let fileName = attachment?.fileName {
            fields.append(fileName)
        }
        if let filePath = attachment?.filePath {
            fields.append(filePath)
        }
        if let fileType = attachment?.fileType {
            fields.append(fileType)
        }
        if let textPreview = attachment?.textPreview {
            fields.append(textPreview)
        }
        let haystack = fields.joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

private extension HistoryAttachment {
    /// Copied images store the English word "Image" as their type, so the caller passes the label.
    func metadataText(imageLabel: String?, fileLabel: String) -> String {
        var parts: [String] = []
        if let type = imageLabel ?? fileType {
            parts.append(type)
        }
        if let fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        if let imageWidth, let imageHeight {
            parts.append("\(imageWidth) × \(imageHeight)")
        }
        return parts.isEmpty ? fileLabel : parts.joined(separator: " · ")
    }
}
