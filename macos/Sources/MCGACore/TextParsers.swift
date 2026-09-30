import Foundation
import Yams

struct CronParser: ContentParser {
    let name = "Cron"

    private struct Unit {
        let zh: String
        let one: String
        let many: String
    }

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let macros = [
            "@yearly": tr("每年 1 月 1 日 00:00 执行", "At 00:00 on January 1 every year"),
            "@annually": tr("每年 1 月 1 日 00:00 执行", "At 00:00 on January 1 every year"),
            "@monthly": tr("每月 1 日 00:00 执行", "At 00:00 on day 1 of every month"),
            "@weekly": tr("每周日 00:00 执行", "At 00:00 every Sunday"),
            "@daily": tr("每天 00:00 执行", "At 00:00 every day"),
            "@midnight": tr("每天 00:00 执行", "At 00:00 every day"),
            "@hourly": tr("每小时整点执行", "At the start of every hour"),
            "@reboot": tr("系统重启后执行一次", "Once after the system starts"),
        ]
        if let desc = macros[content] {
            return [ParseResult(parserName: name, original: content, parsed: desc)]
        }
        let fields = content.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 || fields.count == 6, fields.allSatisfy(isValidField) else { return [] }
        let sec = fields.count == 6 ? explain(fields[0], unit: Unit(zh: "秒", one: "second", many: "seconds")) : nil
        let offset = fields.count == 6 ? 1 : 0
        let min = explain(fields[offset], unit: Unit(zh: "分钟", one: "minute", many: "minutes"))
        let hour = explain(fields[offset + 1], unit: Unit(zh: "小时", one: "hour", many: "hours"))
        let day = explain(fields[offset + 2], unit: Unit(zh: "天", one: "day", many: "days"))
        let month = explain(fields[offset + 3], unit: Unit(zh: "月", one: "month", many: "months"), names: monthNames)
        let week = explain(fields[offset + 4], unit: Unit(zh: "周", one: "day of the week", many: "days of the week"), names: weekdayNames)
        var lines = [
            labeled("分钟", "Minute", min),
            labeled("小时", "Hour", hour),
            labeled("日期", "Day", day),
            labeled("月份", "Month", month),
            labeled("星期", "Weekday", week),
        ]
        if let sec { lines.insert(labeled("秒", "Second", sec), at: 0) }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: [month, day, hour].joined(separator: tr("，", ", ")),
            details: lines.joined(separator: "\n")
        )]
    }

    private var weekdayNames: [String] {
        Localization.language == .zh
            ? ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    private var monthNames: [String] {
        Localization.language == .zh
            ? ["", "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]
            : ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    }

    /// A lone "-" or "," is punctuation, as in "138 - 1234 - 5678", not a cron field.
    private func isValidField(_ value: String) -> Bool {
        value.allSatisfy { $0.isNumber || "*-/?,LW#".contains($0) }
            && value.contains { $0.isNumber || "*?LW".contains($0) }
    }

    private func explain(_ field: String, unit: Unit, names: [String]? = nil) -> String {
        if field == "*" || field == "?" { return tr("每\(unit.zh)", "every \(unit.one)") }
        if field.hasPrefix("*/") {
            let step = field.dropFirst(2)
            return tr("每 \(step) \(unit.zh)", "every \(step) \(unit.many)")
        }
        // Splitting "5-" leaves one part, so every range needs both ends before it is read.
        if field.contains("-"), !field.contains("/") {
            let parts = field.split(separator: "-", maxSplits: 1).map { label(String($0), names: names) }
            if parts.count == 2 {
                return tr("\(parts[0]) 到 \(parts[1])", "\(parts[0]) to \(parts[1])")
            }
        }
        if field.contains("-"), let slash = field.firstIndex(of: "/") {
            let step = field[field.index(after: slash)...]
            let parts = field[..<slash].split(separator: "-", maxSplits: 1).map { label(String($0), names: names) }
            if let first = parts.first, let last = parts.last {
                return tr("\(first) 到 \(last) 每隔 \(step)", "every \(step) from \(first) to \(last)")
            }
        }
        if field.contains(",") {
            return field.split(separator: ",").map { label(String($0), names: names) }.joined(separator: tr("、", ", "))
        }
        return label(field, names: names)
    }

    private func label(_ value: String, names: [String]?) -> String {
        if let names, let index = Int(value), names.indices.contains(index) {
            return names[index]
        }
        return value
    }
}

struct JSONParser: ContentParser {
    let name = "JSON"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.hasPrefix("{") || content.hasPrefix("["),
              let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)),
              let formatted = JSONFormat.pretty(object)
        else { return [] }
        return [ParseResult(parserName: name, original: content, parsed: JSONFormat.summary(content), details: formatted)]
    }
}

/// Comments, trailing commas, unquoted keys and single quotes; Foundation reads JSON5 natively.
struct JSON5Parser: ContentParser {
    let name = "JSON5"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let data = Data(content.utf8)
        // Strict JSON already has a JSON result.
        guard content.hasPrefix("{") || content.hasPrefix("["),
              (try? JSONSerialization.jsonObject(with: data)) == nil,
              let object = try? JSONSerialization.jsonObject(with: data, options: .json5Allowed),
              let formatted = JSONFormat.pretty(object)
        else { return [] }
        return [ParseResult(parserName: name, original: content, parsed: JSONFormat.summary(content), details: formatted)]
    }
}

private enum JSONFormat {
    static func pretty(_ object: Any) -> String? {
        // The validity check keeps NaN and infinities, which JSON5 allows, away from the writer.
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func summary(_ content: String) -> String {
        let kind = content.hasPrefix("{") ? "object" : "array"
        return tr("类型：\(kind)  大小：\(content.utf8.count) 字节", "Type: \(kind)  Size: \(content.utf8.count) bytes")
    }
}

struct YAMLParser: ContentParser {
    let name = "YAML"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.utf8.count <= 64 * 1024,
              !content.hasPrefix("{"), !content.hasPrefix("["),
              looksLikeYAML(content),
              let yaml = try? Yams.load(yaml: content),
              yaml is [Any] || yaml is [String: Any],
              let formatted = try? Yams.dump(object: yaml)
        else { return [] }
        let kind = yaml is [String: Any] ? "map" : "sequence"
        let summary = tr("类型：\(kind)  大小：\(content.utf8.count) 字节", "Type: \(kind)  Size: \(content.utf8.count) bytes")
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: summary,
            details: formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        )]
    }

    /// One "key: value" line is usually prose or a log message, so a document needs two
    /// key, section or list lines, or a leading "---".
    private func looksLikeYAML(_ content: String) -> Bool {
        if content.hasPrefix("---") { return true }
        let structural = content.split(whereSeparator: \.isNewline).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- ") || trimmed.contains(": ") || trimmed.hasSuffix(":")
        }
        return structural.count >= 2
    }
}

struct Base64Parser: ContentParser {
    let name = "Base64"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.count >= 8,
              content.allSatisfy({ $0.isLetter || $0.isNumber || "+/-_=".contains($0) }),
              let (data, variant) = ParserUtilities.dataFromBase64Variants(content),
              let decoded = String(data: data, encoding: .utf8),
              ParserUtilities.isPrintable(decoded)
        else { return [] }
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: tr(
                "格式：\(variant)  编码长度：\(content.count)  解码长度：\(decoded.count)",
                "Format: \(variant)  Encoded: \(content.count)  Decoded: \(decoded.count)"
            ),
            details: "\(decoded)\n\n" + tr(
                "格式：\(variant)  编码长度：\(content.count)  解码长度：\(decoded.utf8.count) 字节",
                "Format: \(variant)  Encoded: \(content.count)  Decoded: \(decoded.utf8.count) bytes"
            )
        )]
    }
}
