using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace MCGA.MCGACore
{
    public class UUIDParser : IContentParser
    {
        public string Name => "UUID";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (!content.Contains("-") || !Guid.TryParse(content, out var guid)) return new List<ParseResult>();

            byte[] guidBytes = guid.ToByteArray();
            byte[] bytes = new byte[16];
            // Convert to Big-Endian Network Byte Order (RFC 4122)
            bytes[0] = guidBytes[3];
            bytes[1] = guidBytes[2];
            bytes[2] = guidBytes[1];
            bytes[3] = guidBytes[0];
            bytes[4] = guidBytes[5];
            bytes[5] = guidBytes[4];
            bytes[6] = guidBytes[7];
            bytes[7] = guidBytes[6];
            Array.Copy(guidBytes, 8, bytes, 8, 8);

            int version = (bytes[6] & 0xf0) >> 4;
            string versionInfo = GetVersionDescription(version);
            string variantInfo = GetVariantDescription(bytes[8]);

            ulong high = 0;
            for (int i = 0; i < 8; i++) high = (high << 8) | bytes[i];
            ulong low = 0;
            for (int i = 8; i < 16; i++) low = (low << 8) | bytes[i];

            string details = $"版本：{versionInfo}\n" +
                             $"变体：{variantInfo}\n" +
                             $"大写：{guid.ToString().ToUpperInvariant()}\n" +
                             $"URN: urn:uuid:{guid.ToString().ToLowerInvariant()}\n" +
                             $"高 64 位：0x{high:x16}\n" +
                             $"低 64 位：0x{low:x16}";

            string timeInfo = "";
            var date = GetUuidTime(version, bytes);
            if (date.HasValue)
            {
                string formatted = ParserUtilities.UtcString(date.Value);
                timeInfo = $"\n创建时间：{formatted}";
                details += $"\n\n时间信息:\n  创建时间：{formatted}\n  ISO 8601: {ParserUtilities.IsoString(date.Value)}";
                if (version == 1)
                {
                    string mac = string.Join(":", bytes.Skip(10).Take(6).Select(b => b.ToString("x2")));
                    details += $"\n\n节点信息:\n  MAC 地址：{mac}";
                    if ((bytes[10] & 0x01) == 0x01)
                    {
                        details += " (随机生成)";
                    }
                }
            }
            else if (version == 2 || version == 3 || version == 4 || version == 5 || version == 8)
            {
                timeInfo = "\n时间信息：无 (该版本不包含时间戳)";
                details += "\n\n时间信息：该版本不包含时间戳";
            }
            else
            {
                timeInfo = "\n时间信息：无法解析";
            }

            return new List<ParseResult>
            {
                new ParseResult(Name, content, $"{versionInfo}{timeInfo}", details)
            };
        }

        private string GetVersionDescription(int version)
        {
            return version switch
            {
                1 => "v1 (基于时间和 MAC 地址)",
                2 => "v2 (DCE Security)",
                3 => "v3 (基于 MD5 哈希)",
                4 => "v4 (随机生成)",
                5 => "v5 (基于 SHA-1 哈希)",
                6 => "v6 (有序时间戳)",
                7 => "v7 (Unix 时间戳)",
                8 => "v8 (自定义)",
                _ => "未知版本"
            };
        }

        private string GetVariantDescription(byte byteValue)
        {
            if ((byteValue & 0x80) == 0) return "NCS 向后兼容";
            if ((byteValue & 0xc0) == 0x80) return "RFC 4122";
            if ((byteValue & 0xe0) == 0xc0) return "Microsoft 向后兼容";
            return "保留给未来定义";
        }

        private DateTime? GetUuidTime(int version, byte[] bytes)
        {
            const ulong uuidEpochDiff = 122192928000000000UL;
            ulong timestamp = 0;
            switch (version)
            {
                case 1:
                    ulong timeLow = ((ulong)bytes[0] << 24) | ((ulong)bytes[1] << 16) | ((ulong)bytes[2] << 8) | bytes[3];
                    ulong timeMid = ((ulong)bytes[4] << 8) | bytes[5];
                    ulong timeHigh = (((ulong)bytes[6] << 8) | bytes[7]) & 0x0fffUL;
                    timestamp = timeLow | (timeMid << 32) | (timeHigh << 48);
                    break;
                case 6:
                    ulong high = ((ulong)bytes[0] << 24) | ((ulong)bytes[1] << 16) | ((ulong)bytes[2] << 8) | bytes[3];
                    ulong mid = ((ulong)bytes[4] << 8) | bytes[5];
                    ulong low = (((ulong)bytes[6] << 8) | bytes[7]) & 0x0fffUL;
                    timestamp = (high << 28) | (mid << 12) | low;
                    break;
                case 7:
                    ulong millis = 0;
                    for (int i = 0; i < 6; i++) millis = (millis << 8) | bytes[i];
                    return DateTimeOffset.FromUnixTimeMilliseconds((long)millis).UtcDateTime;
                default:
                    return null;
            }

            if (timestamp < uuidEpochDiff) return null;
            ulong unix100ns = timestamp - uuidEpochDiff;
            double seconds = (double)unix100ns / 10000000.0;
            return DateTimeOffset.FromUnixTimeSeconds(0).AddSeconds(seconds).UtcDateTime;
        }
    }

    public class ObjectIDParser : IContentParser
    {
        public string Name => "ObjectID";
        public ParserInfo? Info => null;
        private readonly Regex _pattern = ParserUtilities.GetRegex(@"^[0-9a-fA-F]{24}$");

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (ParserUtilities.FullMatch(_pattern, content) == null) return new List<ParseResult>();

            byte[] bytes = new byte[12];
            for (int i = 0; i < 12; i++)
            {
                bytes[i] = byte.Parse(content.Substring(i * 2, 2), NumberStyles.HexNumber);
            }

            uint seconds = ((uint)bytes[0] << 24) | ((uint)bytes[1] << 16) | ((uint)bytes[2] << 8) | bytes[3];
            var date = DateTimeOffset.FromUnixTimeSeconds(seconds).UtcDateTime;
            string random = ParserUtilities.Hex(bytes.Skip(4).Take(5).ToArray());
            uint counter = ((uint)bytes[9] << 16) | ((uint)bytes[10] << 8) | bytes[11];

            return new List<ParseResult>
            {
                new ParseResult(
                    Name,
                    content,
                    $"创建时间: {ParserUtilities.UtcSecondString(date)}\n随机值: {random}\n计数器: {counter}",
                    $"时间戳: {seconds}\nISO 8601: {ParserUtilities.IsoString(date)}"
                )
            };
        }
    }

    public class HashParser : IContentParser
    {
        public string Name => "Hash";
        public ParserInfo? Info => null;
        private readonly Regex _pattern = ParserUtilities.GetRegex(@"^[0-9a-fA-F]+$");

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (ParserUtilities.FullMatch(_pattern, content) == null) return new List<ParseResult>();

            string kind = content.Length switch
            {
                32 => "MD5",
                40 => "SHA-1",
                56 => "SHA-224",
                64 => "SHA-256",
                96 => "SHA-384",
                128 => "SHA-512",
                _ => ""
            };

            if (string.IsNullOrEmpty(kind)) return new List<ParseResult>();

            return new List<ParseResult>
            {
                new ParseResult(Name, content, $"类型：{kind}\n长度：{content.Length} hex 字符")
            };
        }
    }

    public class TimestampParser : IContentParser
    {
        public string Name => "Timestamp";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (!content.All(char.IsDigit) || !long.TryParse(content, out long value)) return new List<ParseResult>();

            string unit;
            double seconds;
            switch (content.Length)
            {
                case 10:
                    unit = "秒";
                    seconds = value;
                    break;
                case 13:
                    unit = "毫秒";
                    seconds = value / 1000.0;
                    break;
                case 16:
                    unit = "微秒";
                    seconds = value / 1000000.0;
                    break;
                case 17:
                    unit = "百纳秒";
                    seconds = value / 10000000.0;
                    break;
                case 19:
                    unit = "纳秒";
                    seconds = value / 1000000000.0;
                    break;
                default:
                    return new List<ParseResult>();
            }

            if (seconds < 0 || seconds > 4102444800.0) return new List<ParseResult>();

            var date = DateTimeOffset.FromUnixTimeSeconds(0).AddSeconds(seconds).UtcDateTime;
            string formatted = ParserUtilities.UtcString(date);

            return new List<ParseResult>
            {
                new ParseResult(
                    Name,
                    content,
                    $"精度：{unit}\n时间：{formatted}",
                    $"原始值：{value}\n精度：{unit}\nUTC: {formatted}\nISO 8601: {ParserUtilities.IsoString(date)}"
                )
            };
        }
    }

    public class HTTPStatusParser : IContentParser
    {
        public string Name => "HTTP Status";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (content.Length != 3 || !int.TryParse(content, out int code) || !_phrases.TryGetValue(code, out string? phrase))
            {
                return new List<ParseResult>();
            }

            string klass = code switch
            {
                >= 100 and < 200 => "信息响应",
                >= 200 and < 300 => "成功",
                >= 300 and < 400 => "重定向",
                >= 400 and < 500 => "客户端错误",
                >= 500 and < 600 => "服务端错误",
                _ => "未知"
            };

            return new List<ParseResult>
            {
                new ParseResult(Name, content, $"{code} {phrase}\n类型：{klass}")
            };
        }

        private readonly Dictionary<int, string> _phrases = new Dictionary<int, string>
        {
            { 100, "Continue" }, { 101, "Switching Protocols" }, { 102, "Processing" }, { 103, "Early Hints" },
            { 200, "OK" }, { 201, "Created" }, { 202, "Accepted" }, { 203, "Non-Authoritative Information" }, { 204, "No Content" }, { 205, "Reset Content" }, { 206, "Partial Content" }, { 207, "Multi-Status" }, { 208, "Already Reported" }, { 226, "IM Used" },
            { 300, "Multiple Choices" }, { 301, "Moved Permanently" }, { 302, "Found" }, { 303, "See Other" }, { 304, "Not Modified" }, { 305, "Use Proxy" }, { 307, "Temporary Redirect" }, { 308, "Permanent Redirect" },
            { 400, "Bad Request" }, { 401, "Unauthorized" }, { 402, "Payment Required" }, { 403, "Forbidden" }, { 404, "Not Found" }, { 405, "Method Not Allowed" }, { 406, "Not Acceptable" }, { 407, "Proxy Authentication Required" }, { 408, "Request Timeout" }, { 409, "Conflict" }, { 410, "Gone" }, { 411, "Length Required" }, { 412, "Precondition Failed" }, { 413, "Content Too Large" }, { 414, "URI Too Long" }, { 415, "Unsupported Media Type" }, { 416, "Range Not Satisfiable" }, { 417, "Expectation Failed" }, { 418, "I'm a teapot" }, { 421, "Misdirected Request" }, { 422, "Unprocessable Content" }, { 423, "Locked" }, { 424, "Failed Dependency" }, { 425, "Too Early" }, { 426, "Upgrade Required" }, { 428, "Precondition Required" }, { 429, "Too Many Requests" }, { 431, "Request Header Fields Too Large" }, { 451, "Unavailable For Legal Reasons" },
            { 500, "Internal Server Error" }, { 501, "Not Implemented" }, { 502, "Bad Gateway" }, { 503, "Service Unavailable" }, { 504, "Gateway Timeout" }, { 505, "HTTP Version Not Supported" }, { 506, "Variant Also Negotiates" }, { 507, "Insufficient Storage" }, { 508, "Loop Detected" }, { 510, "Not Extended" }, { 511, "Network Authentication Required" }
        };
    }

    public class NumberBaseParser : IContentParser
    {
        public string Name => "Number Base";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string lower = content.Trim().ToLowerInvariant();
            ulong? parsed = null;
            int sourceBase = 10;

            try
            {
                if (lower.StartsWith("0x"))
                {
                    parsed = Convert.ToUInt64(lower.Substring(2), 16);
                    sourceBase = 16;
                }
                else if (lower.StartsWith("0b"))
                {
                    parsed = Convert.ToUInt64(lower.Substring(2), 2);
                    sourceBase = 2;
                }
                else if (lower.StartsWith("0o"))
                {
                    parsed = Convert.ToUInt64(lower.Substring(2), 8);
                    sourceBase = 8;
                }
                else if (content.Length <= 9 && content.All(char.IsDigit))
                {
                    parsed = Convert.ToUInt64(content, 10);
                    sourceBase = 10;
                }
            }
            catch
            {
                return new List<ParseResult>();
            }

            if (!parsed.HasValue) return new List<ParseResult>();
            ulong value = parsed.Value;

            var lines = new List<string>
            {
                $"输入进制：{sourceBase}",
                $"DEC: {value}",
                $"HEX: 0x{Convert.ToString((long)value, 16).ToUpperInvariant()}",
                $"OCT: 0o{Convert.ToString((long)value, 8)}",
                $"BIN: 0b{Convert.ToString((long)value, 2)}"
            };

            return new List<ParseResult>
            {
                new ParseResult(Name, content, string.Join("\n", lines))
            };
        }
    }

    public class URLParser : IContentParser
    {
        public string Name => "URL";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (content.Length > 8192 || !content.Contains("://")) return new List<ParseResult>();

            try
            {
                var uri = new Uri(content);
                var lines = new List<string>
                {
                    $"Scheme: {uri.Scheme}",
                    $"Host: {uri.Host}"
                };

                if (!uri.IsDefaultPort)
                {
                    lines.Add($"Port: {uri.Port}");
                }
                if (!string.IsNullOrEmpty(uri.AbsolutePath))
                {
                    lines.Add($"Path: {uri.AbsolutePath}");
                }
                if (!string.IsNullOrEmpty(uri.Fragment))
                {
                    lines.Add($"Fragment: {uri.Fragment.TrimStart('#')}");
                }

                var query = uri.Query;
                if (!string.IsNullOrEmpty(query))
                {
                    var pairs = query.TrimStart('?').Split('&');
                    if (pairs.Length > 0 && pairs[0].Length > 0)
                    {
                        lines.Add("");
                        lines.Add("Query:");
                        foreach (var pair in pairs)
                        {
                            int eq = pair.IndexOf('=');
                            if (eq >= 0)
                            {
                                string k = pair.Substring(0, eq);
                                string v = pair.Substring(eq + 1);
                                lines.Add($"  {k} = {Uri.UnescapeDataString(v)}");
                            }
                            else
                            {
                                lines.Add($"  {pair} = ");
                            }
                        }
                    }
                }

                string decoded = Uri.UnescapeDataString(content);
                string details = decoded == content ? string.Join("\n", lines) : $"{string.Join("\n", lines)}\n\nDecoded:\n{decoded}";

                return new List<ParseResult>
                {
                    new ParseResult(Name, content, string.Join("\n", lines), details)
                };
            }
            catch
            {
                return new List<ParseResult>();
            }
        }
    }

    public class HTMLEntityParser : IContentParser
    {
        public string Name => "HTML Entity";
        public ParserInfo? Info => null;
        private readonly Regex _pattern = ParserUtilities.GetRegex(@"&(?:#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z0-9]+);");

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (ParserUtilities.FullMatch(_pattern, content) == null && !_pattern.IsMatch(content)) return new List<ParseResult>();

            string decoded = WebUtility.HtmlDecode(content);
            if (decoded == content) return new List<ParseResult>();

            return new List<ParseResult>
            {
                new ParseResult(Name, content, decoded, $"原始长度：{content.Length}\n解码长度：{decoded.Length}")
            };
        }
    }

    public class TOMLParser : IContentParser
    {
        public string Name => "TOML";
        public ParserInfo? Info => null;
        private readonly Regex _assignment = ParserUtilities.GetRegex(@"^[A-Za-z0-9_.-]+\s*=\s*.+");

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (Encoding.UTF8.GetByteCount(trimmed) > 64 * 1024) return new List<ParseResult>();
            if (trimmed.StartsWith("{") || trimmed.StartsWith("[")) return new List<ParseResult>();
            if (!LooksLikeTOML(trimmed)) return new List<ParseResult>();

            var lines = trimmed.Split(new[] { '\r', '\n' }, StringSplitOptions.None)
                .Select(FormatLine)
                .ToList();

            string formatted = string.Join("\n", lines).Trim();
            if (string.IsNullOrEmpty(formatted)) return new List<ParseResult>();

            return new List<ParseResult>
            {
                new ParseResult(Name, content, $"TOML  大小：{Encoding.UTF8.GetByteCount(trimmed)} 字节", formatted)
            };
        }

        private bool LooksLikeTOML(string content)
        {
            var lines = content.Split('\n');
            foreach (var line in lines)
            {
                string tr = line.Trim();
                if (tr.StartsWith("#")) continue;

                int hash = tr.IndexOf('#');
                string uncommented = hash >= 0 ? tr.Substring(0, hash) : tr;
                uncommented = uncommented.Trim();

                if (tr.StartsWith("[") && tr.EndsWith("]")) return true;
                if (ParserUtilities.FullMatch(_assignment, uncommented) != null) return true;
            }
            return false;
        }

        private string FormatLine(string line)
        {
            string tr = line.Trim();
            if (string.IsNullOrEmpty(tr) || tr.StartsWith("#")) return line;

            int equals = tr.IndexOf('=');
            if (equals < 0) return line;

            string key = tr.Substring(0, equals).Trim();
            string val = tr.Substring(equals + 1).Trim();
            return $"{key} = {val}";
        }
    }

    public class XMLFormatParser : IContentParser
    {
        public string Name => "XML";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (Encoding.UTF8.GetByteCount(trimmed) > 128 * 1024) return new List<ParseResult>();
            if (!trimmed.StartsWith("<") || !trimmed.EndsWith(">")) return new List<ParseResult>();

            try
            {
                var doc = XDocument.Parse(trimmed);
                string formatted = doc.ToString();
                string root = doc.Root?.Name.LocalName ?? "unknown";
                int bytes = Encoding.UTF8.GetByteCount(trimmed);

                return new List<ParseResult>
                {
                    new ParseResult(Name, content, $"Root: {root}\n大小：{bytes} 字节", formatted)
                };
            }
            catch
            {
                return new List<ParseResult>();
            }
        }
    }
}
