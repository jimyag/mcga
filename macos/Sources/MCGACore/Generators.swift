import Foundation

struct UUIDGenerator: ContentParser {
    let name = "UUID Generator"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.lowercased() == "uuid" else { return [] }
        let uuid = UUIDv7.generate()
        return [ParseResult(parserName: name, original: content, parsed: uuid)]
    }
}

struct TimestampGenerator: ContentParser {
    let name = "Timestamp Generator"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let keyword = content.lowercased()
        guard keyword == "ts" || keyword == "timestamp" else { return [] }
        return [ParseResult(parserName: name, original: content, parsed: "\(Int(Date().timeIntervalSince1970))")]
    }
}

struct TimeGenerator: ContentParser {
    let name = "Time Generator"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.lowercased() == "time" else { return [] }
        return [ParseResult(parserName: name, original: content, parsed: ParserUtilities.isoString(from: Date()))]
    }
}

struct ObjectIDGenerator: ContentParser {
    let name = "ObjectID Generator"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let keyword = content.lowercased()
        guard keyword == "objectid" || keyword == "oid" else { return [] }
        let seconds = UInt32(Date().timeIntervalSince1970)
        var bytes = [UInt8]()
        bytes.append(UInt8((seconds >> 24) & 0xff))
        bytes.append(UInt8((seconds >> 16) & 0xff))
        bytes.append(UInt8((seconds >> 8) & 0xff))
        bytes.append(UInt8(seconds & 0xff))
        bytes.append(contentsOf: ParserUtilities.randomBytes(count: 5))
        bytes.append(contentsOf: ParserUtilities.randomBytes(count: 3))
        return [ParseResult(parserName: name, original: content, parsed: ParserUtilities.hex(bytes))]
    }
}

struct Base64EncodeGenerator: ContentParser {
    let name = "Base64 Encode"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.lowercased() == "b64", !previousContent.isEmpty else { return [] }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: Data(previousContent.utf8).base64EncodedString(),
            details: previousContent
        )]
    }
}

struct Base64DecodeGenerator: ContentParser {
    let name = "Base64 Decode"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.lowercased() == "db64", !previousContent.isEmpty else { return [] }
        guard let (data, variant) = ParserUtilities.dataFromBase64Variants(previousContent),
              let decoded = String(data: data, encoding: .utf8),
              ParserUtilities.isPrintable(decoded)
        else { return [] }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: decoded,
            details: "格式：\(variant)"
        )]
    }
}

struct PasswordGenerator: ContentParser {
    let name = "Password Generator"
    private let pattern = ParserUtilities.regex(#"^pswd(?:\s+(\d{1,3}))?$"#, options: [.caseInsensitive])

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard let match = ParserUtilities.fullMatch(pattern, content) else { return [] }
        let length: Int
        if match.range(at: 1).location != NSNotFound,
           let range = Range(match.range(at: 1), in: content),
           let parsedLength = Int(content[range]) {
            length = min(max(parsedLength, 8), 128)
        } else {
            length = 24
        }

        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*()-_=+")
        let password = String((0..<length).map { _ in alphabet.randomElement()! })
        return [ParseResult(parserName: name, original: content, parsed: password)]
    }
}

enum UUIDv7 {
    static func generate() -> String {
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8((millis >> 40) & 0xff)
        bytes[1] = UInt8((millis >> 32) & 0xff)
        bytes[2] = UInt8((millis >> 24) & 0xff)
        bytes[3] = UInt8((millis >> 16) & 0xff)
        bytes[4] = UInt8((millis >> 8) & 0xff)
        bytes[5] = UInt8(millis & 0xff)
        let random = ParserUtilities.randomBytes(count: 10)
        bytes.replaceSubrange(6..<16, with: random)
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = ParserUtilities.hex(bytes)
        return [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            String(hex.dropFirst(12).prefix(4)),
            String(hex.dropFirst(16).prefix(4)),
            String(hex.dropFirst(20)),
        ].joined(separator: "-")
    }
}
