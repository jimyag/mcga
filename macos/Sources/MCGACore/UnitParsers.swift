import Foundation

private enum DataUnits {
    static let pattern = ParserUtilities.regex(#"^\+?([0-9]+(?:\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?\s*([A-Za-z]+|字节|位|比特)?$"#)

    static var units: [(symbol: String, aliases: [String], bytes: Double)] {
        var units: [(String, [String], Double)] = [
            ("bit", ["b", "bits", "位", "比特"], 0.125),
            ("B", ["byte", "bytes", "Byte", "Bytes", "字节"], 1)
        ]
        for (index, prefix) in ["k", "M", "G", "T", "P", "E"].enumerated() {
            let bytes = pow(1000, Double(index + 1))
            units.append(("\(prefix)bit", index == 0 ? ["kb", "Kb", "Kbit"] : ["\(prefix)b"], bytes / 8))
            units.append((index == 0 ? "kB" : "\(prefix)B", index == 0 ? ["KB", "k", "K"] : [prefix], bytes))
        }
        for (index, prefix) in ["K", "M", "G", "T", "P", "E"].enumerated() {
            let bytes = pow(1024, Double(index + 1))
            units.append(("\(prefix)ibit", ["\(prefix)ib"], bytes / 8))
            units.append(("\(prefix)iB", ["\(prefix)i"], bytes))
        }
        return units
    }

    static func quantity(_ content: String) -> (bytes: Double, suffix: String, symbol: String)? {
        guard let match = ParserUtilities.fullMatch(pattern, content) else { return nil }
        func capture(_ index: Int) -> String {
            Range(match.range(at: index), in: content).map { String(content[$0]) } ?? ""
        }
        let suffix = capture(3)
        guard let value = Double(capture(1) + capture(2)), value.isFinite,
              value != 0 || Double(capture(1)) == 0,
              let input = units.first(where: { $0.symbol == (suffix.isEmpty ? "B" : suffix) || $0.aliases.contains(suffix) }) else { return nil }
        let bytes = value * input.bytes
        return bytes.isFinite && (value == 0 || bytes > 0) ? (bytes, suffix, input.symbol) : nil
    }

    static func lines(_ bytes: Double, perSecond: Bool) -> [String]? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 12
        var lines: [String] = []
        for unit in units {
            let converted = bytes / unit.bytes
            guard converted.isFinite, bytes == 0 || converted > 0 else { return nil }
            guard let number = formatter.string(from: NSNumber(value: converted)) else { return nil }
            let symbol = unit.symbol + (perSecond ? "/s" : "")
            lines.append("\(symbol): \(number) \(symbol)")
        }
        return lines
    }

    static var notes: [String] {
        [tr("bit = 位；B = 字节；1 B = 8 bit", "bit = bit; B = byte; 1 B = 8 bit"),
         tr("十进制前缀 = 1000；二进制前缀 (Ki/Mi/…) = 1024", "Decimal prefixes = 1000; binary prefixes (Ki/Mi/…) = 1024"),
         tr("结果最多保留 12 位有效数字", "Results use up to 12 significant digits")]
    }
}

struct DataSizeParser: ContentParser {
    let name = "Data Size"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard let input = DataUnits.quantity(content), let lines = DataUnits.lines(input.bytes, perSecond: false) else { return [] }
        let heading = input.suffix.isEmpty
            ? tr("无单位数字，按字节 (B) 换算", "Unitless number interpreted as bytes (B)")
            : "\(content) → \(input.symbol)"
        return [ParseResult(parserName: name, original: content, parsed: ([heading] + DataUnits.notes + lines).joined(separator: "\n"))]
    }
}

struct DataRateParser: ContentParser {
    let name = "Data Rate"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let quantity: String
        if content.hasSuffix("/s") { quantity = String(content.dropLast(2)) }
        else if content.hasSuffix("/秒") { quantity = String(content.dropLast(2)) }
        else if content.hasSuffix("ps") { quantity = String(content.dropLast(2)) }
        else { return [] }
        guard let input = DataUnits.quantity(quantity), !input.suffix.isEmpty,
              let lines = DataUnits.lines(input.bytes, perSecond: true) else { return [] }
        let heading = "\(content) → \(input.symbol)/s"
        return [ParseResult(parserName: name, original: content, parsed: ([heading] + DataUnits.notes + lines).joined(separator: "\n"))]
    }
}
