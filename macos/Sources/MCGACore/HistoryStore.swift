import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public internal(set) var id: UInt64
    public internal(set) var timestamp: Date
    public let contentKind: HistoryContentKind?
    public let originalContent: String?
    public let originalContentTruncated: Bool?
    public let originalPreview: String
    public internal(set) var results: [HistoryResult]
    public let attachment: HistoryAttachment?
    /// Pinned entries come first and outlive the retention period and the entry limit.
    public internal(set) var pinned: Bool?

    public var isPinned: Bool {
        pinned == true
    }

    public init(
        id: UInt64,
        timestamp: Date,
        contentKind: HistoryContentKind? = .text,
        originalContent: String? = nil,
        originalContentTruncated: Bool = false,
        originalPreview: String,
        results: [HistoryResult],
        attachment: HistoryAttachment? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentKind = contentKind
        self.originalContent = originalContent
        self.originalContentTruncated = originalContentTruncated
        self.originalPreview = originalPreview
        self.results = results
        self.attachment = attachment
        self.pinned = pinned ? true : nil
    }
}

public enum HistoryContentKind: String, Codable, Equatable, Sendable {
    case text
    case image
    case file
}

public enum HistoryPreviewKind: String, Codable, Equatable, Sendable {
    case none
    case text
    case image
}

public struct HistoryAttachment: Codable, Equatable, Sendable {
    public let previewKind: HistoryPreviewKind
    /// The preview image.
    public let assetPath: String?
    /// A copied image as it was copied, so copying it back loses nothing. Files keep their own path.
    public let originalAssetPath: String?
    public let filePath: String?
    public let fileName: String?
    public let fileType: String?
    public let fileSize: Int64?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let textPreview: String?

    public init(
        previewKind: HistoryPreviewKind,
        assetPath: String? = nil,
        originalAssetPath: String? = nil,
        filePath: String? = nil,
        fileName: String? = nil,
        fileType: String? = nil,
        fileSize: Int64? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        textPreview: String? = nil
    ) {
        self.previewKind = previewKind
        self.assetPath = assetPath
        self.originalAssetPath = originalAssetPath
        self.filePath = filePath
        self.fileName = fileName
        self.fileType = fileType
        self.fileSize = fileSize
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.textPreview = textPreview
    }
}

public struct HistoryResult: Codable, Equatable, Sendable {
    public let parserName: String
    public let parsed: String
    public let details: String?

    public init(parserName: String, parsed: String, details: String? = nil) {
        self.parserName = parserName
        self.parsed = parsed
        self.details = details
    }

    init(_ result: ParseResult) {
        self.init(parserName: result.parserName, parsed: result.parsed, details: result.details)
    }
}

public actor HistoryStore {
    public static let shared = HistoryStore()
    private let maxEntries = 500
    private let previewLength = 200
    private let maximumOriginalBytes = ParserEngine.maximumInputBytes
    private let path: URL
    /// Image previews and copied images.
    public nonisolated let assetsDirectory: URL

    public init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/mcga")
        self.init(
            path: directory.appendingPathComponent("history-swift.json"),
            assetsDirectory: directory.appendingPathComponent("history-assets")
        )
    }

    public init(path: URL, assetsDirectory: URL) {
        self.path = path
        self.assetsDirectory = assetsDirectory
    }

    /// Returns the entry's id. Copying the same text again moves its entry up and replaces its
    /// results instead of adding a duplicate.
    @discardableResult
    public func append(original: String, results: [ParseResult], retentionDays: Int = 0) -> UInt64 {
        var entries = (try? loadAll()) ?? []
        _ = repairDuplicateIDs(&entries)
        let originalContentTruncated = original.utf8.count > maximumOriginalBytes
        if !originalContentTruncated,
           let index = entries.firstIndex(where: { ($0.contentKind ?? .text) == .text && $0.originalContent == original }) {
            var entry = entries.remove(at: index)
            entry.timestamp = Date()
            entry.results = results.map(HistoryResult.init)
            entries.append(entry)
            save(entries, retentionDays: retentionDays)
            return entry.id
        }
        let id = nextHistoryID(after: entries)
        let preview = original.count > previewLength
            ? String(original.prefix(previewLength)) + "..."
            : original
        entries.append(HistoryEntry(
            id: id,
            timestamp: Date(),
            contentKind: .text,
            originalContent: originalContentTruncated ? nil : original,
            originalContentTruncated: originalContentTruncated,
            originalPreview: preview,
            results: results.map(HistoryResult.init),
            attachment: nil
        ))
        save(entries, retentionDays: retentionDays)
        return id
    }

    public func append(kind: HistoryContentKind, originalPreview: String, attachment: HistoryAttachment, retentionDays: Int = 0) {
        var entries = (try? loadAll()) ?? []
        _ = repairDuplicateIDs(&entries)
        // Snipaste and other Qt apps rewrite an unchanged clipboard image, which is not a new copy.
        if let latest = entries.last, latest.contentKind == kind, hasSameAsset(latest.attachment, attachment) {
            removeFiles(of: [attachment])
            return
        }
        entries.append(HistoryEntry(
            id: nextHistoryID(after: entries),
            timestamp: Date(),
            contentKind: kind,
            originalContent: nil,
            originalPreview: originalPreview,
            results: [],
            attachment: attachment
        ))
        save(entries, retentionDays: retentionDays)
    }

    /// Slow parsers report after the entry is recorded.
    public func setResults(id: UInt64, results: [ParseResult]) {
        var entries = (try? loadAll()) ?? []
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].results = results.map(HistoryResult.init)
        save(entries, retentionDays: 0)
    }

    public func promote(id: UInt64, retentionDays: Int = 0) {
        var entries = (try? loadAll()) ?? []
        let repairedDuplicates = repairDuplicateIDs(&entries)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.timestamp = Date()
        entries.append(entry)
        save(entries, retentionDays: repairedDuplicates ? 0 : retentionDays)
    }

    public func setPinned(id: UInt64, _ pinned: Bool) {
        var entries = (try? loadAll()) ?? []
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned = pinned ? true : nil
        save(entries, retentionDays: 0)
    }

    public func delete(id: UInt64) {
        let entries = (try? loadAll()) ?? []
        save(entries.filter { $0.id != id }, retentionDays: 0)
        removeFiles(of: entries.filter { $0.id == id }.map(\.attachment))
    }

    public func loadAll() throws -> [HistoryEntry] {
        let data = try Data(contentsOf: path)
        return try JSONDecoder.mcga.decode([HistoryEntry].self, from: data)
    }

    public func recent(_ count: Int, retentionDays: Int = 0) -> [HistoryEntry] {
        allEntries(retentionDays: retentionDays).suffix(count).reversed()
    }

    /// Pinned entries first, then the rest; each group newest first.
    public func allRecent(retentionDays: Int = 0) -> [HistoryEntry] {
        let newestFirst = allEntries(retentionDays: retentionDays).reversed()
        return newestFirst.filter(\.isPinned) + newestFirst.filter { !$0.isPinned }
    }

    /// Pinned entries stay. Also sweeps files that no entry refers to.
    public func clear() {
        let pinned = ((try? loadAll()) ?? []).filter(\.isPinned)
        save(pinned, retentionDays: 0)
        let referenced = Set(pinned.flatMap { assetPaths(of: $0.attachment) }.map { URL(fileURLWithPath: $0).lastPathComponent })
        for file in (try? FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil)) ?? []
        where !referenced.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func allEntries(retentionDays: Int) -> [HistoryEntry] {
        var entries = (try? loadAll()) ?? []
        let repairedDuplicates = repairDuplicateIDs(&entries)
        let kept = pruned(entries, retentionDays: retentionDays)
        if repairedDuplicates || kept.count != entries.count {
            save(entries, retentionDays: retentionDays)
        }
        return kept
    }

    private func hasSameAsset(_ stored: HistoryAttachment?, _ new: HistoryAttachment) -> Bool {
        guard let stored, stored.filePath == new.filePath,
              let storedPath = stored.assetPath, let newPath = new.assetPath,
              let storedData = FileManager.default.contents(atPath: storedPath),
              let newData = FileManager.default.contents(atPath: newPath)
        else { return false }
        return storedData == newData
    }

    private func nextHistoryID(after entries: [HistoryEntry]) -> UInt64 {
        (entries.map(\.id).max() ?? 0) + 1
    }

    private func repairDuplicateIDs(_ entries: inout [HistoryEntry]) -> Bool {
        var seen = Set<UInt64>()
        var nextID = nextHistoryID(after: entries)
        var changed = false
        for index in entries.indices where !seen.insert(entries[index].id).inserted {
            entries[index].id = nextID
            seen.insert(nextID)
            nextID += 1
            changed = true
        }
        return changed
    }

    private func save(_ entries: [HistoryEntry], retentionDays: Int) {
        var kept = pruned(entries, retentionDays: retentionDays)
        // Pinned entries do not count toward the limit; the oldest unpinned ones go first.
        let excess = kept.count { !$0.isPinned } - maxEntries
        if excess > 0 {
            let dropped = Set(kept.lazy.filter { !$0.isPinned }.prefix(excess).map(\.id))
            kept.removeAll { dropped.contains($0.id) }
        }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.mcga.encode(kept)
            try data.write(to: path, options: [.atomic])
            let keptIDs = Set(kept.map(\.id))
            removeFiles(of: entries.filter { !keptIDs.contains($0.id) }.map(\.attachment))
        } catch {
            // History is best-effort and should never interrupt clipboard parsing.
        }
    }

    private func pruned(_ entries: [HistoryEntry], retentionDays: Int) -> [HistoryEntry] {
        guard retentionDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else {
            return entries
        }
        return entries.filter { $0.isPinned || $0.timestamp >= cutoff }
    }

    /// Removes only the files of entries leaving the history. A new image's files are written
    /// before its entry is added, so sweeping every unreferenced file here could take them.
    private func removeFiles(of attachments: [HistoryAttachment?]) {
        for path in attachments.flatMap(assetPaths(of:)) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func assetPaths(of attachment: HistoryAttachment?) -> [String] {
        [attachment?.assetPath, attachment?.originalAssetPath].compactMap { $0 }
    }
}

/// Image files for history: a preview for the list, and a copied image kept as it was copied.
public enum HistoryImage {
    public struct Saved: Sendable {
        public let previewPath: String
        /// Nil for image files, which stay where they are.
        public let originalPath: String?
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    private static let previewMaxPixels = 900

    /// Keeps PNG, JPEG, HEIC and GIF data as copied and stores other formats, mostly TIFF, as PNG.
    public static func save(_ data: Data, in directory: URL) -> Saved? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let size = pixelSize(of: source) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString
        let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let original: URL
        if let type, let fileExtension = type.preferredFilenameExtension,
           [UTType.png, .jpeg, .heic, .gif].contains(where: type.conforms(to:)) {
            original = directory.appendingPathComponent("\(name)-original.\(fileExtension)")
            guard (try? data.write(to: original)) != nil else { return nil }
        } else {
            original = directory.appendingPathComponent("\(name)-original.png")
            guard writePNG(from: source, to: original) else { return nil }
        }
        let preview = directory.appendingPathComponent("\(name).png")
        guard writePreview(of: source, to: preview) else { return nil }
        return Saved(previewPath: preview.path, originalPath: original.path, pixelWidth: size.width, pixelHeight: size.height)
    }

    /// A preview of an image file, without decoding it at full size.
    public static func preview(ofFile url: URL, in directory: URL) -> Saved? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let size = pixelSize(of: source) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preview = directory.appendingPathComponent("\(UUID().uuidString).png")
        guard writePreview(of: source, to: preview) else { return nil }
        return Saved(previewPath: preview.path, originalPath: nil, pixelWidth: size.width, pixelHeight: size.height)
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // Orientations 5 to 8 turn the image a quarter.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }

    /// Carries the metadata over, so the resolution, and with it the size the image pastes at, stays.
    private static func writePNG(from source: CGImageSource, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func writePreview(of source: CGImageSource, to url: URL) -> Bool {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaxPixels,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        return CGImageDestinationFinalize(destination)
    }
}

private extension JSONEncoder {
    static var mcga: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var mcga: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
