using System;
using System.Text;
using System.Text.RegularExpressions;

namespace MCGA.MCGACore
{
    public static class ParserUtilities
    {
        public static string UtcString(DateTime date)
        {
            return date.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff 'UTC'");
        }

        public static string UtcSecondString(DateTime date)
        {
            return date.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'");
        }

        public static string IsoString(DateTime date)
        {
            return date.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");
        }

        public static Regex GetRegex(string pattern, bool caseInsensitive = false)
        {
            var options = RegexOptions.Compiled;
            if (caseInsensitive)
            {
                options |= RegexOptions.IgnoreCase;
            }
            return new Regex(pattern, options);
        }

        public static Match? FullMatch(Regex regex, string value)
        {
            var match = regex.Match(value);
            if (match.Success && match.Index == 0 && match.Length == value.Length)
            {
                return match;
            }
            return null;
        }

        public static (byte[] Data, string Variant)? DataFromBase64Variants(string value)
        {
            try
            {
                // Try standard Base64
                var data = Convert.FromBase64String(value);
                return (data, "standard");
            }
            catch
            {
                // Try url-safe variants
                string incoming = value.Replace('-', '+').Replace('_', '/');
                try
                {
                    var data = Convert.FromBase64String(incoming);
                    return (data, "url-safe");
                }
                catch
                {
                    // Try padded url-safe
                    int padCount = (4 - incoming.Length % 4) % 4;
                    incoming += new string('=', padCount);
                    try
                    {
                        var data = Convert.FromBase64String(incoming);
                        return (data, "url-safe-no-pad");
                    }
                    catch
                    {
                        return null;
                    }
                }
            }
        }

        public static bool IsPrintable(string value)
        {
            if (string.IsNullOrEmpty(value)) return false;
            foreach (char c in value)
            {
                if (c < 32 && c != '\n' && c != '\r' && c != '\t')
                {
                    return false;
                }
            }
            return true;
        }

        public static string Hex(byte[] bytes)
        {
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public static byte[] RandomBytes(int count)
        {
            var bytes = new byte[count];
            Random.Shared.NextBytes(bytes);
            return bytes;
        }
    }
}
