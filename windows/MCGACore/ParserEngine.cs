using System;
using System.Collections.Generic;
using System.Linq;

namespace MCGA.MCGACore
{
    public class ParserEngine
    {
        private readonly List<IContentParser> _parsers;

        public ParserEngine()
        {
            _parsers = new List<IContentParser>
            {
                new UUIDGenerator(),
                new TimestampGenerator(),
                new TimeGenerator(),
                new ObjectIDGenerator(),
                new Base64EncodeGenerator(),
                new Base64DecodeGenerator(),
                new PasswordGenerator()
            };

            _parsers.AddRange(CustomCommandParser.Load());

            _parsers.AddRange(new IContentParser[]
            {
                new CIDRParser(),
                new UUIDParser(),
                new ObjectIDParser(),
                new HashParser(),
                new IPv6Parser(),
                new IPParser(),
                new TimestampParser(),
                new HTTPStatusParser(),
                new NumberBaseParser(),
                new CronParser(),
                new URLParser(),
                new JSONParser(),
                new JSON5Parser(),
                new XMLFormatParser(),
                new TOMLParser(),
                new YAMLParser(),
                new HTMLEntityParser(),
                new Base64Parser(),
                new DNSParser()
            });
        }

        public List<string> ParserNames => _parsers.Select(p => p.Name).ToList();

        public List<ParserInfo> ParserInfos => _parsers.Select(p => p.Info ?? ParserCatalog.GetInfo(p.Name)).ToList();

        public ParseResult? Parse(string content, string previousContent = "", HashSet<string>? enabledParserNames = null)
        {
            string trimmed = content.Trim();
            if (string.IsNullOrEmpty(trimmed)) return null;

            foreach (var parser in _parsers)
            {
                if (enabledParserNames != null && !enabledParserNames.Contains(parser.Name))
                {
                    continue;
                }
                var results = parser.Parse(trimmed, previousContent);
                if (results.Count > 0)
                {
                    return results[0];
                }
            }
            return null;
        }

        public List<ParseResult> ParseAll(string content, string previousContent = "", HashSet<string>? enabledParserNames = null)
        {
            string trimmed = content.Trim();
            if (string.IsNullOrEmpty(trimmed)) return new List<ParseResult>();

            var allResults = new List<ParseResult>();
            foreach (var parser in _parsers)
            {
                if (enabledParserNames != null && !enabledParserNames.Contains(parser.Name))
                {
                    continue;
                }
                allResults.AddRange(parser.Parse(trimmed, previousContent));
            }
            return allResults;
        }
    }

    public static class ParserCatalog
    {
        public static ParserInfo GetInfo(string name)
        {
            if (Table.TryGetValue(name, out var info))
            {
                return info;
            }
            return new ParserInfo(
                name,
                $"解析剪切板中的 {name} 内容。",
                $"Parses {name} content from the clipboard.",
                new List<ParserExample>()
            );
        }

        private static ParserExample Ex(string input, string zh, string en)
        {
            return new ParserExample(input, zh, en);
        }

        private static readonly Dictionary<string, ParserInfo> Table = new Dictionary<string, ParserInfo>(StringComparer.OrdinalIgnoreCase)
        {
            { "UUID Generator", new ParserInfo("UUID Generator", "输入 uuid 生成 UUID v7。", "Generates a UUID v7 from the keyword uuid.", new List<ParserExample> { Ex("uuid", "输出一个新的 UUID v7。", "Outputs a new UUID v7.") }) },
            { "Timestamp Generator", new ParserInfo("Timestamp Generator", "输入 ts 或 timestamp 生成当前秒级时间戳。", "Generates the current Unix timestamp from ts or timestamp.", new List<ParserExample> { Ex("ts", "输出当前 Unix 秒级时间戳。", "Outputs current Unix timestamp in seconds.") }) },
            { "Time Generator", new ParserInfo("Time Generator", "输入 time 生成当前 RFC3339 时间。", "Generates current RFC3339 time from time.", new List<ParserExample> { Ex("time", "输出当前 RFC3339 时间。", "Outputs current RFC3339 time.") }) },
            { "ObjectID Generator", new ParserInfo("ObjectID Generator", "输入 objectid 或 oid 生成 MongoDB ObjectID。", "Generates a MongoDB ObjectID from objectid or oid.", new List<ParserExample> { Ex("objectid", "输出一个新的 24 位 ObjectID。", "Outputs a new 24-character ObjectID.") }) },
            { "Base64 Encode", new ParserInfo("Base64 Encode", "输入 b64，对上一条剪切板内容做 Base64 编码。", "Encodes previous clipboard text as Base64 when b64 is copied.", new List<ParserExample> { Ex("上一条剪切板：hello world\n当前剪切板：b64", "输出 aGVsbG8gd29ybGQ=。", "Outputs aGVsbG8gd29ybGQ=.") }) },
            { "Base64 Decode", new ParserInfo("Base64 Decode", "输入 db64，对上一条剪切板内容做 Base64 解码。", "Decodes previous clipboard Base64 text when db64 is copied.", new List<ParserExample> { Ex("上一条剪切板：aGVsbG8gd29ybGQ=\n当前剪切板：db64", "输出 hello world。", "Outputs hello world.") }) },
            { "Password Generator", new ParserInfo("Password Generator", "输入 pswd 或 pswd N 生成随机密码。", "Generates a random password from pswd or pswd N.", new List<ParserExample> { Ex("pswd 32", "输出 32 位随机密码。", "Outputs a 32-character random password.") }) },
            { "CIDR", new ParserInfo("CIDR", "解析 IPv4 CIDR 网段、网络地址、广播地址和可用范围。", "Parses IPv4 CIDR networks, broadcast address, and usable range.", new List<ParserExample> { Ex("192.168.1.20/24", "输出网络地址 192.168.1.0、广播地址和可用范围。", "Outputs network address 192.168.1.0, broadcast address, and usable range.") }) },
            { "UUID", new ParserInfo("UUID", "解析 UUID 版本、变体，以及 v1/v6/v7 中的时间信息。", "Parses UUID version, variant, and timestamp for v1/v6/v7.", new List<ParserExample> { Ex("550e8400-e29b-41d4-a716-446655440000", "输出 UUID 版本、变体和大写/URN 形式。", "Outputs UUID version, variant, uppercase form, and UCN.") }) },
            { "ObjectID", new ParserInfo("ObjectID", "解析 MongoDB ObjectID 的创建时间、随机值和计数器。", "Parses MongoDB ObjectID creation time, random bytes, and counter.", new List<ParserExample> { Ex("507f1f77bcf86cd799439011", "输出创建时间、随机值和计数器。", "Outputs creation time, random bytes, and counter.") }) },
            { "Hash", new ParserInfo("Hash", "按十六进制长度识别 MD5、SHA-1、SHA-256 等摘要。", "Identifies common hex digest algorithms by length.", new List<ParserExample> { Ex("d41d8cd98f00b204e9800998ecf8427e", "输出类型 MD5 和摘要长度。", "Outputs MD5 and digest length.") }) },
            { "IPv6", new ParserInfo("IPv6", "解析 IPv6 地址类型、压缩格式和展开格式。", "Parses IPv6 address type, compressed form, and expanded form.", new List<ParserExample> { Ex("2001:db8::1", "输出地址类型、压缩格式和展开格式。", "Outputs address type, compressed form, and expanded form.") }) },
            { "IP", new ParserInfo("IP", "识别公网 IPv4，并尝试查询地理位置。", "Recognizes public IPv4 addresses and looks up geolocation.", new List<ParserExample> { Ex("8.8.8.8", "输出公网 IP 信息，网络可用时包含地理位置。", "Outputs public IP info and geolocation when available.") }) },
            { "Timestamp", new ParserInfo("Timestamp", "解析 10/13/16/17/19 位 Unix 时间戳。", "Parses 10/13/16/17/19 digit Unix timestamps.", new List<ParserExample> { Ex("1700000000", "输出精度为秒和对应 UTC 时间。", "Outputs seconds precision and corresponding UTC time.") }) },
            { "HTTP Status", new ParserInfo("HTTP Status", "解释常见 HTTP 状态码。", "Explains common HTTP status codes.", new List<ParserExample> { Ex("404", "输出 404 Not Found，类型为客户端错误。", "Outputs 404 Not Found as a client error.") }) },
            { "Number Base", new ParserInfo("Number Base", "在二进制、八进制、十进制、十六进制之间转换整数。", "Converts integers between binary, octal, decimal, and hexadecimal.", new List<ParserExample> { Ex("0xff", "输出 DEC 255、HEX 0xFF、OCT 0o377、BIN 0b11111111。", "Outputs DEC 255, HEX 0xFF, OCT 0o377, and BIN 0b11111111.") }) },
            { "Cron", new ParserInfo("Cron", "解释 5 或 6 字段 Cron 表达式和常见宏。", "Explains 5/6-field cron expressions and common macros.", new List<ParserExample> { Ex("*/5 * * * *", "输出每 5 分钟等字段解释。", "Outputs field explanations such as every 5 minutes.") }) },
            { "URL", new ParserInfo("URL", "拆解 URL 的 scheme、host、path、fragment 和 query 参数。", "Breaks down URL scheme, host, path, fragment, and query parameters.", new List<ParserExample> { Ex("https://example.com/a?x=1&name=mcga", "输出 scheme、host、path 和 query 参数表。", "Outputs scheme, host, path, and query parameters.") }) },
            { "JSON", new ParserInfo("JSON", "识别并格式化严格 JSON 对象或数组。", "Recognizes and pretty-prints strict JSON objects or arrays.", new List<ParserExample> { Ex("{\"hello\":\"world\"}", "输出格式化后的 JSON。", "Outputs pretty-printed JSON.") }) },
            { "JSON5", new ParserInfo("JSON5", "识别常见 JSON5/JSONC 写法，包括注释和 trailing comma。", "Recognizes common JSON5/JSONC forms such as comments and trailing commas.", new List<ParserExample> { Ex("{hello: \"world\",}", "输出转换后的格式化 JSON。", "Outputs normalized pretty-printed JSON.") }) },
            { "XML", new ParserInfo("XML", "识别并格式化 XML，展示根节点。", "Recognizes and pretty-prints XML, showing the root element.", new List<ParserExample> { Ex("<root><item>1</item></root>", "输出 Root: root 和格式化 XML。", "Outputs Root: root and formatted XML.") }) },
            { "TOML", new ParserInfo("TOML", "识别并轻量格式化 TOML 配置片段。", "Recognizes and lightly formats TOML snippets.", new List<ParserExample> { Ex("name = \"mcga\"\ncount = 1", "输出 TOML 大小和格式化后的键值。", "Outputs TOML size and formatted key-value lines.") }) },
            { "YAML", new ParserInfo("YAML", "识别 YAML map 或 sequence 并格式化。", "Recognizes and formats YAML maps or sequences.", new List<ParserExample> { Ex("hello: world\ncount: 1", "输出 YAML 类型和格式化内容。", "Outputs YAML type and formatted content.") }) },
            { "HTML Entity", new ParserInfo("HTML Entity", "解码 HTML entities，包括命名实体、十进制和十六进制数字实体。", "Decodes named, decimal, and hexadecimal HTML entities.", new List<ParserExample> { Ex("hello &amp; world", "输出 hello & world。", "Outputs hello & world.") }) },
            { "Base64", new ParserInfo("Base64", "识别并解码可打印 UTF-8 Base64 文本。", "Recognizes and decodes printable UTF-8 Base64 text.", new List<ParserExample> { Ex("aGVsbG8gd29ybGQ=", "输出 hello world。", "Outputs hello world.") }) },
            { "DNS", new ParserInfo("DNS", "识别域名并通过 DoH 查询 A、AAAA、CNAME 记录。", "Recognizes domains and queries A, AAAA, and CNAME records via DoH.", new List<ParserExample> { Ex("example.com", "输出 A/AAAA/CNAME 查询结果。", "Outputs A/AAAA/CNAME lookup results.") }) }
        };
    }
}
