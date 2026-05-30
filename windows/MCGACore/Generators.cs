using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

namespace MCGA.MCGACore
{
    public class UUIDGenerator : IContentParser
    {
        public string Name => "UUID Generator";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (content.Trim().Equals("uuid", StringComparison.OrdinalIgnoreCase))
            {
                string uuid = UUIDv7.Generate();
                return new List<ParseResult> { new ParseResult(Name, content, uuid) };
            }
            return new List<ParseResult>();
        }
    }

    public class TimestampGenerator : IContentParser
    {
        public string Name => "Timestamp Generator";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string keyword = content.Trim().ToLowerInvariant();
            if (keyword == "ts" || keyword == "timestamp")
            {
                long seconds = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                return new List<ParseResult> { new ParseResult(Name, content, seconds.ToString()) };
            }
            return new List<ParseResult>();
        }
    }

    public class TimeGenerator : IContentParser
    {
        public string Name => "Time Generator";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (content.Trim().Equals("time", StringComparison.OrdinalIgnoreCase))
            {
                string iso = ParserUtilities.IsoString(DateTime.UtcNow);
                return new List<ParseResult> { new ParseResult(Name, content, iso) };
            }
            return new List<ParseResult>();
        }
    }

    public class ObjectIDGenerator : IContentParser
    {
        public string Name => "ObjectID Generator";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            string keyword = content.Trim().ToLowerInvariant();
            if (keyword == "objectid" || keyword == "oid")
            {
                uint seconds = (uint)DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                byte[] bytes = new byte[12];
                bytes[0] = (byte)((seconds >> 24) & 0xff);
                bytes[1] = (byte)((seconds >> 16) & 0xff);
                bytes[2] = (byte)((seconds >> 8) & 0xff);
                bytes[3] = (byte)(seconds & 0xff);

                byte[] randomBytes = ParserUtilities.RandomBytes(8);
                Array.Copy(randomBytes, 0, bytes, 4, 8);

                string hex = ParserUtilities.Hex(bytes);
                return new List<ParseResult> { new ParseResult(Name, content, hex) };
            }
            return new List<ParseResult>();
        }
    }

    public class Base64EncodeGenerator : IContentParser
    {
        public string Name => "Base64 Encode";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (content.Trim().Equals("b64", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(previousContent))
            {
                byte[] bytes = Encoding.UTF8.GetBytes(previousContent);
                string b64 = Convert.ToBase64String(bytes);
                return new List<ParseResult> { new ParseResult(Name, content, b64, previousContent) };
            }
            return new List<ParseResult>();
        }
    }

    public class Base64DecodeGenerator : IContentParser
    {
        public string Name => "Base64 Decode";
        public ParserInfo? Info => null;

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (content.Trim().Equals("db64", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(previousContent))
            {
                var decodedOpt = ParserUtilities.DataFromBase64Variants(previousContent);
                if (decodedOpt.HasValue)
                {
                    try
                    {
                        string decoded = Encoding.UTF8.GetString(decodedOpt.Value.Data);
                        if (ParserUtilities.IsPrintable(decoded))
                        {
                            return new List<ParseResult> { new ParseResult(Name, content, decoded, $"格式：{decodedOpt.Value.Variant}") };
                        }
                    }
                    catch
                    {
                        // Ignore
                    }
                }
            }
            return new List<ParseResult>();
        }
    }

    public class PasswordGenerator : IContentParser
    {
        public string Name => "Password Generator";
        public ParserInfo? Info => null;
        private readonly Regex _pattern = ParserUtilities.GetRegex(@"^pswd(?:\s+(\d{1,3}))?$", true);

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            var match = ParserUtilities.FullMatch(_pattern, content);
            if (match == null) return new List<ParseResult>();

            int length = 24;
            if (match.Groups[1].Success)
            {
                if (int.TryParse(match.Groups[1].Value, out int parsedLength))
                {
                    length = Math.Min(Math.Max(parsedLength, 8), 128);
                }
            }

            const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*()-_=+";
            var sb = new StringBuilder();
            for (int i = 0; i < length; i++)
            {
                sb.Append(alphabet[Random.Shared.Next(alphabet.Length)]);
            }

            return new List<ParseResult> { new ParseResult(Name, content, sb.ToString()) };
        }
    }

    public static class UUIDv7
    {
        public static string Generate()
        {
            long millis = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            byte[] bytes = new byte[16];
            bytes[0] = (byte)((millis >> 40) & 0xff);
            bytes[1] = (byte)((millis >> 32) & 0xff);
            bytes[2] = (byte)((millis >> 24) & 0xff);
            bytes[3] = (byte)((millis >> 16) & 0xff);
            bytes[4] = (byte)((millis >> 8) & 0xff);
            bytes[5] = (byte)(millis & 0xff);

            byte[] random = ParserUtilities.RandomBytes(10);
            Array.Copy(random, 0, bytes, 6, 10);

            // Set version 7
            bytes[6] = (byte)((bytes[6] & 0x0f) | 0x70);
            // Set variant RFC4122
            bytes[8] = (byte)((bytes[8] & 0x3f) | 0x80);

            string hex = ParserUtilities.Hex(bytes);
            return $"{hex.Substring(0, 8)}-{hex.Substring(8, 4)}-{hex.Substring(12, 4)}-{hex.Substring(16, 4)}-{hex.Substring(20)}";
        }
    }
}
