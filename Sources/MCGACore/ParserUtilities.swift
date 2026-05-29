import Foundation

enum ParserUtilities {
    static func utcString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS 'UTC'"
        return formatter.string(from: date)
    }

    static func utcSecondString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }

    static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static func fullMatch(_ regex: NSRegularExpression, _ value: String) -> NSTextCheckingResult? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.range == range else {
            return nil
        }
        return match
    }

    static func dataFromBase64Variants(_ value: String) -> (Data, String)? {
        if let data = Data(base64Encoded: value) {
            return (data, "standard")
        }
        let urlSafePadded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if let data = Data(base64Encoded: urlSafePadded) {
            return (data, "url-safe")
        }
        let padded = urlSafePadded + String(repeating: "=", count: (4 - urlSafePadded.count % 4) % 4)
        if let data = Data(base64Encoded: padded) {
            return (data, "url-safe-no-pad")
        }
        return nil
    }

    static func isPrintable(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 32 || scalar == "\n" || scalar == "\r" || scalar == "\t"
        }
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func randomBytes(count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8.random(in: .min ... .max) }
    }
}

extension String {
    var mcgaTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
