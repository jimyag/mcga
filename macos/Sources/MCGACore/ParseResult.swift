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

/// How a parser's text output reads best: "label：value" facts under an optional headline,
/// or the text as is when any line is not such a fact (formatted code, lists, sections).
public enum ResultTextLayout: Equatable, Sendable {
    case fields(headline: String?, fields: [ResultField])
    case plain(String)

    public init(_ text: String) {
        var headline: String?
        var fields: [ResultField] = []
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for (index, line) in lines.enumerated() {
            if let field = ResultField(line: line) {
                fields.append(field)
            } else if index == 0 {
                headline = line.trimmingCharacters(in: .whitespaces)
            } else {
                self = .plain(text)
                return
            }
        }
        self = fields.isEmpty ? .plain(text) : .fields(headline: headline, fields: fields)
    }
}

public struct ResultField: Equatable, Sendable {
    public let label: String
    public let value: String

    init?(line: String) {
        guard let first = line.first, !first.isWhitespace,
              let separator = ["：", ": "].compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }
        let label = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let value = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label.count <= 16, !value.isEmpty,
              label.rangeOfCharacter(from: CharacterSet(charactersIn: "\"'{}[]<>")) == nil
        else { return nil }
        self.label = label
        self.value = value
    }
}

public protocol ContentParser: Sendable {
    var name: String { get }
    var info: ParserInfo? { get }
    /// Network lookups and external commands. The engine runs them concurrently after the other
    /// parsers, so a slow one never holds back results that are already known.
    var isSlow: Bool { get }
    func parse(_ content: String, previousContent: String) async -> [ParseResult]
}

public extension ContentParser {
    var info: ParserInfo? { nil }
    var isSlow: Bool { false }
}
