using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace MCGA.MCGACore
{
    public class CustomCommandParser : IContentParser
    {
        public string Name { get; }
        public ParserInfo? Info { get; }
        private readonly CustomParserConfig _config;

        private CustomCommandParser(CustomParserConfig config)
        {
            _config = config;
            Name = config.Name;

            var examplesList = new List<ParserExample>();
            if (config.Examples != null)
            {
                foreach (var ex in config.Examples)
                {
                    string zhExp = ex.Expected?.Zh ?? ex.ExpectedText ?? "";
                    string enExp = ex.Expected?.En ?? ex.ExpectedText ?? "";
                    examplesList.Add(new ParserExample(ex.Input, zhExp, enExp));
                }
            }

            Info = new ParserInfo(
                config.Name,
                config.Description?.Zh ?? "执行本地命令解析剪切板内容。",
                config.Description?.En ?? "Runs a local command to parse clipboard content.",
                examplesList
            );
        }

        public static List<CustomCommandParser> Load()
        {
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string configPath = Path.Combine(userProfile, ".config", "mcga", "custom_parsers.json");

            if (!File.Exists(configPath)) return new List<CustomCommandParser>();

            try
            {
                string json = File.ReadAllText(configPath);
                var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
                var fileData = JsonSerializer.Deserialize<CustomParserFile>(json, options);

                if (fileData?.Parsers == null) return new List<CustomCommandParser>();

                return fileData.Parsers
                    .Where(p => p.Enabled ?? true)
                    .Where(p => string.IsNullOrEmpty(p.Kind) || p.Kind.Equals("command", StringComparison.OrdinalIgnoreCase))
                    .Select(p => new CustomCommandParser(p))
                    .ToList();
            }
            catch
            {
                return new List<CustomCommandParser>();
            }
        }

        public List<ParseResult> Parse(string content, string previousContent = "")
        {
            if (!string.IsNullOrEmpty(_config.Match))
            {
                try
                {
                    var rx = new Regex(_config.Match);
                    if (!rx.IsMatch(content)) return new List<ParseResult>();
                }
                catch
                {
                    return new List<ParseResult>();
                }
            }

            string? executable = ExpandCommandPath(_config.Command);
            if (string.IsNullOrEmpty(executable))
            {
                return new List<ParseResult>();
            }

            bool isPath = executable.Contains(Path.DirectorySeparatorChar) || executable.Contains(Path.AltDirectorySeparatorChar);
            if (isPath && !File.Exists(executable))
            {
                return new List<ParseResult>();
            }

            string? output = RunCommand(executable, _config.Args ?? new List<string>(), content);
            if (string.IsNullOrEmpty(output)) return new List<ParseResult>();

            string trimmed = output.Trim();
            if (string.IsNullOrEmpty(trimmed)) return new List<ParseResult>();

            string[] lines = trimmed.Split(new[] { '\n' }, 2);
            string firstLine = lines[0].TrimEnd('\r');

            return new List<ParseResult>
            {
                new ParseResult(
                    Name,
                    content,
                    firstLine,
                    trimmed == firstLine ? null : trimmed
                )
            };
        }

        private string? ExpandCommandPath(string command)
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string path = command;
            if (path == "~")
            {
                path = home;
            }
            else if (path.StartsWith("~/") || path.StartsWith("~\\"))
            {
                path = Path.Combine(home, path.Substring(2));
            }
            path = path.Replace("$HOME", home).Replace("${HOME}", home);
            return path;
        }

        private string? RunCommand(string executable, List<string> args, string input)
        {
            int timeoutMs = Math.Min(Math.Max(_config.TimeoutMs ?? 500, 50), 3000);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = executable,
                    UseShellExecute = false,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8
                };

                foreach (var arg in args)
                {
                    psi.ArgumentList.Add(arg);
                }

                using var process = new Process { StartInfo = psi };
                process.Start();

                // Write stdin asynchronously to prevent deadlock if buffer fills up
                var writeTask = Task.Run(async () =>
                {
                    try
                    {
                        await process.StandardInput.WriteAsync(input);
                        process.StandardInput.Close();
                    }
                    catch
                    {
                        // Ignore write failures
                    }
                });

                bool exited = process.WaitForExit(timeoutMs);
                if (!exited)
                {
                    try
                    {
                        process.Kill();
                    }
                    catch
                    {
                        // Ignore kill failures
                    }
                    return null;
                }

                writeTask.Wait(); // Ensure write task is completed

                if (process.ExitCode != 0) return null;

                return process.StandardOutput.ReadToEnd();
            }
            catch
            {
                return null;
            }
        }
    }

    internal class CustomParserFile
    {
        public List<CustomParserConfig>? Parsers { get; set; }
    }

    internal class CustomParserConfig
    {
        public string Name { get; set; } = "";
        public string? Kind { get; set; }
        public LocalizedText? Description { get; set; }
        public List<CustomParserExample>? Examples { get; set; }
        public string? Match { get; set; }
        public string Command { get; set; } = "";
        public List<string>? Args { get; set; }
        public int? TimeoutMs { get; set; }
        public bool? Enabled { get; set; }
    }

    internal class LocalizedText
    {
        public string? Zh { get; set; }
        public string? En { get; set; }
    }

    internal class CustomParserExample
    {
        public string Input { get; set; } = "";
        public LocalizedText? Expected { get; set; }
        public string? ExpectedText { get; set; }
    }
}
