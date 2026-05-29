import Foundation

    private let ipMap: [String: String]
    private let nodeMap: [String: String]

    init() {
        let path = FileManager.default.homeDirectoryForCurrentUser
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            self.ipMap = [:]
            self.nodeMap = [:]
            return
        }
        var ipMap: [String: String] = [:]
        var nodeMap: [String: String] = [:]
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard index > 0 else { continue }
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            nodeMap[parts[0]] = parts[1]
            ipMap[parts[1]] = parts[0]
        }
        self.ipMap = ipMap
        self.nodeMap = nodeMap
    }

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        if let node = ipMap[content] {
            return [ParseResult(parserName: name, original: content, parsed: "节点：\(node)")]
        }
        if let ip = nodeMap[content] {
            return [ParseResult(parserName: name, original: content, parsed: "IP:\(ip)")]
        }
        return []
    }
}

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
            return [ParseResult(parserName: name, original: content, parsed: "默认路由（所有地址）")]
        }

        var lines: [String] = []
        if ipValue != network {
            lines.append("输入：\(ip.description)/\(prefix) → 网络：\(IPv4Address(network))/\(prefix)")
        }

        switch prefix {
        case 32:
            lines.append("单主机地址：\(IPv4Address(network))")
        case 31:
            lines.append("点对点链路（RFC 3021）")
            lines.append("可用范围：\(IPv4Address(network)) - \(IPv4Address(broadcast)) (2)")
        default:
            let total = UInt64(1) << UInt64(32 - prefix)
            lines.append("网络地址：\(IPv4Address(network))")
            lines.append("广播地址：\(IPv4Address(broadcast))")
            lines.append("可用范围：\(IPv4Address(network + 1)) - \(IPv4Address(broadcast - 1)) (\(total - 2))")
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
        let type = address.kind
        return [ParseResult(
            parserName: name,
            original: content,
            parsed: "类型：\(type)",
            details: "压缩：\(address.description)\n展开：\(address.expanded)\n类型：\(type)"
        )]
    }
}

struct IPParser: ContentParser {
    let name = "IP"

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard let address = IPv4Address(content), address.isPublic else { return [] }
        var parsed = "公网 IP"
        var details = "八位组：\(address.octets)\n二进制：\(address.octets.map { String($0, radix: 2).leftPadded(to: 8) }.joined(separator: "."))"
        if let info = IPGeo.lookup(content) {
            let lines = info.displayLines
            if !lines.isEmpty {
                parsed = lines.joined(separator: "\n")
                details += "\n\n地理位置信息：\n\(parsed)"
            }
        }
        return [ParseResult(parserName: "IPv4", original: content, parsed: parsed, details: details)]
    }
}

struct DNSParser: ContentParser {
    let name = "DNS"
    private let domainPattern = ParserUtilities.regex(#"^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#, options: [.caseInsensitive])

    func parse(_ content: String, previousContent: String) -> [ParseResult] {
        guard ParserUtilities.fullMatch(domainPattern, content) != nil else { return [] }
        let providers = [
            DNSProvider(name: "Cloudflare DoH", url: "https://cloudflare-dns.com/dns-query"),
            DNSProvider(name: "Google DoH", url: "https://dns.google/resolve"),
            DNSProvider(name: "AliDNS DoH", url: "https://dns.alidns.com/dns-query"),
        ]
        let queryTypes: [(UInt16, String)] = [(1, "A"), (28, "AAAA"), (5, "CNAME")]
        return providers.flatMap { provider in
            queryTypes.compactMap { typeNumber, typeName in
                let answers = DNSLookup.query(domain: content, type: typeNumber, provider: provider)
                    .filter { $0.recordType == typeNumber }
                guard !answers.isEmpty else { return nil }
                let parsed = "DNS/\(typeName) via \(provider.name)\n\(answers.map(\.data).joined(separator: "\n"))"
                return ParseResult(parserName: name, original: content, parsed: parsed)
            }
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
        if description == "::1" { return "回环地址 (::1)" }
        if description == "::" { return "未指定地址 (::)" }
        if (segments[0] & 0xffc0) == 0xfe80 { return "链路本地地址 (fe80::/10)" }
        if (segments[0] & 0xfe00) == 0xfc00 { return "唯一本地地址 (fc00::/7)" }
        if (segments[0] & 0xff00) == 0xff00 { return "多播地址 (ff00::/8)" }
        if segments[0...4].allSatisfy({ $0 == 0 }) && segments[5] == 0xffff {
            return "IPv4 映射地址 (::ffff:0:0/96)"
        }
        return "全局单播地址"
    }
}

private struct IPGeo: Decodable {
    let status: String
    let country: String?
    let city: String?
    let isp: String?
    let reverse: String?

    var displayLines: [String] {
        [
            country.flatMap { $0.isEmpty ? nil : "国家：\($0)" },
            city.flatMap { $0.isEmpty ? nil : "城市：\($0)" },
            isp.flatMap { $0.isEmpty ? nil : "ISP：\($0)" },
            reverse.flatMap { $0.isEmpty ? nil : "反向 DNS：\($0)" },
        ].compactMap { $0 }
    }

    static func lookup(_ ip: String) -> IPGeo? {
        guard let encoded = ip.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://ip-api.com/json/\(encoded)?fields=status,message,country,city,isp,reverse,query&lang=zh-CN")
        else { return nil }
        guard let data = BlockingHTTP.get(url: url, timeout: 3, headers: [:]),
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

    var recordType: UInt16 { type }
}

private enum DNSLookup {
    static func query(domain: String, type: UInt16, provider: DNSProvider) -> [DNSAnswer] {
        guard var components = URLComponents(string: provider.url) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "name", value: domain),
            URLQueryItem(name: "type", value: "\(type)"),
        ]
        guard let url = components.url,
              let data = BlockingHTTP.get(url: url, timeout: 3, headers: ["Accept": "application/dns-json"]),
              let response = try? JSONDecoder().decode(DNSResponse.self, from: data),
              response.Status == 0
        else { return [] }
        return response.Answer ?? []
    }
}

private enum BlockingHTTP {
    static func get(url: URL, timeout: TimeInterval, headers: [String: String]) -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var data: Data?
        }
        let box = Box()
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            box.data = data
            semaphore.signal()
        }
        task.resume()
        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            task.cancel()
            return nil
        }
        return box.data
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
