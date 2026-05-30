using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using YamlDotNet.Serialization;

namespace MCGA.MCGACore
{
    public class CronParser : IContentParser
    {
        public string Name => "Cron";
        public ParserInfo? Info => null;

        private readonly Dictionary<string, string> _macros = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "@yearly", "每年 1 月 1 日 00:00 执行" },
            { "@annually", "每年 1 月 1 日 00:00 执行" },
            { "@monthly", "每月 1 日 00:00 执行" },
            { "@weekly", "每周日 00:00 执行" },
            { "@daily", "每天 00:00 执行" },
            { "@midnight", "每天 00:00 执行" },
            { "@hourly", "每小时整点执行" },
            { "@reboot", "系统重启后执行一次" }
        };

        private readonly string[] _weekdayNames = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" };
        private readonly string[] _monthNames = { "", "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月" };

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (_macros.TryGetValue(trimmed, out string? desc))
            {
                return new List<ParseResult> { new ParseResult(Name, content, desc) };
            }

            string[] fields = trimmed.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            if ((fields.Length != 5 && fields.Length != 6) || !fields.All(IsValidField))
            {
                return new List<ParseResult>();
            }

            string? sec = fields.Length == 6 ? Explain(fields[0], "秒") : null;
            int offset = fields.Length == 6 ? 1 : 0;
            string min = Explain(fields[offset], "分钟");
            string hour = Explain(fields[offset + 1], "小时");
            string day = Explain(fields[offset + 2], "天");
            string month = Explain(fields[offset + 3], "月", _monthNames);
            string week = Explain(fields[offset + 4], "周", _weekdayNames);

            var lines = new List<string>
            {
                $"分钟：{min}",
                $"小时：{hour}",
                $"日期：{day}",
                $"月份：{month}",
                $"星期：{week}"
            };
            if (sec != null)
            {
                lines.Insert(0, $"秒：{sec}");
            }

            return new List<ParseResult>
            {
                new ParseResult(Name, content, $"{month}，{day}，{hour}", string.Join("\n", lines))
            };
        }

        private bool IsValidField(string value)
        {
            if (string.IsNullOrEmpty(value)) return false;
            foreach (char c in value)
            {
                if (!char.IsDigit(c) && !"*-/?,LW#".Contains(c))
                {
                    return false;
                }
            }
            return true;
        }

        private string Explain(string field, string unit, string[]? names = null)
        {
            if (field == "*" || field == "?") return $"每{unit}";
            if (field.StartsWith("*/")) return $"每 {field.Substring(2)} {unit}";
            if (field.Contains("-") && !field.Contains("/"))
            {
                var parts = field.Split('-');
                if (parts.Length == 2)
                {
                    return $"{Label(parts[0], names)} 到 {Label(parts[1], names)}";
                }
            }
            if (field.Contains("-") && field.Contains("/"))
            {
                int slash = field.IndexOf('/');
                string range = field.Substring(0, slash);
                string step = field.Substring(slash + 1);
                var parts = range.Split('-');
                string start = parts[0];
                string end = parts.Length > 1 ? parts[1] : parts[0];
                return $"{Label(start, names)} 到 {Label(end, names)} 每隔 {step}";
            }
            if (field.Contains(","))
            {
                return string.Join("、", field.Split(',').Select(x => Label(x, names)));
            }
            return Label(field, names);
        }

        private string Label(string value, string[]? names)
        {
            if (names != null && int.TryParse(value, out int index) && index >= 0 && index < names.Length)
            {
                return names[index];
            }
            return value;
        }
    }

    public class JSONParser : IContentParser
    {
        public string Name => "JSON";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (!trimmed.StartsWith("{") && !trimmed.StartsWith("[")) return new List<ParseResult>();

            try
            {
                using var doc = JsonDocument.Parse(trimmed);
                var options = new JsonSerializerOptions { WriteIndented = true };
                string formatted = JsonSerializer.Serialize(doc, options);
                string kind = trimmed.StartsWith("{") ? "object" : "array";
                int bytes = Encoding.UTF8.GetByteCount(trimmed);
                return new List<ParseResult>
                {
                    new ParseResult(Name, content, $"类型：{kind}  大小：{bytes} 字节", formatted)
                };
            }
            catch
            {
                return new List<ParseResult>();
            }
        }
    }

    public class JSON5Parser : IContentParser
    {
        public string Name => "JSON5";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (!trimmed.StartsWith("{") && !trimmed.StartsWith("[")) return new List<ParseResult>();

            string normalized = Normalize(trimmed);
            if (normalized == trimmed) return new List<ParseResult>();

            try
            {
                using var doc = JsonDocument.Parse(normalized);
                var options = new JsonSerializerOptions { WriteIndented = true };
                string formatted = JsonSerializer.Serialize(doc, options);
                string kind = trimmed.StartsWith("{") ? "object" : "array";
                int bytes = Encoding.UTF8.GetByteCount(trimmed);
                return new List<ParseResult>
                {
                    new ParseResult(Name, content, $"类型：{kind}  大小：{bytes} 字节", formatted)
                };
            }
            catch
            {
                return new List<ParseResult>();
            }
        }

        private string Normalize(string input)
        {
            string output = input;
            // Remove single-line comments
            output = Regex.Replace(output, @"(?m)//.*$", "");
            // Remove multi-line comments
            output = Regex.Replace(output, @"/\*[\s\S]*?\*/", "");
            // Remove trailing commas
            output = Regex.Replace(output, @",(\s*[\]}])", "$1");
            // Add quotes to unquoted keys
            output = Regex.Replace(output, @"([\{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:", "$1\"$2\":");
            // Single quotes to double quotes
            output = output.Replace('\'', '"');
            return output;
        }
    }

    public class YAMLParser : IContentParser
    {
        public string Name => "YAML";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (Encoding.UTF8.GetByteCount(trimmed) > 64 * 1024) return new List<ParseResult>();
            if (trimmed.StartsWith("{") || trimmed.StartsWith("[")) return new List<ParseResult>();
            if (!LooksLikeYAML(trimmed)) return new List<ParseResult>();

            try
            {
                var deserializer = new DeserializerBuilder().Build();
                var yamlObj = deserializer.Deserialize<object>(trimmed);
                if (yamlObj is IDictionary<object, object> || yamlObj is IList<object>)
                {
                    var serializer = new SerializerBuilder().Build();
                    string formatted = serializer.Serialize(yamlObj).Trim();
                    string kind = yamlObj is IDictionary<object, object> ? "map" : "sequence";
                    int bytes = Encoding.UTF8.GetByteCount(trimmed);
                    return new List<ParseResult>
                    {
                        new ParseResult(
                            Name,
                            content,
                            $"类型：{kind}  大小：{bytes} 字节",
                            $"{formatted}\n类型：{kind}  大小：{bytes} 字节"
                        )
                    };
                }
            }
            catch
            {
                // Ignore
            }
            return new List<ParseResult>();
        }

        private bool LooksLikeYAML(string content)
        {
            if (content.StartsWith("---")) return true;
            if (content.Contains(": ") || content.Contains(":\n")) return true;

            var lines = content.Split('\n');
            int dashCount = 0;
            foreach (var line in lines)
            {
                if (line.Trim().StartsWith("- "))
                {
                    dashCount++;
                    if (dashCount >= 2) return true;
                }
            }
            return false;
        }
    }

    public class Base64Parser : IContentParser
    {
        public string Name => "Base64";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string trimmed = content.Trim();
            if (trimmed.Length < 8) return new List<ParseResult>();

            foreach (char c in trimmed)
            {
                if (!char.IsLetterOrDigit(c) && !"+/-_=".Contains(c))
                {
                    return new List<ParseResult>();
                }
            }

            var decodedOpt = ParserUtilities.DataFromBase64Variants(trimmed);
            if (!decodedOpt.HasValue) return new List<ParseResult>();

            try
            {
                string decoded = Encoding.UTF8.GetString(decodedOpt.Value.Data);
                if (ParserUtilities.IsPrintable(decoded))
                {
                    int byteCount = Encoding.UTF8.GetByteCount(decoded);
                    return new List<ParseResult>
                    {
                        new ParseResult(
                            Name,
                            content,
                            $"格式：{decodedOpt.Value.Variant}  编码长度：{trimmed.Length}  解码长度：{decoded.Length}",
                            $"{decoded}\n\n格式：{decodedOpt.Value.Variant}  编码长度：{trimmed.Length}  解码长度：{byteCount} 字节"
                        )
                    };
                }
            }
            catch
            {
                // Ignore
            }

            return new List<ParseResult>();
        }
    }
}
