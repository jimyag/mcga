import Foundation

/// Fetches a URL for the network parsers; tests pass a stub so they run offline.
public typealias HTTPFetch = @Sendable (URLRequest) async -> Data?

public struct ParserEngine: Sendable {
    public static let maximumInputBytes = 256 * 1024

    public static let urlSessionFetch: HTTPFetch = { request in
        try? await URLSession.shared.data(for: request).0
    }

    private let parsers: [any ContentParser]
    private let language: ParserLanguage
    public let parserInfos: [ParserInfo]
    /// Categories keyed by the `parserName` that results carry.
    public let parserCategories: [String: ParserCategory]
    /// Problems in the custom parser config, for settings to show.
    public let customParserIssues: [String]

    /// A nil `customParserConfig` loads no custom parsers.
    public init(
        language: ParserLanguage = .zh,
        customParserConfig: URL? = ParserEngine.customParserConfigURL,
        fetch: @escaping HTTPFetch = ParserEngine.urlSessionFetch
    ) {
        let custom = Localization.$language.withValue(language) {
            customParserConfig.map(CustomCommandParser.load(from:)) ?? (parsers: [], issues: [])
        }
        let parsers: [any ContentParser] = [
            UUIDGenerator(),
            TimestampGenerator(),
            TimeGenerator(),
            ObjectIDGenerator(),
            Base64EncodeGenerator(),
            Base64DecodeGenerator(),
            PasswordGenerator(),
        ]
        + custom.parsers
        + [
            VideoDownloadParser(),
            JWTParser(),
            PEMCertificateParser(),
            SSHPublicKeyParser(),
            MACAddressParser(),
            CIDRParser(),
            UUIDParser(),
            ObjectIDParser(),
            HashParser(),
            IPv6Parser(),
            IPParser(fetch: fetch),
            TimestampParser(),
            HTTPStatusParser(),
            NumberBaseParser(),
            DataSizeParser(),
            DataRateParser(),
            CronParser(),
            URLParser(),
            JSONParser(),
            JSON5Parser(),
            XMLFormatParser(),
            TOMLParser(),
            YAMLParser(),
            HTMLEntityParser(),
            UnicodeEscapeParser(),
            Base64Parser(),
            DNSParser(fetch: fetch),
        ]
        let infos = parsers.map { $0.info ?? ParserCatalog.info(for: $0.name) }
        var categories = Dictionary(infos.map { ($0.name, $0.category) }, uniquingKeysWith: { first, _ in first })
        // Older history entries label IP results "IPv4".
        categories["IPv4"] = .network
        self.parsers = parsers
        self.language = language
        self.parserInfos = infos
        self.parserCategories = categories
        self.customParserIssues = custom.issues
    }

    public var parserNames: [String] {
        parsers.map(\.name)
    }

    public static var customParserConfigURL: URL {
        CustomCommandParser.configURL
    }

    /// Local parsers answer at once; slow ones (network lookups, commands) then run concurrently.
    /// The stream starts with the local results and adds each slow parser's results as they
    /// arrive. Every element is the full list so far, in parser order.
    public func results(
        for content: String,
        previousContent: String = "",
        enabledParserNames: Set<String>? = nil
    ) -> AsyncStream<[ParseResult]> {
        let trimmed = content.mcgaTrimmed
        let previousContent = Self.canParse(previousContent) ? previousContent : ""
        let active = Self.canParse(content) && !trimmed.isEmpty
            ? parsers.indices.filter { enabledParserNames?.contains(parsers[$0].name) ?? true }
            : []
        let (stream, continuation) = AsyncStream.makeStream(of: [ParseResult].self)
        let task = Task { [parsers, language] in
            await Localization.$language.withValue(language) {
                var found = [[ParseResult]](repeating: [], count: parsers.count)
                for index in active where !parsers[index].isSlow {
                    found[index] = await parsers[index].parse(trimmed, previousContent: previousContent)
                }
                continuation.yield(found.flatMap { $0 })
                await withTaskGroup(of: (Int, [ParseResult]).self) { group in
                    for index in active where parsers[index].isSlow {
                        group.addTask { (index, await parsers[index].parse(trimmed, previousContent: previousContent)) }
                    }
                    for await (index, results) in group where !results.isEmpty {
                        found[index] = results
                        continuation.yield(found.flatMap { $0 })
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// The final list of `results(for:)`.
    public func parseAll(
        _ content: String,
        previousContent: String = "",
        enabledParserNames: Set<String>? = nil
    ) async -> [ParseResult] {
        var all: [ParseResult] = []
        for await update in results(for: content, previousContent: previousContent, enabledParserNames: enabledParserNames) {
            all = update
        }
        return all
    }

    public static func canParse(_ content: String) -> Bool {
        content.utf8.count <= maximumInputBytes
    }
}

public struct ParserInfo: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let zhDescription: String
    public let enDescription: String
    public let examples: [ParserExample]
    public var category: ParserCategory = .text
}

/// Declaration order is the order parsers are grouped in settings.
public enum ParserCategory: String, CaseIterable, Codable, Sendable {
    case custom
    case generator
    case identifier
    case network
    case time
    case dataFormat
    case text

    /// Whether results read as "label：value" facts; generated values, formatted data and
    /// decoded text stay verbatim.
    public var showsFields: Bool {
        switch self {
        case .custom, .identifier, .network, .time: true
        case .generator, .dataFormat, .text: false
        }
    }

    /// The whole of a result, as copying and pasting take it. Custom commands keep only their first
    /// stdout line in `parsed` and all of it in details, and formatted data parsers describe the
    /// input in `parsed` and keep the formatted text in details.
    public func content(parsed: String, details: String?) -> String {
        switch self {
        case .custom, .dataFormat: details ?? parsed
        default: parsed
        }
    }
}

public struct ParserExample: Identifiable, Codable, Equatable, Sendable {
    public var id: String { input }
    public let input: String
    public let zhExpected: String
    public let enExpected: String
}

enum ParserCatalog {
    static func info(for name: String) -> ParserInfo {
        var info = table[name] ?? ParserInfo(
            name: name,
            zhDescription: "解析剪切板中的 \(name) 内容。",
            enDescription: "Parses \(name) content from the clipboard.",
            examples: []
        )
        info.category = categories[name] ?? .text
        return info
    }

    private static let categories: [String: ParserCategory] = [
        "UUID Generator": .generator,
        "Timestamp Generator": .generator,
        "Time Generator": .generator,
        "ObjectID Generator": .generator,
        "Base64 Encode": .generator,
        "Base64 Decode": .generator,
        "Password Generator": .generator,
        "UUID": .identifier,
        "ObjectID": .identifier,
        "Hash": .identifier,
        "Number Base": .identifier,
        "JWT": .identifier,
        "PEM Certificate": .identifier,
        "SSH Public Key": .identifier,
        "MAC Address": .network,
        "Data Size": .identifier,
        "Data Rate": .identifier,
        "Video Download": .network,
        "HTTP Status": .identifier,
        "CIDR": .network,
        "IPv6": .network,
        "IP": .network,
        "DNS": .network,
        "URL": .network,
        "Timestamp": .time,
        "Cron": .time,
        "JSON": .dataFormat,
        "JSON5": .dataFormat,
        "XML": .dataFormat,
        "TOML": .dataFormat,
        "YAML": .dataFormat,
        "HTML Entity": .text,
        "Unicode Escape": .text,
        "Base64": .text,
    ]

    private static let table: [String: ParserInfo] = [
        "Video Download": ParserInfo(name: "Video Download", zhDescription: "解析视频信息并提供预览，确认有视频后可下载最高画质到 Downloads。", enDescription: "Resolves video metadata with a preview; confirmed videos can be downloaded at the best quality to Downloads.", examples: [ex("https://www.bilibili.com/video/BV1xx411c7mD", "先解析视频信息，成功后显示预览和下载按钮。", "Resolves video metadata before showing preview and download controls.")]),
        "Data Rate": ParserInfo(name: "Data Rate", zhDescription: "本地换算带宽和传输速率，区分 Mbps/Gbps、MB/s、MiB/s，1 Byte = 8 bit。", enDescription: "Locally converts bandwidth and transfer rates, distinguishing Mbps/Gbps, MB/s, and MiB/s; 1 byte = 8 bits.", examples: [ex("100 Mbps", "输出 12.5 MB/s 和 11.9209289551 MiB/s 等。", "Shows 12.5 MB/s, 11.9209289551 MiB/s, and more.")]),
        "JWT": ParserInfo(name: "JWT", zhDescription: "本地解码 JWT 的 Header、Payload 和时间声明，不验证签名。", enDescription: "Locally decodes JWT headers, payloads, and time claims without verifying signatures.", examples: [ex("eyJhbGciOiJub25lIn0.eyJzdWIiOiJkZW1vIn0.", "输出 Header、Payload，并标注未验证签名。", "Shows header and payload with an unverified-signature label.")]),
        "Data Size": ParserInfo(name: "Data Size", zhDescription: "换算 bit/Byte 和 kB/MB、KiB/MiB 等单位。无单位的非负数字按字节换算，结果最多 12 位有效数字。", enDescription: "Converts bits, bytes, decimal and binary sizes. Unitless nonnegative numbers are bytes; results use up to 12 significant digits.", examples: [ex("1048576", "按字节换算，输出 1 MiB、1.048576 MB 等。", "Interprets bytes and shows 1 MiB, 1.048576 MB, and more."), ex("8 Mb", "区分位和字节，输出 1 MB。", "Distinguishes bits from bytes and shows 1 MB.")]),
        "PEM Certificate": ParserInfo(name: "PEM Certificate", zhDescription: "本地解析 PEM X.509 证书或证书链的主体、签发者、有效期、备用名称和 SHA-256 指纹，不验证信任链。", enDescription: "Locally reads PEM X.509 certificates or chains: subject, issuer, validity, SANs, and SHA-256 fingerprints. Does not verify trust.", examples: []),
        "SSH Public Key": ParserInfo(name: "SSH Public Key", zhDescription: "解析 OpenSSH 格式的 RSA、DSA、ECDSA、Ed25519 公钥，显示类型、位数、SHA256 指纹和注释。", enDescription: "Reads OpenSSH RSA, DSA, ECDSA, and Ed25519 public keys: type, bits, SHA256 fingerprint, and comment.", examples: []),
        "MAC Address": ParserInfo(name: "MAC Address", zhDescription: "识别冒号、短横线、点分或连续十六进制 MAC 地址，输出标准形式及单播/组播、全局/本地管理属性。", enDescription: "Normalizes colon, hyphen, dotted, or compact MAC addresses and shows unicast/multicast and universal/local administration.", examples: [ex("02:11:22:33:44:55", "输出标准地址、单播和本地管理属性。", "Shows the normalized address, unicast, and local administration.")]),
        "UUID Generator": ParserInfo(name: "UUID Generator", zhDescription: "输入 uuid 生成 UUID v7。", enDescription: "Generates a UUID v7 from the keyword uuid.", examples: [ex("uuid", "输出一个新的 UUID v7。", "Outputs a new UUID v7.")]),
        "Timestamp Generator": ParserInfo(name: "Timestamp Generator", zhDescription: "输入 ts 或 timestamp 生成当前秒级时间戳。", enDescription: "Generates the current Unix timestamp from ts or timestamp.", examples: [ex("ts", "输出当前 Unix 秒级时间戳。", "Outputs current Unix timestamp in seconds.")]),
        "Time Generator": ParserInfo(name: "Time Generator", zhDescription: "输入 time 生成当前 RFC3339 时间。", enDescription: "Generates current RFC3339 time from time.", examples: [ex("time", "输出当前 RFC3339 时间。", "Outputs current RFC3339 time.")]),
        "ObjectID Generator": ParserInfo(name: "ObjectID Generator", zhDescription: "输入 objectid 或 oid 生成 MongoDB ObjectID。", enDescription: "Generates a MongoDB ObjectID from objectid or oid.", examples: [ex("objectid", "输出一个新的 24 位 ObjectID。", "Outputs a new 24-character ObjectID.")]),
        "Base64 Encode": ParserInfo(name: "Base64 Encode", zhDescription: "输入 b64，对上一条剪切板内容做 Base64 编码。", enDescription: "Encodes previous clipboard text as Base64 when b64 is copied.", examples: [ex("上一条剪切板：hello world\n当前剪切板：b64", "输出 aGVsbG8gd29ybGQ=。", "Outputs aGVsbG8gd29ybGQ=.")]),
        "Base64 Decode": ParserInfo(name: "Base64 Decode", zhDescription: "输入 db64，对上一条剪切板内容做 Base64 解码。", enDescription: "Decodes previous clipboard Base64 text when db64 is copied.", examples: [ex("上一条剪切板：aGVsbG8gd29ybGQ=\n当前剪切板：db64", "输出 hello world。", "Outputs hello world.")]),
        "Password Generator": ParserInfo(name: "Password Generator", zhDescription: "输入 pswd 或 pswd N 生成随机密码。", enDescription: "Generates a random password from pswd or pswd N.", examples: [ex("pswd 32", "输出 32 位随机密码。", "Outputs a 32-character random password.")]),
        "CIDR": ParserInfo(name: "CIDR", zhDescription: "解析 IPv4 CIDR 网段、网络地址、广播地址和可用范围。", enDescription: "Parses IPv4 CIDR networks, broadcast address, and usable range.", examples: [ex("192.168.1.20/24", "输出网络地址 192.168.1.0、广播地址和可用范围。", "Outputs network address 192.168.1.0, broadcast address, and usable range.")]),
        "UUID": ParserInfo(name: "UUID", zhDescription: "解析 UUID 版本、变体，以及 v1/v6/v7 中的时间信息。", enDescription: "Parses UUID version, variant, and timestamp for v1/v6/v7.", examples: [ex("550e8400-e29b-41d4-a716-446655440000", "输出 UUID 版本、变体和大写/URN 形式。", "Outputs UUID version, variant, uppercase form, and URN.")]),
        "ObjectID": ParserInfo(name: "ObjectID", zhDescription: "解析 MongoDB ObjectID 的创建时间、随机值和计数器。", enDescription: "Parses MongoDB ObjectID creation time, random bytes, and counter.", examples: [ex("507f1f77bcf86cd799439011", "输出创建时间、随机值和计数器。", "Outputs creation time, random bytes, and counter.")]),
        "Hash": ParserInfo(name: "Hash", zhDescription: "按十六进制长度识别 MD5、SHA-1、SHA-256 等摘要。", enDescription: "Identifies common hex digest algorithms by length.", examples: [ex("d41d8cd98f00b204e9800998ecf8427e", "输出类型 MD5 和摘要长度。", "Outputs MD5 and digest length.")]),
        "IPv6": ParserInfo(name: "IPv6", zhDescription: "解析 IPv6 地址类型、压缩格式和展开格式。", enDescription: "Parses IPv6 address type, compressed form, and expanded form.", examples: [ex("2001:db8::1", "输出地址类型、压缩格式和展开格式。", "Outputs address type, compressed form, and expanded form.")]),
        "IP": ParserInfo(name: "IP", zhDescription: "识别公网 IPv4，并尝试查询地理位置。", enDescription: "Recognizes public IPv4 addresses and looks up geolocation.", examples: [ex("8.8.8.8", "输出公网 IP 信息，网络可用时包含地理位置。", "Outputs public IP info and geolocation when available.")]),
        "Timestamp": ParserInfo(name: "Timestamp", zhDescription: "解析 10/13/16/17/19 位 Unix 时间戳。", enDescription: "Parses 10/13/16/17/19 digit Unix timestamps.", examples: [ex("1700000000", "输出精度为秒和对应 UTC 时间。", "Outputs seconds precision and corresponding UTC time.")]),
        "HTTP Status": ParserInfo(name: "HTTP Status", zhDescription: "解释常见 HTTP 状态码。", enDescription: "Explains common HTTP status codes.", examples: [ex("404", "输出 404 Not Found，类型为客户端错误。", "Outputs 404 Not Found as a client error.")]),
        "Number Base": ParserInfo(name: "Number Base", zhDescription: "在二进制、八进制、十进制、十六进制之间转换整数。", enDescription: "Converts integers between binary, octal, decimal, and hexadecimal.", examples: [ex("0xff", "输出 DEC 255、HEX 0xFF、OCT 0o377、BIN 0b11111111。", "Outputs DEC 255, HEX 0xFF, OCT 0o377, and BIN 0b11111111.")]),
        "Cron": ParserInfo(name: "Cron", zhDescription: "解释 5 或 6 字段 Cron 表达式和常见宏。", enDescription: "Explains 5/6-field cron expressions and common macros.", examples: [ex("*/5 * * * *", "输出每 5 分钟等字段解释。", "Outputs field explanations such as every 5 minutes.")]),
        "URL": ParserInfo(name: "URL", zhDescription: "拆解 URL 的 scheme、host、path、fragment 和 query 参数。", enDescription: "Breaks down URL scheme, host, path, fragment, and query parameters.", examples: [ex("https://example.com/a?x=1&name=mcga", "输出 scheme、host、path 和 query 参数表。", "Outputs scheme, host, path, and query parameters.")]),
        "JSON": ParserInfo(name: "JSON", zhDescription: "识别并格式化严格 JSON 对象或数组。", enDescription: "Recognizes and pretty-prints strict JSON objects or arrays.", examples: [ex("{\"hello\":\"world\"}", "输出格式化后的 JSON。", "Outputs pretty-printed JSON.")]),
        "JSON5": ParserInfo(name: "JSON5", zhDescription: "识别常见 JSON5/JSONC 写法，包括注释和 trailing comma。", enDescription: "Recognizes common JSON5/JSONC forms such as comments and trailing commas.", examples: [ex("{hello: \"world\",}", "输出转换后的格式化 JSON。", "Outputs normalized pretty-printed JSON.")]),
        "XML": ParserInfo(name: "XML", zhDescription: "识别并格式化 XML，展示根节点。", enDescription: "Recognizes and pretty-prints XML, showing the root element.", examples: [ex("<root><item>1</item></root>", "输出 Root: root 和格式化 XML。", "Outputs Root: root and formatted XML.")]),
        "TOML": ParserInfo(name: "TOML", zhDescription: "识别并轻量格式化 TOML 配置片段。", enDescription: "Recognizes and lightly formats TOML snippets.", examples: [ex("name = \"mcga\"\ncount = 1", "输出 TOML 大小和格式化后的键值。", "Outputs TOML size and formatted key-value lines.")]),
        "YAML": ParserInfo(name: "YAML", zhDescription: "识别 YAML map 或 sequence 并格式化。", enDescription: "Recognizes and formats YAML maps or sequences.", examples: [ex("hello: world\ncount: 1", "输出 YAML 类型和格式化内容。", "Outputs YAML type and formatted content.")]),
        "HTML Entity": ParserInfo(name: "HTML Entity", zhDescription: "解码 HTML entities，包括命名实体、十进制和十六进制数字实体。", enDescription: "Decodes named, decimal, and hexadecimal HTML entities.", examples: [ex("hello &amp; world", "输出 hello & world。", "Outputs hello & world.")]),
        "Unicode Escape": ParserInfo(name: "Unicode Escape", zhDescription: "解码 \\uXXXX、\\u{XXXX} Unicode 转义为 UTF-8 文本。", enDescription: "Decodes \\uXXXX and \\u{XXXX} Unicode escapes into UTF-8 text.", examples: [ex("\\u4F60\\u597D", "输出 你好。", "Outputs 你好.")]),
        "Base64": ParserInfo(name: "Base64", zhDescription: "识别并解码可打印 UTF-8 Base64 文本。", enDescription: "Recognizes and decodes printable UTF-8 Base64 text.", examples: [ex("aGVsbG8gd29ybGQ=", "输出 hello world。", "Outputs hello world.")]),
        "DNS": ParserInfo(name: "DNS", zhDescription: "识别域名并通过 DoH 查询 A、AAAA、CNAME 记录。", enDescription: "Recognizes domains and queries A, AAAA, and CNAME records via DoH.", examples: [ex("example.com", "输出 A/AAAA/CNAME 查询结果。", "Outputs A/AAAA/CNAME lookup results.")]),
    ]

    private static func ex(_ input: String, _ zhExpected: String, _ enExpected: String) -> ParserExample {
        ParserExample(input: input, zhExpected: zhExpected, enExpected: enExpected)
    }
}
