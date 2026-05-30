import Foundation
import Yams

struct CronParser: ContentParser {
    let name = "Cron"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let macros = [
            "@yearly": "每年 1 月 1 日 00:00 执行",
            "@annually": "每年 1 月 1 日 00:00 执行",
            "@monthly": "每月 1 日 00:00 执行",
            "@weekly": "每周日 00:00 执行",
            "@daily": "每天 00:00 执行",
            "@midnight": "每天 00:00 执行",
            "@hourly": "每小时整点执行",
            "@reboot": "系统重启后执行一次",
        ]
        if let desc = macros[content] {
            return [ParseResult(parserName: name, original: content, parsed: desc)]
        }
        let fields = content.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 || fields.count == 6, fields.allSatisfy(isValidField) else { return [] }
        let sec = fields.count == 6 ? explain(fields[0], unit: "秒") : nil
        let offset = fields.count == 6 ? 1 : 0
        let min = explain(fields[offset], unit: "分钟")
        let hour = explain(fields[offset + 1], unit: "小时")
        let day = explain(fields[offset + 2], unit: "天")
        let month = explain(fields[offset + 3], unit: "月", names: monthNames)
        let week = explain(fields[offset + 4], unit: "周", names: weekdayNames)
        var lines = ["分钟：\(min)", "小时：\(hour)", "日期：\(day)", "月份：\(month)", "星期：\(week)"]
        if let sec { lines.insert("秒：\(sec)", at: 0) }
        return [ParseResult(parserName: name, original: content, parsed: "\(month)，\(day)，\(hour)", details: lines.joined(separator: "\n"))]
    }

    private var weekdayNames: [String] { ["周日", "周一", "周二", "周三", "周四", "周五", "周六"] }
    private var monthNames: [String] { ["", "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"] }

    private func isValidField(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isNumber || "*-/?,LW#".contains($0) }
    }

    private func explain(_ field: String, unit: String, names: [String]? = nil) -> String {
        if field == "*" || field == "?" { return "每\(unit)" }
        if field.hasPrefix("*/") { return "每 \(field.dropFirst(2)) \(unit)" }
        if field.contains("-"), !field.contains("/") {
            let parts = field.split(separator: "-", maxSplits: 1).map(String.init)
            return "\(label(parts[0], names: names)) 到 \(label(parts[1], names: names))"
        }
        if field.contains("-"), field.contains("/"), let slash = field.firstIndex(of: "/") {
            let range = String(field[..<slash])
            let step = String(field[field.index(after: slash)...])
            let parts = range.split(separator: "-", maxSplits: 1).map(String.init)
            return "\(label(parts[0], names: names)) 到 \(label(parts.count > 1 ? parts[1] : parts[0], names: names)) 每隔 \(step)"
        }
        if field.contains(",") {
            return field.split(separator: ",").map { label(String($0), names: names) }.joined(separator: "、")
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
              let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: pretty, encoding: .utf8)
        else { return [] }
        let kind = content.hasPrefix("{") ? "object" : "array"
        return [ParseResult(parserName: name, original: content, parsed: "类型：\(kind)  大小：\(content.utf8.count) 字节", details: formatted)]
    }
}

struct JSON5Parser: ContentParser {
    let name = "JSON5"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.hasPrefix("{") || content.hasPrefix("[") else { return [] }
        let normalized = normalize(content)
        guard normalized != content,
              let data = normalized.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: pretty, encoding: .utf8)
        else { return [] }
        let kind = content.hasPrefix("{") ? "object" : "array"
        return [ParseResult(parserName: name, original: content, parsed: "类型：\(kind)  大小：\(content.utf8.count) 字节", details: formatted)]
    }

    private func normalize(_ input: String) -> String {
        var output = input
        output = output.replacingOccurrences(of: #"(?m)//.*$"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: #",(\s*[\]}])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"([\{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:"#, with: "$1\"$2\":", options: .regularExpression)
        output = output.replacingOccurrences(of: #"'"#, with: "\"")
        return output
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
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "类型：\(kind)  大小：\(content.utf8.count) 字节",
            details: "\(formatted.trimmingCharacters(in: .whitespacesAndNewlines))\n类型：\(kind)  大小：\(content.utf8.count) 字节"
        )]
    }

    private func looksLikeYAML(_ content: String) -> Bool {
        content.hasPrefix("---")
            || content.contains(": ")
            || content.contains(":\n")
            || content.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }.prefix(2).count >= 2
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
            parsed: "格式：\(variant)  编码长度：\(content.count)  解码长度：\(decoded.count)",
            details: "\(decoded)\n\n格式：\(variant)  编码长度：\(content.count)  解码长度：\(decoded.utf8.count) 字节"
        )]
    }
}
