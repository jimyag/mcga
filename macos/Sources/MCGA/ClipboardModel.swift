import AppKit
import MCGACore
import UniformTypeIdentifiers

@MainActor
final class ClipboardModel: ObservableObject {
    @Published var isPaused = false
    @Published var history: [HistoryEntry] = []
    @Published var copyNotice: String?
    /// The app that pasting from history returns to.
    @Published var pasteTargetName: String?
    /// Version a background update check found, shown as a gentle reminder until the user acts on it.
    @Published var availableUpdateVersion: String?
    /// Rebuilt when the language or the custom parser config changes.
    @Published private(set) var engine: ParserEngine
    /// Results of the latest copy as they arrive: local parsers first, slow ones later. The id
    /// changes with every copy.
    var onResults: ((UInt64, String, [ParseResult]) -> Void)?

    private let preferences: AppPreferences
    private let pasteboard: NSPasteboard
    private let historyStore: HistoryStore
    private var customParserConfigDate: Date?
    private var timer: Timer?
    private var lastChangeCount: Int
    /// The clipboard text now, whether copied elsewhere or by MCGA; copying it again is not a new copy.
    private var currentContent = ""
    /// The text before the current copy, for the b64 and db64 keywords.
    private var previousContent = ""
    private var parseGeneration: UInt64 = 0
    private nonisolated static let filePreviewLimit = 256 * 1024

    var parserInfos: [ParserInfo] {
        engine.parserInfos
    }

    var customParserIssues: [String] {
        engine.customParserIssues
    }

    func category(forParser name: String) -> ParserCategory {
        engine.parserCategories[name] ?? .text
    }

    init(
        preferences: AppPreferences,
        pasteboard: NSPasteboard = .general,
        historyStore: HistoryStore = .shared,
        engine: ParserEngine? = nil
    ) {
        self.preferences = preferences
        self.pasteboard = pasteboard
        self.historyStore = historyStore
        self.lastChangeCount = pasteboard.changeCount
        self.customParserConfigDate = Self.customParserConfigDate()
        self.engine = engine ?? ParserEngine(language: preferences.language.parserLanguage)
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
            await historyStore.clear()
            refreshHistory()
        }
    }

    func refreshHistory() {
        Task {
            let entries = await historyStore.allRecent(retentionDays: preferences.historyRetentionDays)
            await MainActor.run {
                self.history = entries
            }
        }
    }

    func promoteHistoryEntry(id: UInt64) {
        Task {
            await historyStore.promote(id: id, retentionDays: preferences.historyRetentionDays)
            refreshHistory()
        }
    }

    func deleteHistoryEntry(id: UInt64) {
        Task {
            await historyStore.delete(id: id)
            refreshHistory()
        }
    }

    func setPinned(_ pinned: Bool, forEntry id: UInt64) {
        Task {
            await historyStore.setPinned(id: id, pinned)
            refreshHistory()
        }
    }

    /// Picks up a language change or an edit to the custom parser config.
    func reloadParsers() {
        customParserConfigDate = Self.customParserConfigDate()
        engine = ParserEngine(language: preferences.language.parserLanguage)
    }

    func reloadParsersIfConfigChanged() {
        if Self.customParserConfigDate() != customParserConfigDate {
            reloadParsers()
        }
    }

    private static func customParserConfigDate() -> Date? {
        try? ParserEngine.customParserConfigURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func copy(_ value: String) {
        copy(.text(value))
    }

    /// Text taken out of the overlay is a new copy: parse it, record it, and show its results.
    func copyAndRecord(_ value: String) {
        if !isPaused, value != currentContent {
            parse(value)
        }
        copy(value)
    }

    func copy(_ payload: ClipboardPayload) {
        pasteboard.clearContents()
        switch payload {
        case .text(let value):
            pasteboard.setString(value, forType: .string)
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setString(url.path, forType: .string)
            }
        }
        lastChangeCount = pasteboard.changeCount
        // Skip the polling echo of this write; overlay copies already started their parse.
        // History copies still become the previous value for the b64 and db64 keywords.
        if case .text(let value) = payload {
            currentContent = value
            previousContent = value
        } else {
            currentContent = ""
        }
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
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let fileURLs = pasteboardFileURLs(pasteboard)
        if !fileURLs.isEmpty {
            appendFileHistory(fileURLs)
            return
        }

        let text = pasteboard.string(forType: .string).flatMap { $0.isEmpty ? nil : $0 }
        if prefersImage(over: text, in: pasteboard), let image = pasteboardImageData(pasteboard) {
            appendImageHistory(image)
            return
        }

        guard let text, text != currentContent else { return }
        parse(text)
    }

    private func parse(_ content: String) {
        parseGeneration &+= 1
        let generation = parseGeneration
        let previous = previousContent
        previousContent = content
        currentContent = content
        reloadParsersIfConfigChanged()
        let updates = engine.results(
            for: content,
            previousContent: previous,
            enabledParserNames: preferences.enabledParserNames(from: engine.parserNames)
        )
        let retentionDays = preferences.historyRetentionDays
        Task {
            var historyID: UInt64?
            for await results in updates {
                if generation == parseGeneration, !results.isEmpty {
                    onResults?(generation, content, results)
                }
                if let historyID {
                    await historyStore.setResults(id: historyID, results: results)
                } else {
                    historyID = await historyStore.append(original: content, results: results, retentionDays: retentionDays)
                }
                refreshHistory()
            }
        }
    }

    /// Office and iWork put a picture of copied cells or text next to the text, so text wins.
    /// A browser's copied image comes with its address, so a lone link the source lists after
    /// the image does not.
    private func prefersImage(over text: String?, in pasteboard: NSPasteboard) -> Bool {
        guard let text else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let scheme = URL(string: trimmed)?.scheme?.lowercased(),
              ["http", "https", "file", "data", "blob"].contains(scheme)
        else { return false }
        for type in pasteboard.pasteboardItems?.first?.types ?? [] {
            guard let uti = UTType(type.rawValue) else { continue }
            if uti.conforms(to: .plainText) { return false }
            if uti.conforms(to: .image) { return true }
        }
        return false
    }

    /// The image as the source app wrote it; formats only NSImage reads, such as PDF, as TIFF.
    private func pasteboardImageData(_ pasteboard: NSPasteboard) -> Data? {
        let types: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier),
            .tiff,
        ]
        if let type = pasteboard.availableType(from: types), let data = pasteboard.data(forType: type) {
            return data
        }
        return NSImage(pasteboard: pasteboard)?.tiffRepresentation
    }

    private func pasteboardFileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    /// Decoding and encoding a large image takes a noticeable fraction of a second, so it runs
    /// off the main thread.
    private func appendImageHistory(_ data: Data) {
        parseGeneration &+= 1
        currentContent = ""
        let historyStore = historyStore
        let directory = historyStore.assetsDirectory
        let retentionDays = preferences.historyRetentionDays
        Task.detached(priority: .utility) { [weak self] in
            guard let image = HistoryImage.save(data, in: directory) else { return }
            await historyStore.append(
                kind: .image,
                originalPreview: "Image \(image.pixelWidth) x \(image.pixelHeight)",
                attachment: HistoryAttachment(
                    previewKind: .image,
                    assetPath: image.previewPath,
                    originalAssetPath: image.originalPath,
                    fileType: "Image",
                    imageWidth: image.pixelWidth,
                    imageHeight: image.pixelHeight
                ),
                retentionDays: retentionDays
            )
            await self?.refreshHistory()
        }
    }

    private func appendFileHistory(_ urls: [URL]) {
        parseGeneration &+= 1
        currentContent = ""
        let historyStore = historyStore
        let directory = historyStore.assetsDirectory
        let retentionDays = preferences.historyRetentionDays
        Task.detached(priority: .utility) { [weak self] in
            for url in urls {
                await historyStore.append(
                    kind: .file,
                    originalPreview: "\(url.lastPathComponent)\n\(url.path)",
                    attachment: Self.fileAttachment(url, previewsIn: directory),
                    retentionDays: retentionDays
                )
            }
            await self?.refreshHistory()
        }
    }

    private nonisolated static func fileAttachment(_ url: URL, previewsIn directory: URL) -> HistoryAttachment {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let fileSize = Int64(values?.fileSize ?? 0)
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let typeName = type?.localizedDescription ?? type?.identifier ?? url.pathExtension
        let fileName = url.lastPathComponent

        if let type, type.conforms(to: .image), let image = HistoryImage.preview(ofFile: url, in: directory) {
            return HistoryAttachment(
                previewKind: .image,
                assetPath: image.previewPath,
                filePath: url.path,
                fileName: fileName,
                fileType: typeName,
                fileSize: fileSize,
                imageWidth: image.pixelWidth,
                imageHeight: image.pixelHeight
            )
        }
        if isTextPreviewable(type: type), let textPreview = readTextPreview(url) {
            return HistoryAttachment(
                previewKind: .text,
                filePath: url.path,
                fileName: fileName,
                fileType: typeName,
                fileSize: fileSize,
                textPreview: textPreview
            )
        }
        return HistoryAttachment(previewKind: .none, filePath: url.path, fileName: fileName, fileType: typeName, fileSize: fileSize)
    }

    private nonisolated static func isTextPreviewable(type: UTType?) -> Bool {
        guard let type else { return false }
        return type.conforms(to: .text)
            || type.conforms(to: .json)
            || type.conforms(to: .xml)
            || type.identifier == "public.yaml"
            || type.identifier == "net.daringfireball.markdown"
    }

    private nonisolated static func readTextPreview(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: filePreviewLimit), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
