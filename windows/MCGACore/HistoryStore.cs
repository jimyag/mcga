using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MCGA.MCGACore
{
    public class HistoryEntry
    {
        public ulong Id { get; set; }
        public DateTime Timestamp { get; set; }
        public string OriginalPreview { get; set; }
        public List<HistoryResult> Results { get; set; }

        public HistoryEntry(ulong id, DateTime timestamp, string originalPreview, List<HistoryResult> results)
        {
            Id = id;
            Timestamp = timestamp;
            OriginalPreview = originalPreview;
            Results = results;
        }
    }

    public class HistoryResult
    {
        public string ParserName { get; set; }
        public string Parsed { get; set; }
        public string? Details { get; set; }

        public HistoryResult(string parserName, string parsed, string? details = null)
        {
            ParserName = parserName;
            Parsed = parsed;
            Details = details;
        }
    }

    public class HistoryStore
    {
        public static HistoryStore Shared { get; } = new HistoryStore();
        private const int MaxEntries = 500;
        private const int PreviewLength = 200;
        private readonly string _filePath;
        private readonly SemaphoreSlim _semaphore = new SemaphoreSlim(1, 1);
        private readonly JsonSerializerOptions _jsonOptions;

        public HistoryStore()
        {
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _filePath = Path.Combine(userProfile, ".local", "share", "mcga", "history.json");
            _jsonOptions = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            };
        }

        public async Task AppendAsync(string original, List<ParseResult> results)
        {
            if (results == null || results.Count == 0) return;

            await _semaphore.WaitAsync();
            try
            {
                var entries = await LoadAllInternalAsync();
                ulong nextId = entries.Count > 0 ? entries.Last().Id + 1 : 1;
                string preview = original.Length > PreviewLength
                    ? original.Substring(0, PreviewLength) + "..."
                    : original;

                var newEntry = new HistoryEntry(
                    nextId,
                    DateTime.Now,
                    preview,
                    results.Select(r => new HistoryResult(r.ParserName, r.Parsed, r.Details)).ToList()
                );

                entries.Add(newEntry);
                if (entries.Count > MaxEntries)
                {
                    entries.RemoveRange(0, entries.Count - MaxEntries);
                }

                string dir = Path.GetDirectoryName(_filePath)!;
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                string tempFile = _filePath + ".tmp";
                await using (var stream = File.Create(tempFile))
                {
                    await JsonSerializer.SerializeAsync(stream, entries, _jsonOptions);
                }
                if (File.Exists(_filePath))
                {
                    File.Delete(_filePath);
                }
                File.Move(tempFile, _filePath);
            }
            catch
            {
                // History is best-effort and should never block the main flow
            }
            finally
            {
                _semaphore.Release();
            }
        }

        private async Task<List<HistoryEntry>> LoadAllInternalAsync()
        {
            if (!File.Exists(_filePath)) return new List<HistoryEntry>();
            try
            {
                await using var stream = File.OpenRead(_filePath);
                var list = await JsonSerializer.DeserializeAsync<List<HistoryEntry>>(stream, _jsonOptions);
                return list ?? new List<HistoryEntry>();
            }
            catch
            {
                return new List<HistoryEntry>();
            }
        }

        public async Task<List<HistoryEntry>> LoadAllAsync()
        {
            await _semaphore.WaitAsync();
            try
            {
                return await LoadAllInternalAsync();
            }
            finally
            {
                _semaphore.Release();
            }
        }

        public async Task<List<HistoryEntry>> GetRecentAsync(int count)
        {
            var all = await LoadAllAsync();
            return all.AsEnumerable().Reverse().Take(count).ToList();
        }

        public async Task ClearAsync()
        {
            await _semaphore.WaitAsync();
            try
            {
                string dir = Path.GetDirectoryName(_filePath)!;
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                await File.WriteAllTextAsync(_filePath, "[]");
            }
            catch
            {
                // Ignore
            }
            finally
            {
                _semaphore.Release();
            }
        }
    }
}
