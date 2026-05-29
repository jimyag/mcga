import Foundation

public struct ParserEngine: Sendable {
    private let parsers: [any ContentParser]

    public init() {
        self.parsers = [
            UUIDGenerator(),
            TimestampGenerator(),
            TimeGenerator(),
            ObjectIDGenerator(),
            Base64EncodeGenerator(),
            Base64DecodeGenerator(),
            PasswordGenerator(),
            CIDRParser(),
            UUIDParser(),
            ObjectIDParser(),
            HashParser(),
            IPv6Parser(),
            IPParser(),
            TimestampParser(),
            CronParser(),
            JSONParser(),
            JSON5Parser(),
            YAMLParser(),
            Base64Parser(),
            DNSParser(),
        ]
    }

    public var parserNames: [String] {
        parsers.map(\.name)
    }

    public func parse(_ content: String, previousContent: String = "") -> ParseResult? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for parser in parsers {
            if let first = parser.parse(trimmed, previousContent: previousContent).first {
                return first
            }
        }
        return nil
    }

    public func parseAll(_ content: String, previousContent: String = "") -> [ParseResult] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return parsers.flatMap { $0.parse(trimmed, previousContent: previousContent) }
    }
}
