import Foundation

public struct ParserEngine: Sendable {
    private let parsers: [any ContentParser]

    public init() {
        self.parsers = [
            UUIDGenerator(),
            TimestampGenerator(),
            TimeGenerator(),
            ObjectIDGenerator(),
            Base64EncodeGenerator(),
            Base64DecodeGenerator(),
            PasswordGenerator(),
            CIDRParser(),
            UUIDParser(),
            ObjectIDParser(),
            HashParser(),
            IPv6Parser(),
            IPParser(),
            TimestampParser(),
            HTTPStatusParser(),
            NumberBaseParser(),
            CronParser(),
            URLParser(),
            JSONParser(),
            JSON5Parser(),
            XMLFormatParser(),
            TOMLParser(),
            YAMLParser(),
            HTMLEntityParser(),
            Base64Parser(),
            DNSParser(),
        ]
    }

    public var parserNames: [String] {
        parsers.map(\.name)
    }

    public var parserInfos: [ParserInfo] {
        parsers.map { ParserCatalog.info(for: $0.name) }
    }

    public func parse(
        _ content: String,
        previousContent: String = "",
        enabledParserNames: Set<String>? = nil
    ) -> ParseResult? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for parser in parsers {
            if let enabledParserNames, !enabledParserNames.contains(parser.name) {
                continue
            }
            if let first = parser.parse(trimmed, previousContent: previousContent).first {
                return first
            }
        }
        return nil
    }

    public func parseAll(
        _ content: String,
        previousContent: String = "",
        enabledParserNames: Set<String>? = nil
    ) -> [ParseResult] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return parsers.flatMap { parser in
            if let enabledParserNames, !enabledParserNames.contains(parser.name) {
                return [ParseResult]()
            }
            return parser.parse(trimmed, previousContent: previousContent)
        }
    }
}

public struct ParserInfo: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let zhDescription: String
    public let enDescription: String
    public let examples: [ParserExample]
}

public struct ParserExample: Identifiable, Codable, Equatable, Sendable {
    public var id: String { input }
    public let input: String
    public let zhExpected: String
    public let enExpected: String
}

enum ParserCatalog {
    static func info(for name: String) -> ParserInfo {
        table[name] ?? ParserInfo(
            name: name,
            zhDescription: "解析剪切板中的 \(name) 内容。",
            enDescription: "Parses \(name) content from the clipboard.",
            examples: []
        )
    }

    private static let table: [String: ParserInfo] = [
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
        "Base64": ParserInfo(name: "Base64", zhDescription: "识别并解码可打印 UTF-8 Base64 文本。", enDescription: "Recognizes and decodes printable UTF-8 Base64 text.", examples: [ex("aGVsbG8gd29ybGQ=", "输出 hello world。", "Outputs hello world.")]),
        "DNS": ParserInfo(name: "DNS", zhDescription: "识别域名并通过 DoH 查询 A、AAAA、CNAME 记录。", enDescription: "Recognizes domains and queries A, AAAA, and CNAME records via DoH.", examples: [ex("example.com", "输出 A/AAAA/CNAME 查询结果。", "Outputs A/AAAA/CNAME lookup results.")]),
    ]

    private static func ex(_ input: String, _ zhExpected: String, _ enExpected: String) -> ParserExample {
        ParserExample(input: input, zhExpected: zhExpected, enExpected: enExpected)
    }
}
