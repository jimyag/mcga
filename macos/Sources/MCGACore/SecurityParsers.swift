import CryptoKit
import Foundation
import Security

struct JWTParser: ContentParser {
    let name = "JWT"
    private let segmentPattern = ParserUtilities.regex(#"^[A-Za-z0-9_-]+$"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let token = content.lowercased().hasPrefix("bearer ") ? String(content.dropFirst(7)).mcgaTrimmed : content
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let header = object(parts[0]), let payload = object(parts[1]),
              let algorithm = header["alg"] as? String, !algorithm.isEmpty,
              parts[2].isEmpty ? algorithm == "none" : decode(parts[2]) != nil,
              let headerJSON = pretty(header), let payloadJSON = pretty(payload) else { return [] }
        var lines = [labeled("算法", "Algorithm", algorithm),
                     labeled("签名", "Signature", tr("未验证（仅解码）", "Not verified (decode only)"))]
        for (claim, zh, en) in [("iat", "签发时间", "Issued at"), ("nbf", "生效时间", "Not before"), ("exp", "到期时间", "Expires at")] {
            guard let seconds = numericDate(payload[claim]) else { continue }
            lines.append(labeled(zh, en, ParserUtilities.utcSecondString(from: Date(timeIntervalSince1970: seconds))))
        }
        if let expiration = numericDate(payload["exp"]) {
            lines.append(labeled("时间状态", "Time status", expiration <= Date().timeIntervalSince1970
                ? tr("已到期（未验证声明）", "Expired (unverified claim)") : tr("尚未到期（未验证声明）", "Not expired (unverified claim)")))
        }
        lines += ["", "Header:", headerJSON, "", "Payload:", payloadJSON]
        return [ParseResult(parserName: name, original: content, parsed: lines.joined(separator: "\n"))]
    }

    private func decode(_ text: String) -> Data? {
        guard ParserUtilities.fullMatch(segmentPattern, text) != nil else { return nil }
        return ParserUtilities.dataFromBase64Variants(text)?.0
    }

    private func object(_ text: String) -> [String: Any]? {
        guard let data = decode(text) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func pretty(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func numericDate(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, abs(number.doubleValue) <= 253_402_300_799 else { return nil }
        return number.doubleValue
    }
}

struct PEMCertificateParser: ContentParser {
    let name = "PEM Certificate"
    private let pattern = ParserUtilities.regex(#"-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        let matches = pattern.matches(in: content, range: NSRange(content.startIndex..<content.endIndex, in: content))
        guard !matches.isEmpty else { return [] }
        var end = content.startIndex
        var results: [ParseResult] = []
        for match in matches {
            guard let range = Range(match.range, in: content), let body = Range(match.range(at: 1), in: content),
                  content[end..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = Data(base64Encoded: content[body].filter { !$0.isWhitespace }),
                  let certificate = SecCertificateCreateWithData(nil, data as CFData),
                  let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] else { return [] }
            end = range.upperBound
            func value(_ oid: CFString) -> Any? {
                (values[oid as String] as? [String: Any])?[kSecPropertyKeyValue as String]
            }
            var lines = [labeled("主体", "Subject", describe(value(kSecOIDX509V1SubjectName))),
                         labeled("签发者", "Issuer", describe(value(kSecOIDX509V1IssuerName))),
                         labeled("序列号", "Serial", describe(value(kSecOIDX509V1SerialNumber)))]
            for (oid, zh, en) in [(kSecOIDX509V1ValidityNotBefore, "起始时间", "Not before"), (kSecOIDX509V1ValidityNotAfter, "截止时间", "Not after")] {
                if let seconds = value(oid) as? NSNumber {
                    lines.append(labeled(zh, en, ParserUtilities.utcSecondString(from: Date(timeIntervalSinceReferenceDate: seconds.doubleValue))))
                }
            }
            if let names = value(kSecOIDSubjectAltName) {
                lines.append(labeled("备用名称", "SAN", describe(names)))
            }
            if let key = SecCertificateCopyKey(certificate), let attributes = SecKeyCopyAttributes(key) as? [String: Any],
               let bits = attributes[kSecAttrKeySizeInBits as String] {
                lines.append(labeled("公钥位数", "Key bits", "\(bits)"))
            }
            lines.append("SHA-256: \(ParserUtilities.hex(SHA256.hash(data: data)))")
            lines.append(labeled("验证", "Verification", tr("仅解析，未验证信任链", "Parse only; trust chain not verified")))
            results.append(ParseResult(parserName: name, original: content, parsed: lines.joined(separator: "\n")))
        }
        return content[end...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? results : []
    }

    private func describe(_ value: Any?) -> String {
        if let entries = value as? [[String: Any]] {
            return entries.map { entry in
                let label = entry[kSecPropertyKeyLabel as String] as? String ?? ""
                let text = describe(entry[kSecPropertyKeyValue as String])
                return label.isEmpty ? text : "\(label)=\(text)"
            }.joined(separator: ", ")
        }
        if let data = value as? Data { return ParserUtilities.hex(data) }
        return value.map { String(describing: $0) } ?? tr("无", "None")
    }
}

struct SSHPublicKeyParser: ContentParser {
    let name = "SSH Public Key"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard !content.contains(where: \.isNewline) else { return [] }
        let parts = content.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2, let data = Data(base64Encoded: parts[1]) else { return [] }
        var wire = SSHKeyFields(bytes: Array(data))
        guard let typeBytes = wire.next(), let type = String(bytes: typeBytes, encoding: .utf8), type == parts[0] else { return [] }
        let bits: Int
        switch type {
        case "ssh-ed25519":
            guard wire.next()?.count == 32 else { return [] }
            bits = 256
        case "ssh-rsa":
            guard let exponent = wire.next(), let modulus = wire.next(),
                  positiveMPInt(exponent), positiveMPInt(modulus) else { return [] }
            bits = bitCount(modulus)
        case "ssh-dss":
            guard let p = wire.next(), positiveMPInt(p) else { return [] }
            for _ in 0..<3 {
                guard let field = wire.next(), positiveMPInt(field) else { return [] }
            }
            bits = bitCount(p)
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            guard let curveBytes = wire.next(), let curve = String(bytes: curveBytes, encoding: .utf8),
                  type == "ecdsa-sha2-\(curve)", let point = wire.next() else { return [] }
            bits = ["nistp256": 256, "nistp384": 384, "nistp521": 521][curve]!
            guard point.first == 4, point.count == 1 + 2 * ((bits + 7) / 8) else { return [] }
        default: return []
        }
        guard wire.offset == wire.bytes.count else { return [] }
        let fingerprint = Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        var lines = [labeled("类型", "Type", type), labeled("位数", "Bits", "\(bits)"),
                     labeled("指纹", "Fingerprint", "SHA256:\(fingerprint)")]
        if parts.count == 3 { lines.append(labeled("注释", "Comment", parts[2])) }
        return [ParseResult(parserName: name, original: content, parsed: lines.joined(separator: "\n"))]
    }

    private func positiveMPInt(_ bytes: [UInt8]) -> Bool {
        guard let first = bytes.first, first < 128 else { return false }
        return first != 0 || (bytes.count > 1 && bytes[1] >= 128)
    }

    private func bitCount(_ bytes: [UInt8]) -> Int {
        let significant = bytes.drop(while: { $0 == 0 })
        guard let first = significant.first else { return 0 }
        return (significant.count - 1) * 8 + 8 - first.leadingZeroBitCount
    }
}

private struct SSHKeyFields {
    let bytes: [UInt8]
    var offset = 0

    mutating func next() -> [UInt8]? {
        guard bytes.count - offset >= 4 else { return nil }
        let count = bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        offset += 4
        guard count <= bytes.count - offset else { return nil }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }
}

struct MACAddressParser: ContentParser {
    let name = "MAC Address"
    private let pattern = ParserUtilities.regex(#"^(?:[0-9a-fA-F]{2}([:-])(?:[0-9a-fA-F]{2}\1){4}[0-9a-fA-F]{2}|[0-9a-fA-F]{4}(?:\.[0-9a-fA-F]{4}){2}|[0-9a-fA-F]{12})$"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard ParserUtilities.fullMatch(pattern, content) != nil,
              !content.allSatisfy(\.isNumber) else { return [] }
        let hex = content.filter { $0.isHexDigit }.lowercased()
        let bytes = stride(from: 0, to: 12, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 2)])
        }
        guard let first = UInt8(bytes[0], radix: 16) else { return [] }
        let scope = first & 2 == 0 ? tr("全局管理", "Universally administered") : tr("本地管理", "Locally administered")
        let kind = bytes.allSatisfy { $0 == "ff" } ? tr("广播", "Broadcast")
            : first & 1 == 0 ? tr("单播", "Unicast") : tr("组播", "Multicast")
        let text = ["MAC: \(bytes.joined(separator: ":"))", "MAC (-): \(bytes.joined(separator: "-"))",
                    labeled("类型", "Type", kind), labeled("管理方式", "Administration", scope),
                    "OUI: \(bytes.prefix(3).joined(separator: ":"))"].joined(separator: "\n")
        return [ParseResult(parserName: name, original: content, parsed: text)]
    }
}
