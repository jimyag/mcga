import Foundation

struct CIDRParser: ContentParser {
    let name = "CIDR"
    private let pattern = ParserUtilities.regex(#"^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$"#)

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard let match = ParserUtilities.fullMatch(pattern, content),
              let ipRange = Range(match.range(at: 1), in: content),
              let prefixRange = Range(match.range(at: 2), in: content),
              let prefix = UInt8(content[prefixRange]),
              prefix <= 32,
              let ip = IPv4Address(String(content[ipRange]))
        else { return [] }

        let ipValue = ip.value
        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        let network = ipValue & mask
        let broadcast = network | ~mask
        if prefix == 0 {
            return [ParseResult(parserName: name, original: content, parsed: tr("默认路由（所有地址）", "Default route (all addresses)"))]
        }

        var lines: [String] = []
        if ipValue != network {
            let input = "\(ip.description)/\(prefix)"
            let masked = "\(IPv4Address(network))/\(prefix)"
            lines.append(tr("输入：\(input) → 网络：\(masked)", "Input: \(input) → network: \(masked)"))
        }

        switch prefix {
        case 32:
            lines.append(labeled("单主机地址", "Single host", "\(IPv4Address(network))"))
        case 31:
            lines.append(tr("点对点链路（RFC 3021）", "Point-to-point link (RFC 3021)"))
            lines.append(labeled("可用范围", "Usable range", "\(IPv4Address(network)) - \(IPv4Address(broadcast)) (2)"))
        default:
            let total = UInt64(1) << UInt64(32 - prefix)
            lines.append(labeled("网络地址", "Network", "\(IPv4Address(network))"))
            lines.append(labeled("广播地址", "Broadcast", "\(IPv4Address(broadcast))"))
            lines.append(labeled("可用范围", "Usable range", "\(IPv4Address(network + 1)) - \(IPv4Address(broadcast - 1)) (\(total - 2))"))
        }
        return [ParseResult(parserName: name, original: content, parsed: lines.joined(separator: "\n"))]
    }
}

struct IPv6Parser: ContentParser {
    let name = "IPv6"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard content.contains(":"), !content.contains(" ") else { return [] }
        let cleaned = content.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard let address = IPv6Address(cleaned) else { return [] }
        let type = labeled("类型", "Type", address.kind)
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: type,
            details: [
                labeled("压缩", "Compressed", address.description),
                labeled("展开", "Expanded", address.expanded),
                type,
            ].joined(separator: "\n")
        )]
    }
}

struct IPParser: ContentParser {
    let name = "IP"
    let isSlow = true
    let fetch: HTTPFetch

    func parse(_ content: String, previousContent: String) async -> [ParseResult] {
        guard let address = IPv4Address(content), address.isPublic else { return [] }
        var parsed = tr("公网 IP", "Public IP")
        var details = [
            labeled("八位组", "Octets", "\(address.octets)"),
            labeled("二进制", "Binary", address.octets.map { String($0, radix: 2).leftPadded(to: 8) }.joined(separator: ".")),
        ].joined(separator: "\n")
        if let lines = await IPGeo.lookup(content, fetch: fetch)?.displayLines, !lines.isEmpty {
            parsed = lines.joined(separator: "\n")
            details += "\n\n\(tr("地理位置信息：", "Geolocation:"))\n\(parsed)"
        }
        return [ParseResult(parserName: name, original: content, parsed: parsed, details: details)]
    }
}

struct DNSParser: ContentParser {
    let name = "DNS"
    let isSlow = true
    let fetch: HTTPFetch
    private let domainPattern = ParserUtilities.regex(#"^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#, options: [.caseInsensitive])
    private static let providers = [
        DNSProvider(name: "Cloudflare DoH", url: "https://cloudflare-dns.com/dns-query"),
        DNSProvider(name: "Google DoH", url: "https://dns.google/resolve"),
        DNSProvider(name: "AliDNS DoH", url: "https://dns.alidns.com/dns-query"),
    ]
    private static let recordTypes: [(number: UInt16, name: String)] = [(1, "A"), (28, "AAAA"), (5, "CNAME")]

    func parse(_ content: String, previousContent: String) async -> [ParseResult] {
        guard ParserUtilities.fullMatch(domainPattern, content) != nil else { return [] }
        let queries = Self.providers.flatMap { provider in Self.recordTypes.map { (provider, $0) } }
        // All queries at once; the results keep the provider and record type order.
        var answers = [[DNSAnswer]](repeating: [], count: queries.count)
        await withTaskGroup(of: (Int, [DNSAnswer]).self) { group in
            for (index, (provider, recordType)) in queries.enumerated() {
                group.addTask {
                    (index, await DNSLookup.query(domain: content, type: recordType.number, provider: provider, fetch: fetch))
                }
            }
            for await (index, result) in group {
                answers[index] = result.filter { $0.type == queries[index].1.number }
            }
        }
        return zip(queries, answers).compactMap { query, answers in
            guard !answers.isEmpty else { return nil }
            let (provider, recordType) = query
            let parsed = "DNS/\(recordType.name) via \(provider.name)\n\(answers.map(\.data).joined(separator: "\n"))"
            return ParseResult(parserName: name, original: content, parsed: parsed)
        }
    }
}

struct IPv4Address: CustomStringConvertible, Equatable {
    let value: UInt32

    init?(_ raw: String) {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        self.value = value
    }

    init(_ value: UInt32) {
        self.value = value
    }

    var octets: [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
    }

    var description: String {
        "\(value >> 24 & 0xff).\(value >> 16 & 0xff).\(value >> 8 & 0xff).\(value & 0xff)"
    }

    var isPublic: Bool {
        let first = (value >> 24) & 0xff
        let second = (value >> 16) & 0xff
        if first == 10 || first == 127 || first == 0 || first >= 224 { return false }
        if first == 172 && (16...31).contains(second) { return false }
        if first == 192 && second == 168 { return false }
        if first == 169 && second == 254 { return false }
        if first == 100 && (64...127).contains(second) { return false }
        return true
    }
}

struct IPv6Address: CustomStringConvertible {
    let description: String
    let expanded: String
    let segments: [UInt16]

    init?(_ raw: String) {
        var storage = in6_addr()
        guard raw.withCString({ inet_pton(AF_INET6, $0, &storage) }) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &storage, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
        let utf8 = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self.description = String(decoding: utf8, as: UTF8.self)
        self.segments = withUnsafeBytes(of: storage.__u6_addr.__u6_addr8) { rawBuffer in
            stride(from: 0, to: 16, by: 2).map { offset in
                UInt16(rawBuffer[offset]) << 8 | UInt16(rawBuffer[offset + 1])
            }
        }
        self.expanded = segments.map { String(format: "%04x", $0) }.joined(separator: ":")
    }

    var kind: String {
        if description == "::1" { return tr("回环地址 (::1)", "Loopback (::1)") }
        if description == "::" { return tr("未指定地址 (::)", "Unspecified (::)") }
        if (segments[0] & 0xffc0) == 0xfe80 { return tr("链路本地地址 (fe80::/10)", "Link-local (fe80::/10)") }
        if (segments[0] & 0xfe00) == 0xfc00 { return tr("唯一本地地址 (fc00::/7)", "Unique local (fc00::/7)") }
        if (segments[0] & 0xff00) == 0xff00 { return tr("多播地址 (ff00::/8)", "Multicast (ff00::/8)") }
        if segments[0...4].allSatisfy({ $0 == 0 }) && segments[5] == 0xffff {
            return tr("IPv4 映射地址 (::ffff:0:0/96)", "IPv4-mapped (::ffff:0:0/96)")
        }
        return tr("全局单播地址", "Global unicast")
    }
}

private struct IPGeo: Decodable {
    let status: String
    let country: String?
    let regionName: String?
    let city: String?
    let isp: String?
    let reverse: String?

    var displayLines: [String] {
        [
            ("国家", "Country", country),
            ("地区", "Region", regionName),
            ("城市", "City", city),
            ("ISP", "ISP", isp),
            ("反向 DNS", "Reverse DNS", reverse),
        ].compactMap { zh, en, value in
            guard let value, !value.isEmpty else { return nil }
            return labeled(zh, en, value)
        }
    }

    static func lookup(_ ip: String, fetch: HTTPFetch) async -> IPGeo? {
        guard let encoded = ip.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://ip-api.com/json/\(encoded)?fields=status,message,country,regionName,city,isp,reverse,query&lang=\(tr("zh-CN", "en"))"),
              let data = await fetch(URLRequest(url: url, timeoutInterval: 5)),
              let response = try? JSONDecoder().decode(IPGeo.self, from: data),
              response.status == "success"
        else { return nil }
        return response
    }
}

private struct DNSProvider {
    let name: String
    let url: String
}

private struct DNSResponse: Decodable {
    let Status: Int
    let Answer: [DNSAnswer]?
}

private struct DNSAnswer: Decodable {
    let type: UInt16
    let TTL: UInt32
    let data: String
}

private enum DNSLookup {
    static func query(domain: String, type: UInt16, provider: DNSProvider, fetch: HTTPFetch) async -> [DNSAnswer] {
        guard var components = URLComponents(string: provider.url) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "name", value: domain),
            URLQueryItem(name: "type", value: "\(type)"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        guard let data = await fetch(request),
              let response = try? JSONDecoder().decode(DNSResponse.self, from: data),
              response.Status == 0
        else { return [] }
        return response.Answer ?? []
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
