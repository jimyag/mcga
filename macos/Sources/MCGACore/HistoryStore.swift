import Foundation

public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UInt64
    public let timestamp: Date
    public let contentKind: HistoryContentKind?
    public let originalContent: String?
    public let originalPreview: String
    public let results: [HistoryResult]
    public let attachment: HistoryAttachment?

    public init(
        id: UInt64,
        timestamp: Date,
        contentKind: HistoryContentKind? = .text,
        originalContent: String? = nil,
        originalPreview: String,
        results: [HistoryResult],
        attachment: HistoryAttachment? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentKind = contentKind
        self.originalContent = originalContent
        self.originalPreview = originalPreview
        self.results = results
        self.attachment = attachment
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
    public let assetPath: String?
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
}

public actor HistoryStore {
    public static let shared = HistoryStore()
    private let maxEntries = 500
    private let previewLength = 200
    private let path: URL
    private let assetsDirectory: URL

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

    public func append(original: String, results: [ParseResult], retentionDays: Int = 0) {
        var entries = (try? loadAll()) ?? []
        _ = repairDuplicateIDs(&entries)
        let nextID = nextHistoryID(after: entries)
        let preview = original.count > previewLength
            ? String(original.prefix(previewLength)) + "..."
            : original
        entries.append(HistoryEntry(
            id: nextID,
            timestamp: Date(),
            contentKind: .text,
            originalContent: original,
            originalPreview: preview,
            results: results.map { HistoryResult(parserName: $0.parserName, parsed: $0.parsed, details: $0.details) },
            attachment: nil
        ))
        save(entries, retentionDays: retentionDays)
    }

    public func append(kind: HistoryContentKind, originalPreview: String, attachment: HistoryAttachment, retentionDays: Int = 0) {
        var entries = (try? loadAll()) ?? []
        _ = repairDuplicateIDs(&entries)
        let nextID = nextHistoryID(after: entries)
        entries.append(HistoryEntry(
            id: nextID,
            timestamp: Date(),
            contentKind: kind,
            originalContent: nil,
            originalPreview: originalPreview,
            results: [],
            attachment: attachment
        ))
        save(entries, retentionDays: retentionDays)
    }

    public func promote(id: UInt64, retentionDays: Int = 0) {
        var entries = (try? loadAll()) ?? []
        let repairedDuplicates = repairDuplicateIDs(&entries)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entries.append(HistoryEntry(
            id: entry.id,
            timestamp: Date(),
            contentKind: entry.contentKind,
            originalContent: entry.originalContent,
            originalPreview: entry.originalPreview,
            results: entry.results,
            attachment: entry.attachment
        ))
        save(entries, retentionDays: repairedDuplicates ? 0 : retentionDays)
    }

    public func loadAll() throws -> [HistoryEntry] {
        let data = try Data(contentsOf: path)
        return try JSONDecoder.mcga.decode([HistoryEntry].self, from: data)
    }

    public func recent(_ count: Int, retentionDays: Int = 0) -> [HistoryEntry] {
        allEntries(retentionDays: retentionDays).suffix(count).reversed()
    }

    public func allRecent(retentionDays: Int = 0) -> [HistoryEntry] {
        allEntries(retentionDays: retentionDays).reversed()
    }

    public func clear() {
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("[]".utf8).write(to: path, options: [.atomic])
        try? FileManager.default.removeItem(at: assetsDirectory)
    }

    private func allEntries(retentionDays: Int) -> [HistoryEntry] {
        var entries = (try? loadAll()) ?? []
        let originalCount = entries.count
        let repairedDuplicates = repairDuplicateIDs(&entries)
        entries = pruned(entries, retentionDays: retentionDays)
        if repairedDuplicates || entries.count != originalCount {
            save(entries, retentionDays: 0)
        }
        return entries
    }

    private func nextHistoryID(after entries: [HistoryEntry]) -> UInt64 {
        (entries.map(\.id).max() ?? 0) + 1
    }

    private func repairDuplicateIDs(_ entries: inout [HistoryEntry]) -> Bool {
        var seen = Set<UInt64>()
        var nextID = nextHistoryID(after: entries)
        var changed = false
        for index in entries.indices {
            let entry = entries[index]
            if seen.insert(entry.id).inserted {
                continue
            }
            entries[index] = HistoryEntry(
                id: nextID,
                timestamp: entry.timestamp,
                contentKind: entry.contentKind,
                originalContent: entry.originalContent,
                originalPreview: entry.originalPreview,
                results: entry.results,
                attachment: entry.attachment
            )
            seen.insert(nextID)
            nextID += 1
            changed = true
        }
        return changed
    }

    private func save(_ entries: [HistoryEntry], retentionDays: Int) {
        var entries = pruned(entries, retentionDays: retentionDays)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.mcga.encode(entries)
            try data.write(to: path, options: [.atomic])
            removeOrphanedAssets(referencedBy: entries)
        } catch {
            // History is best-effort and should never interrupt clipboard parsing.
        }
    }

    private func pruned(_ entries: [HistoryEntry], retentionDays: Int) -> [HistoryEntry] {
        guard retentionDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else {
            return entries
        }
        return entries.filter { $0.timestamp >= cutoff }
    }

    private func removeOrphanedAssets(referencedBy entries: [HistoryEntry]) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        let referenced = Set(entries.compactMap { $0.attachment?.assetPath }.map { URL(fileURLWithPath: $0).lastPathComponent })
        for file in files where !referenced.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
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
