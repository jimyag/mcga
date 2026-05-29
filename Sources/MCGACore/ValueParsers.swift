import Foundation

struct UUIDParser: ContentParser {
    let name = "UUID"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.contains("-"), let uuid = UUID(uuidString: content) else { return [] }
        let bytes = uuid.uuidBytes
        let version = Int((bytes[6] & 0xf0) >> 4)
        let versionInfo = versionDescription(version)
        let variantInfo = variantDescription(bytes[8])
        let high = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let low = bytes.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }

        var details = """
        版本：\(versionInfo)
        变体：\(variantInfo)
        大写：\(uuid.uuidString.uppercased())
        URN: urn:uuid:\(uuid.uuidString.lowercased())
        高 64 位：0x\(String(format: "%016llx", high))
        低 64 位：0x\(String(format: "%016llx", low))
        """

        var timeInfo = ""
        if let date = uuidTime(version: version, bytes: bytes) {
            let formatted = ParserUtilities.utcString(from: date)
            timeInfo = "\n创建时间：\(formatted)"
            details += "\n\n时间信息:\n  创建时间：\(formatted)\n  ISO 8601: \(ParserUtilities.isoString(from: date))"
            if version == 1 {
                let mac = bytes[10...15].map { String(format: "%02x", $0) }.joined(separator: ":")
                details += "\n\n节点信息:\n  MAC 地址：\(mac)"
                if bytes[10] & 0x01 == 0x01 {
                    details += " (随机生成)"
                }
            }
        } else if [2, 3, 4, 5, 8].contains(version) {
            timeInfo = "\n时间信息：无 (该版本不包含时间戳)"
            details += "\n\n时间信息：该版本不包含时间戳"
        } else {
            timeInfo = "\n时间信息：无法解析"
        }

        return [ParseResult(parserName: name, original: content, parsed: "\(versionInfo)\(timeInfo)", details: details)]
    }

    private func versionDescription(_ version: Int) -> String {
        switch version {
        case 1: "v1 (基于时间和 MAC 地址)"
        case 2: "v2 (DCE Security)"
        case 3: "v3 (基于 MD5 哈希)"
        case 4: "v4 (随机生成)"
        case 5: "v5 (基于 SHA-1 哈希)"
        case 6: "v6 (有序时间戳)"
        case 7: "v7 (Unix 时间戳)"
        case 8: "v8 (自定义)"
        default: "未知版本"
        }
    }

    private func variantDescription(_ byte: UInt8) -> String {
        if byte & 0x80 == 0 { return "NCS 向后兼容" }
        if byte & 0xc0 == 0x80 { return "RFC 4122" }
        if byte & 0xe0 == 0xc0 { return "Microsoft 向后兼容" }
        return "保留给未来定义"
    }

    private func uuidTime(version: Int, bytes: [UInt8]) -> Date? {
        let uuidEpochDiff: UInt64 = 122_192_928_000_000_000
        let timestamp: UInt64
        switch version {
        case 1:
            let timeLow = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
            let timeMid = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
            let timeHigh = (UInt64(bytes[6]) << 8 | UInt64(bytes[7])) & 0x0fff
            timestamp = timeLow | (timeMid << 32) | (timeHigh << 48)
        case 6:
            let high = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
            let mid = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
            let low = (UInt64(bytes[6]) << 8 | UInt64(bytes[7])) & 0x0fff
            timestamp = (high << 28) | (mid << 12) | low
        case 7:
            let millis = bytes[0...5].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        default:
            return nil
        }
        guard timestamp >= uuidEpochDiff else { return nil }
        let unix100ns = timestamp - uuidEpochDiff
        return Date(timeIntervalSince1970: TimeInterval(unix100ns) / 10_000_000)
    }
}

struct ObjectIDParser: ContentParser {
    let name = "ObjectID"
    private let pattern = ParserUtilities.regex(#"^[0-9a-fA-F]{24}$"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard ParserUtilities.fullMatch(pattern, content) != nil else { return [] }
        let bytes = stride(from: 0, to: content.count, by: 2).compactMap { offset -> UInt8? in
            let start = content.index(content.startIndex, offsetBy: offset)
            let end = content.index(start, offsetBy: 2)
            return UInt8(content[start..<end], radix: 16)
        }
        guard bytes.count == 12 else { return [] }
        let seconds = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let random = ParserUtilities.hex(bytes[4..<9])
        let counter = UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11])
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "创建时间: \(ParserUtilities.utcSecondString(from: date))\n随机值: \(random)\n计数器: \(counter)",
            details: "时间戳: \(seconds)\nISO 8601: \(ParserUtilities.isoString(from: date))"
        )]
    }
}

struct HashParser: ContentParser {
    let name = "Hash"
    private let pattern = ParserUtilities.regex(#"^[0-9a-fA-F]+$"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard ParserUtilities.fullMatch(pattern, content) != nil else { return [] }
        let kind: String
        switch content.count {
        case 32: kind = "MD5"
        case 40: kind = "SHA-1"
        case 56: kind = "SHA-224"
        case 64: kind = "SHA-256"
        case 96: kind = "SHA-384"
        case 128: kind = "SHA-512"
        default: return []
        }
        return [ParseResult(parserName: name, original: content, parsed: "类型：\(kind)\n长度：\(content.count) hex 字符")]
    }
}

struct TimestampParser: ContentParser {
    let name = "Timestamp"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.allSatisfy(\.isNumber), let value = Int64(content) else { return [] }
        let unit: String
        let seconds: TimeInterval
        switch content.count {
        case 10:
            unit = "秒"
            seconds = TimeInterval(value)
        case 13:
            unit = "毫秒"
            seconds = TimeInterval(value) / 1_000
        case 16:
            unit = "微秒"
            seconds = TimeInterval(value) / 1_000_000
        case 17:
            unit = "百纳秒"
            seconds = TimeInterval(value) / 10_000_000
        case 19:
            unit = "纳秒"
            seconds = TimeInterval(value) / 1_000_000_000
        default:
            return []
        }
        guard seconds >= 0, seconds <= 4_102_444_800 else { return [] }
        let date = Date(timeIntervalSince1970: seconds)
        let formatted = ParserUtilities.utcString(from: date)
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "精度：\(unit)\n时间：\(formatted)",
            details: "原始值：\(value)\n精度：\(unit)\nUTC: \(formatted)\nISO 8601: \(ParserUtilities.isoString(from: date))"
        )]
    }
}

    private let pattern = ParserUtilities.regex(#"^[A-Za-z0-9_-]{16}$"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard ParserUtilities.fullMatch(pattern, content) != nil,
              let (data, _) = ParserUtilities.dataFromBase64Variants(content),
              data.count == 12
        else { return [] }
        let bytes = [UInt8](data)
        let pid = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let unixNano = bytes[4..<12].enumerated().reduce(Int64(0)) { acc, item in
            acc | (Int64(item.element) << Int64(item.offset * 8))
        }
        let seconds = TimeInterval(unixNano) / 1_000_000_000
        let date = Date(timeIntervalSince1970: seconds)
        guard date >= Date(timeIntervalSince1970: 1_420_070_400) else { return [] }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "时间：\(ParserUtilities.utcString(from: date))\nPID: \(pid)",
            details: "UnixNano: \(unixNano)\nISO 8601: \(ParserUtilities.isoString(from: date))"
        )]
    }
}

extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
