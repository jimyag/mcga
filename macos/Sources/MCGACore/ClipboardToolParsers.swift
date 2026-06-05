import Foundation

struct URLParser: ContentParser {
    let name = "URL"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.count <= 8_192,
              content.contains("://"),
              let components = URLComponents(string: content),
              let scheme = components.scheme,
              let host = components.host
        else { return [] }

        var lines = [
            "Scheme: \(scheme)",
            "Host: \(host)",
        ]
        if let port = components.port {
            lines.append("Port: \(port)")
        }
        if !components.path.isEmpty {
            lines.append("Path: \(components.path)")
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            lines.append("Fragment: \(fragment)")
        }

        let queryItems = components.queryItems ?? []
        if !queryItems.isEmpty {
            lines.append("")
            lines.append("Query:")
            for item in queryItems {
                lines.append("  \(item.name) = \(item.value ?? "")")
            }
        }

        let decoded = content.removingPercentEncoding ?? content
        let details = decoded == content ? lines.joined(separator: "\n") : "\(lines.joined(separator: "\n"))\n\nDecoded:\n\(decoded)"
        return [ParseResult(parserName: name, original: content, parsed: lines.joined(separator: "\n"), details: details)]
    }
}

struct HTMLEntityParser: ContentParser {
    let name = "HTML Entity"
    private let pattern = ParserUtilities.regex(#"&(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard ParserUtilities.fullMatch(pattern, content) != nil || pattern.firstMatch(in: content, range: NSRange(content.startIndex..<content.endIndex, in: content)) != nil else {
            return []
        }
        let decoded = decode(content)
        guard decoded != content else { return [] }
        return [ParseResult(parserName: name, original: content, parsed: decoded, details: "原始长度：\(content.count)\n解码长度：\(decoded.count)")]
    }

    private func decode(_ value: String) -> String {
        let entities: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "nbsp": "\u{00a0}", "copy": "©", "reg": "®", "trade": "™",
            "hellip": "…", "mdash": "—", "ndash": "–",
        ]
        var output = ""
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "&", let semicolon = value[index...].firstIndex(of: ";") else {
                output.append(value[index])
                index = value.index(after: index)
                continue
            }
            let body = String(value[value.index(after: index)..<semicolon])
            if let named = entities[body] {
                output.append(named)
            } else if body.hasPrefix("#x"), let scalar = UInt32(body.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init) {
                output.append(Character(scalar))
            } else if body.hasPrefix("#"), let scalar = UInt32(body.dropFirst(), radix: 10).flatMap(UnicodeScalar.init) {
                output.append(Character(scalar))
            } else {
                output.append(String(value[index...semicolon]))
            }
            index = value.index(after: semicolon)
        }
        return output
    }
}

struct UnicodeEscapeParser: ContentParser {
    let name = "Unicode Escape"
    private let pattern = ParserUtilities.regex(#"\\u(?:\{[0-9a-fA-F]{1,6}\}|[0-9a-fA-F]{4})"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.count <= 64 * 1024,
              pattern.firstMatch(in: content, range: NSRange(content.startIndex..<content.endIndex, in: content)) != nil else {
            return []
        }
        let decoded = decode(content)
        guard decoded != content else { return [] }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: decoded,
            details: "原始长度：\(content.count)\n解码长度：\(decoded.count)"
        )]
    }

    private func decode(_ value: String) -> String {
        var output = ""
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "\\",
                  let next = value.index(index, offsetBy: 1, limitedBy: value.index(before: value.endIndex)),
                  value[next] == "u" else {
                output.append(value[index])
                index = value.index(after: index)
                continue
            }

            if let parsed = parseBracedScalar(in: value, slashIndex: index) {
                output.append(parsed.character)
                index = parsed.nextIndex
                continue
            }

            if let parsed = parseFourDigitScalar(in: value, slashIndex: index) {
                output.append(parsed.character)
                index = parsed.nextIndex
                continue
            }

            output.append(value[index])
            index = value.index(after: index)
        }
        return output
    }

    private func parseBracedScalar(in value: String, slashIndex: String.Index) -> (character: Character, nextIndex: String.Index)? {
        let braceIndex = value.index(slashIndex, offsetBy: 2, limitedBy: value.endIndex)
        guard let braceIndex, braceIndex < value.endIndex, value[braceIndex] == "{" else { return nil }
        guard let closeIndex = value[braceIndex...].firstIndex(of: "}") else { return nil }
        let bodyStart = value.index(after: braceIndex)
        guard bodyStart < closeIndex else { return nil }
        let body = value[bodyStart..<closeIndex]
        guard body.count <= 6,
              body.allSatisfy(\.isHexDigit),
              let codePoint = UInt32(body, radix: 16),
              let scalar = UnicodeScalar(codePoint) else {
            return nil
        }
        return (Character(scalar), value.index(after: closeIndex))
    }

    private func parseFourDigitScalar(in value: String, slashIndex: String.Index) -> (character: Character, nextIndex: String.Index)? {
        guard let firstDigit = value.index(slashIndex, offsetBy: 2, limitedBy: value.endIndex),
              let end = value.index(firstDigit, offsetBy: 4, limitedBy: value.endIndex) else {
            return nil
        }
        let digits = value[firstDigit..<end]
        guard digits.count == 4, digits.allSatisfy(\.isHexDigit), let firstCodeUnit = UInt16(digits, radix: 16) else {
            return nil
        }

        if (0xD800...0xDBFF).contains(firstCodeUnit),
           let low = parseLowSurrogate(in: value, after: end),
           let scalar = scalarFromSurrogates(high: firstCodeUnit, low: low.codeUnit) {
            return (Character(scalar), low.nextIndex)
        }

        guard !(0xDC00...0xDFFF).contains(firstCodeUnit),
              let scalar = UnicodeScalar(UInt32(firstCodeUnit)) else {
            return nil
        }
        return (Character(scalar), end)
    }

    private func parseLowSurrogate(in value: String, after index: String.Index) -> (codeUnit: UInt16, nextIndex: String.Index)? {
        guard index < value.endIndex,
              value[index] == "\\",
              let uIndex = value.index(index, offsetBy: 1, limitedBy: value.index(before: value.endIndex)),
              value[uIndex] == "u",
              let firstDigit = value.index(index, offsetBy: 2, limitedBy: value.endIndex),
              let end = value.index(firstDigit, offsetBy: 4, limitedBy: value.endIndex) else {
            return nil
        }
        let digits = value[firstDigit..<end]
        guard digits.count == 4,
              digits.allSatisfy(\.isHexDigit),
              let codeUnit = UInt16(digits, radix: 16),
              (0xDC00...0xDFFF).contains(codeUnit) else {
            return nil
        }
        return (codeUnit, end)
    }

    private func scalarFromSurrogates(high: UInt16, low: UInt16) -> UnicodeScalar? {
        let value = 0x10000 + ((UInt32(high) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
        return UnicodeScalar(value)
    }
}

struct HTTPStatusParser: ContentParser {
    let name = "HTTP Status"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.count == 3, let code = Int(content), let phrase = phrases[code] else { return [] }
        let klass = switch code {
        case 100..<200: "信息响应"
        case 200..<300: "成功"
        case 300..<400: "重定向"
        case 400..<500: "客户端错误"
        case 500..<600: "服务端错误"
        default: "未知"
        }
        return [ParseResult(parserName: name, original: content, parsed: "\(code) \(phrase)\n类型：\(klass)")]
    }

    private let phrases: [Int: String] = [
        100: "Continue", 101: "Switching Protocols", 102: "Processing", 103: "Early Hints",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used",
        300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 305: "Use Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 418: "I'm a teapot", 421: "Misdirected Request", 422: "Unprocessable Content", 423: "Locked", 424: "Failed Dependency", 425: "Too Early", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected", 510: "Not Extended", 511: "Network Authentication Required",
    ]
}

struct NumberBaseParser: ContentParser {
    let name = "Number Base"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let lower = content.lowercased()
        let parsed: UInt64?
        let sourceBase: Int
        if lower.hasPrefix("0x") {
            parsed = UInt64(lower.dropFirst(2), radix: 16)
            sourceBase = 16
        } else if lower.hasPrefix("0b") {
            parsed = UInt64(lower.dropFirst(2), radix: 2)
            sourceBase = 2
        } else if lower.hasPrefix("0o") {
            parsed = UInt64(lower.dropFirst(2), radix: 8)
            sourceBase = 8
        } else if content.count <= 9, content.allSatisfy(\.isNumber) {
            parsed = UInt64(content, radix: 10)
            sourceBase = 10
        } else {
            return []
        }
        guard let value = parsed else { return [] }
        let lines = [
            "输入进制：\(sourceBase)",
            "DEC: \(value)",
            "HEX: 0x\(String(value, radix: 16).uppercased())",
            "OCT: 0o\(String(value, radix: 8))",
            "BIN: 0b\(String(value, radix: 2))",
        ]
        return [ParseResult(parserName: name, original: content, parsed: lines.joined(separator: "\n"))]
    }
}

struct TOMLParser: ContentParser {
    let name = "TOML"
    private let assignment = ParserUtilities.regex(#"^[A-Za-z0-9_.-]+\s*=\s*.+"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.utf8.count <= 64 * 1024,
              !content.hasPrefix("{"), !content.hasPrefix("["),
              looksLikeTOML(content)
        else { return [] }
        let formatted = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(formatLine)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formatted.isEmpty else { return [] }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "TOML  大小：\(content.utf8.count) 字节",
            details: formatted
        )]
    }

    private func looksLikeTOML(_ content: String) -> Bool {
        content.lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let uncommented = String(trimmed.prefix { $0 != "#" })
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
                || ParserUtilities.fullMatch(assignment, uncommented) != nil
        }
    }

    private func formatLine(_ line: Substring) -> String {
        let raw = String(line)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else {
            return raw
        }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        return "\(key) = \(value)"
    }
}

struct XMLFormatParser: ContentParser {
    let name = "XML"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.utf8.count <= 128 * 1024,
              content.hasPrefix("<"),
              content.hasSuffix(">"),
              let data = content.data(using: .utf8),
              let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace])
        else { return [] }

        let formatted = document.xmlString(options: [.nodePrettyPrint])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formatted.isEmpty else { return [] }
        let root = document.rootElement()?.name ?? "unknown"
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "Root: \(root)\n大小：\(content.utf8.count) 字节",
            details: formatted
        )]
    }
}

private extension String {
    var lines: [String] {
        split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
