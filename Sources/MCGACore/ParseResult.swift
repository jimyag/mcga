import Foundation

public struct ParseResult: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let parserName: String
    public let original: String
    public let parsed: String
    public let details: String?

    public init(
        parserName: String,
        original: String,
        parsed: String,
        details: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.parserName = parserName
        self.original = original
        self.parsed = parsed
        self.details = details
    }
}

public protocol ContentParser: Sendable {
    var name: String { get }
    func parse(_ content: String, previousContent: String) -> [ParseResult]
}

public extension ContentParser {
    func parse(_ content: String) -> [ParseResult] {
        parse(content, previousContent: "")
    }
}
