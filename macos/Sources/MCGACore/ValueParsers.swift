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

        var details = [
            labeled("版本", "Version", versionInfo),
            labeled("变体", "Variant", variantInfo),
            labeled("大写", "Uppercase", uuid.uuidString.uppercased()),
            "URN: urn:uuid:\(uuid.uuidString.lowercased())",
            labeled("高 64 位", "High 64 bits", "0x\(String(format: "%016llx", high))"),
            labeled("低 64 位", "Low 64 bits", "0x\(String(format: "%016llx", low))"),
        ].joined(separator: "\n")

        var timeInfo = ""
        if let date = uuidTime(version: version, bytes: bytes) {
            let created = labeled("创建时间", "Created", ParserUtilities.utcString(from: date))
            timeInfo = "\n\(created)"
            details += "\n\n\(tr("时间信息:", "Time:"))\n  \(created)\n  ISO 8601: \(ParserUtilities.isoString(from: date))"
            if version == 1 {
                let mac = bytes[10...15].map { String(format: "%02x", $0) }.joined(separator: ":")
                details += "\n\n\(tr("节点信息:", "Node:"))\n  \(labeled("MAC 地址", "MAC address", mac))"
                if bytes[10] & 0x01 == 0x01 {
                    details += tr(" (随机生成)", " (random)")
                }
            }
        } else if [2, 3, 4, 5, 8].contains(version) {
            timeInfo = "\n" + tr("时间信息：无 (该版本不包含时间戳)", "Time: none (this version has no timestamp)")
            details += "\n\n" + tr("时间信息：该版本不包含时间戳", "Time: this version has no timestamp")
        } else {
            timeInfo = "\n" + tr("时间信息：无法解析", "Time: cannot be read")
        }

        return [ParseResult(parserName: name, original: content, parsed: "\(versionInfo)\(timeInfo)", details: details)]
    }

    private func versionDescription(_ version: Int) -> String {
        switch version {
        case 1: tr("v1 (基于时间和 MAC 地址)", "v1 (time and MAC address)")
        case 2: "v2 (DCE Security)"
        case 3: tr("v3 (基于 MD5 哈希)", "v3 (MD5 hash)")
        case 4: tr("v4 (随机生成)", "v4 (random)")
        case 5: tr("v5 (基于 SHA-1 哈希)", "v5 (SHA-1 hash)")
        case 6: tr("v6 (有序时间戳)", "v6 (ordered time)")
        case 7: tr("v7 (Unix 时间戳)", "v7 (Unix time)")
        case 8: tr("v8 (自定义)", "v8 (custom)")
        default: tr("未知版本", "Unknown version")
        }
    }

    private func variantDescription(_ byte: UInt8) -> String {
        if byte & 0x80 == 0 { return tr("NCS 向后兼容", "NCS backward compatible") }
        if byte & 0xc0 == 0x80 { return "RFC 4122" }
        if byte & 0xe0 == 0xc0 { return tr("Microsoft 向后兼容", "Microsoft backward compatible") }
        return tr("保留给未来定义", "Reserved for future use")
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
            parsed: [
                "\(tr("创建时间", "Created")): \(ParserUtilities.utcSecondString(from: date))",
                "\(tr("随机值", "Random")): \(random)",
                "\(tr("计数器", "Counter")): \(counter)",
            ].joined(separator: "\n"),
            details: "\(tr("时间戳", "Timestamp")): \(seconds)\nISO 8601: \(ParserUtilities.isoString(from: date))"
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
        let length = labeled("长度", "Length", tr("\(content.count) hex 字符", "\(content.count) hex characters"))
        return [ParseResult(parserName: name, original: content, parsed: "\(labeled("类型", "Type", kind))\n\(length)")]
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
            unit = tr("秒", "seconds")
            seconds = TimeInterval(value)
        case 13:
            unit = tr("毫秒", "milliseconds")
            seconds = TimeInterval(value) / 1_000
        case 16:
            unit = tr("微秒", "microseconds")
            seconds = TimeInterval(value) / 1_000_000
        case 17:
            unit = tr("百纳秒", "100-nanosecond ticks")
            seconds = TimeInterval(value) / 10_000_000
        case 19:
            unit = tr("纳秒", "nanoseconds")
            seconds = TimeInterval(value) / 1_000_000_000
        default:
            return []
        }
        guard seconds >= 0, seconds <= 4_102_444_800 else { return [] }
        let date = Date(timeIntervalSince1970: seconds)
        let formatted = ParserUtilities.utcString(from: date)
        let precision = labeled("精度", "Precision", unit)
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "\(precision)\n\(labeled("时间", "Time", formatted))",
            details: "\(labeled("原始值", "Raw value", "\(value)"))\n\(precision)\nUTC: \(formatted)\nISO 8601: \(ParserUtilities.isoString(from: date))"
        )]
    }
}

extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
