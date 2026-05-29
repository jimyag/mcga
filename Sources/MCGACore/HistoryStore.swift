import Foundation

public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UInt64
    public let timestamp: Date
    public let originalPreview: String
    public let results: [HistoryResult]

    public init(id: UInt64, timestamp: Date, originalPreview: String, results: [HistoryResult]) {
        self.id = id
        self.timestamp = timestamp
        self.originalPreview = originalPreview
        self.results = results
    }
}

public struct HistoryResult: Codable, Equatable, Sendable {
    public let parserName: String
    public let parsed: String

    public init(parserName: String, parsed: String) {
        self.parserName = parserName
        self.parsed = parsed
    }
}

public actor HistoryStore {
    public static let shared = HistoryStore()
    private let maxEntries = 500
    private let previewLength = 200
    private let path: URL

    public init() {
        self.path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/mcga/history-swift.json")
    }

    public func append(original: String, results: [ParseResult]) {
        guard !results.isEmpty else { return }
        var entries = (try? loadAll()) ?? []
        let nextID = (entries.last?.id ?? 0) + 1
        let preview = original.count > previewLength
            ? String(original.prefix(previewLength)) + "..."
            : original
        entries.append(HistoryEntry(
            id: nextID,
            timestamp: Date(),
            originalPreview: preview,
            results: results.map { HistoryResult(parserName: $0.parserName, parsed: $0.parsed) }
        ))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.mcga.encode(entries)
            try data.write(to: path, options: [.atomic])
        } catch {
            // History is best-effort and should never interrupt clipboard parsing.
        }
    }

    public func loadAll() throws -> [HistoryEntry] {
        let data = try Data(contentsOf: path)
        return try JSONDecoder.mcga.decode([HistoryEntry].self, from: data)
    }

    public func recent(_ count: Int) -> [HistoryEntry] {
        ((try? loadAll()) ?? []).suffix(count).reversed()
    }

    public func clear() {
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("[]".utf8).write(to: path, options: [.atomic])
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
