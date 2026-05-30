using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace MCGA.MCGACore
{
    public class CIDRParser : IContentParser
    {
        public string Name => "CIDR";
        public ParserInfo? Info => null;
        private readonly Regex _pattern = ParserUtilities.GetRegex(@"^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$");

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            var match = ParserUtilities.FullMatch(_pattern, content);
            if (match == null) return new List<ParseResult>();

            string ipStr = match.Groups[1].Value;
            string prefixStr = match.Groups[2].Value;

            if (!byte.TryParse(prefixStr, out byte prefix) || prefix > 32) return new List<ParseResult>();
            if (!IPAddress.TryParse(ipStr, out var ipAddress) || ipAddress.AddressFamily != AddressFamily.InterNetwork) return new List<ParseResult>();

            byte[] ipBytes = ipAddress.GetAddressBytes();
            uint ipValue = ((uint)ipBytes[0] << 24) | ((uint)ipBytes[1] << 16) | ((uint)ipBytes[2] << 8) | ipBytes[3];

            uint mask = prefix == 0 ? 0 : uint.MaxValue << (32 - prefix);
            uint network = ipValue & mask;
            uint broadcast = network | ~mask;

            if (prefix == 0)
            {
                return new List<ParseResult> { new ParseResult(Name, content, "默认路由（所有地址）") };
            }

            var lines = new List<string>();
            if (ipValue != network)
            {
                lines.Add($"输入：{ipAddress}/{prefix} → 网络：{new IPAddress(GetBeBytes(network))}/{prefix}");
            }

            switch (prefix)
            {
                case 32:
                    lines.Add($"单主机地址：{new IPAddress(GetBeBytes(network))}");
                    break;
                case 31:
                    lines.Add("点对点链路（RFC 3021）");
                    lines.Add($"可用范围：{new IPAddress(GetBeBytes(network))} - {new IPAddress(GetBeBytes(broadcast))} (2)");
                    break;
                default:
                    ulong total = 1UL << (32 - prefix);
                    lines.Add($"网络地址：{new IPAddress(GetBeBytes(network))}");
                    lines.Add($"广播地址：{new IPAddress(GetBeBytes(broadcast))}");
                    lines.Add($"可用范围：{new IPAddress(GetBeBytes(network + 1))} - {new IPAddress(GetBeBytes(broadcast - 1))} ({total - 2})");
                    break;
            }

            return new List<ParseResult> { new ParseResult(Name, content, string.Join("\n", lines)) };
        }

        private byte[] GetBeBytes(uint val)
        {
            return new[]
            {
                (byte)((val >> 24) & 0xff),
                (byte)((val >> 16) & 0xff),
                (byte)((val >> 8) & 0xff),
                (byte)(val & 0xff)
            };
        }
    }

    public class IPv6Parser : IContentParser
    {
        public string Name => "IPv6";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (!content.Contains(":") || content.Contains(" ")) return new List<ParseResult>();
            string cleaned = content.Trim('[', ']');
            if (!IPAddress.TryParse(cleaned, out var address) || address.AddressFamily != AddressFamily.InterNetworkV6) return new List<ParseResult>();

            string type = GetIPv6Kind(address);
            string compressed = address.ToString();
            string expanded = GetExpandedIPv6(address);

            return new List<ParseResult>
            {
                new ParseResult(
                    Name,
                    content,
                    $"类型：{type}",
                    $"压缩：{compressed}\n展开：{expanded}\n类型：{type}"
                )
            };
        }

        private string GetIPv6Kind(IPAddress address)
        {
            byte[] bytes = address.GetAddressBytes();
            ushort[] segments = new ushort[8];
            for (int i = 0; i < 8; i++)
            {
                segments[i] = (ushort)((bytes[i * 2] << 8) | bytes[i * 2 + 1]);
            }

            string desc = address.ToString();
            if (desc == "::1") return "回环地址 (::1)";
            if (desc == "::") return "未指定地址 (::)";
            if ((segments[0] & 0xffc0) == 0xfe80) return "链路本地地址 (fe80::/10)";
            if ((segments[0] & 0xfe00) == 0xfc00) return "唯一本地地址 (fc00::/7)";
            if ((segments[0] & 0xff00) == 0xff00) return "多播地址 (ff00::/8)";

            bool isMapped = true;
            for (int i = 0; i < 5; i++)
            {
                if (segments[i] != 0) { isMapped = false; break; }
            }
            if (isMapped && segments[5] == 0xffff)
            {
                return "IPv4 映射地址 (::ffff:0:0/96)";
            }

            return "全局单播地址";
        }

        private string GetExpandedIPv6(IPAddress address)
        {
            byte[] bytes = address.GetAddressBytes();
            var parts = new string[8];
            for (int i = 0; i < 8; i++)
            {
                ushort val = (ushort)((bytes[i * 2] << 8) | bytes[i * 2 + 1]);
                parts[i] = val.ToString("x4");
            }
            return string.Join(":", parts);
        }
    }

    public class IPParser : IContentParser
    {
        public string Name => "IP";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (!IPAddress.TryParse(content, out var address) || !IsPublicIPv4(address)) return new List<ParseResult>();

            byte[] bytes = address.GetAddressBytes();
            string binary = $"{Convert.ToString(bytes[0], 2).PadLeft(8, '0')}.{Convert.ToString(bytes[1], 2).PadLeft(8, '0')}.{Convert.ToString(bytes[2], 2).PadLeft(8, '0')}.{Convert.ToString(bytes[3], 2).PadLeft(8, '0')}";
            string details = $"八位组：{bytes[0]}.{bytes[1]}.{bytes[2]}.{bytes[3]}\n二进制：{binary}";

            string parsed = "公网 IP";
            var geo = IPGeo.Lookup(content);
            if (geo != null)
            {
                var lines = geo.DisplayLines;
                if (lines.Count > 0)
                {
                    parsed = string.Join("\n", lines);
                    details += $"\n\n地理位置信息：\n{parsed}";
                }
            }

            return new List<ParseResult> { new ParseResult("IPv4", content, parsed, details) };
        }

        private bool IsPublicIPv4(IPAddress address)
        {
            if (address.AddressFamily != AddressFamily.InterNetwork) return false;
            byte[] bytes = address.GetAddressBytes();
            byte first = bytes[0];
            byte second = bytes[1];
            if (first == 10 || first == 127 || first == 0 || first >= 224) return false;
            if (first == 172 && second >= 16 && second <= 31) return false;
            if (first == 192 && second == 168) return false;
            if (first == 169 && second == 254) return false;
            if (first == 100 && second >= 64 && second <= 127) return false;
            return true;
        }
    }

    public class DNSParser : IContentParser
    {
        public string Name => "DNS";
        public ParserInfo? Info => null;
        private readonly Regex _domainPattern = ParserUtilities.GetRegex(@"^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$", true);

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (ParserUtilities.FullMatch(_domainPattern, content) == null) return new List<ParseResult>();

            var providers = new[]
            {
                new DNSProvider("Cloudflare DoH", "https://cloudflare-dns.com/dns-query"),
                new DNSProvider("Google DoH", "https://dns.google/resolve"),
                new DNSProvider("AliDNS DoH", "https://dns.alidns.com/dns-query")
            };

            var queryTypes = new[]
            {
                new { Type = (ushort)1, Name = "A" },
                new { Type = (ushort)28, Name = "AAAA" },
                new { Type = (ushort)5, Name = "CNAME" }
            };

            var results = new List<ParseResult>();
            foreach (var provider in providers)
            {
                foreach (var qt in queryTypes)
                {
                    var answers = DNSLookup.Query(content, qt.Type, provider);
                    var matchedAnswers = new List<string>();
                    foreach (var ans in answers)
                    {
                        if (ans.Type == qt.Type)
                        {
                            matchedAnswers.Add(ans.Data);
                        }
                    }
                    if (matchedAnswers.Count > 0)
                    {
                        string parsed = $"DNS/{qt.Name} via {provider.Name}\n{string.Join("\n", matchedAnswers)}";
                        results.Add(new ParseResult(Name, content, parsed));
                    }
                }
            }
            return results;
        }
    }

    internal class IPGeo
    {
        public string Status { get; set; } = "";
        public string? Country { get; set; }
        public string? City { get; set; }
        public string? Isp { get; set; }
        public string? Reverse { get; set; }

        [JsonIgnore]
        public List<string> DisplayLines
        {
            get
            {
                var list = new List<string>();
                if (!string.IsNullOrEmpty(Country)) list.Add($"国家：{Country}");
                if (!string.IsNullOrEmpty(City)) list.Add($"城市：{City}");
                if (!string.IsNullOrEmpty(Isp)) list.Add($"ISP：{Isp}");
                if (!string.IsNullOrEmpty(Reverse)) list.Add($"反向 DNS：{Reverse}");
                return list;
            }
        }

        private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };

        public static IPGeo? Lookup(string ip)
        {
            try
            {
                string url = $"http://ip-api.com/json/{Uri.EscapeDataString(ip)}?fields=status,message,country,city,isp,reverse,query&lang=zh-CN";
                using var response = _httpClient.GetAsync(url).GetAwaiter().GetResult();
                if (!response.IsSuccessStatusCode) return null;
                string json = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
                var result = JsonSerializer.Deserialize<IPGeo>(json, options);
                if (result != null && result.Status == "success")
                {
                    return result;
                }
            }
            catch
            {
                // Ignore
            }
            return null;
        }
    }

    internal class DNSProvider
    {
        public string Name { get; }
        public string Url { get; }

        public DNSProvider(string name, string url)
        {
            Name = name;
            Url = url;
        }
    }

    internal class DNSResponse
    {
        public int Status { get; set; }
        public List<DNSAnswer>? Answer { get; set; }
    }

    internal class DNSAnswer
    {
        public ushort Type { get; set; }
        public uint Ttl { get; set; }
        public string Data { get; set; } = "";
    }

    internal static class DNSLookup
    {
        private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };

        public static List<DNSAnswer> Query(string domain, ushort type, DNSProvider provider)
        {
            try
            {
                string url = $"{provider.Url}?name={Uri.EscapeDataString(domain)}&type={type}";
                var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/dns-json"));

                using var response = _httpClient.SendAsync(request).GetAwaiter().GetResult();
                if (!response.IsSuccessStatusCode) return new List<DNSAnswer>();

                string json = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var res = JsonSerializer.Deserialize<DNSResponse>(json, options);
                if (res != null && res.Status == 0)
                {
                    return res.Answer ?? new List<DNSAnswer>();
                }
            }
            catch
            {
                // Ignore
            }
            return new List<DNSAnswer>();
        }
    }
}
