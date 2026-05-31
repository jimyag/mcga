using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace MCGA
{
    public enum AppLanguage
    {
        Zh,
        En
    }

    public enum AppTheme
    {
        Light,
        Dark
    }

    public enum TextKey
    {
        History,
        CopyFirstResult,
        CopyResult,
        CurrentClipboard,
        CopyOriginal,
        Paused,
        Waiting,
        EmptyHint,
        RefreshHistory,
        Quit,
        ClearHistory,
        NoHistory,
        Settings,
        Language,
        Chinese,
        English,
        Theme,
        LightWord,
        DarkWord,
        Parsers,
        StartAtLogin,
        Pause,
        Resume,
        CopyHistoryResult,
        Copied,
        OpenSettings,
        Close,
        Description,
        Examples,
        ClipboardContent,
        ExpectedOutput
    }

    public class AppPreferences
    {
        public AppLanguage Language { get; set; } = AppLanguage.Zh;
        public AppTheme Theme { get; set; } = AppTheme.Light;
        public HashSet<string> DisabledParserNames { get; set; } = new HashSet<string>();

        private readonly string _filePath;
        private static readonly object _lock = new object();

        public AppPreferences()
        {
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _filePath = Path.Combine(userProfile, ".config", "mcga", "preferences.json");
            Load();
        }

        public bool IsParserEnabled(string name)
        {
            return !DisabledParserNames.Contains(name);
        }

        public void SetParserEnabled(string name, bool enabled)
        {
            if (enabled)
            {
                DisabledParserNames.Remove(name);
            }
            else
            {
                DisabledParserNames.Add(name);
            }
            Save();
        }

        public HashSet<string> EnabledParserNames(List<string> allNames)
        {
            var set = new HashSet<string>();
            foreach (var name in allNames)
            {
                if (IsParserEnabled(name))
                {
                    set.Add(name);
                }
            }
            return set;
        }

        public string Text(TextKey key)
        {
            return Language == AppLanguage.Zh ? GetZh(key) : GetEn(key);
        }

        private void Load()
        {
            lock (_lock)
            {
                if (!File.Exists(_filePath)) return;
                try
                {
                    string json = File.ReadAllText(_filePath);
                    var data = JsonSerializer.Deserialize<AppPreferencesData>(json);
                    if (data != null)
                    {
                        Language = Enum.TryParse<AppLanguage>(data.Language, true, out var lang) ? lang : AppLanguage.Zh;
                        Theme = Enum.TryParse<AppTheme>(data.Theme, true, out var th) ? th : AppTheme.Light;
                        DisabledParserNames = data.DisabledParserNames != null 
                            ? new HashSet<string>(data.DisabledParserNames) 
                            : new HashSet<string>();
                    }
                }
                catch
                {
                    // Fallback to defaults
                }
            }
        }

        public void Save()
        {
            lock (_lock)
            {
                try
                {
                    string dir = Path.GetDirectoryName(_filePath)!;
                    if (!Directory.Exists(dir))
                    {
                        Directory.CreateDirectory(dir);
                    }
                    var data = new AppPreferencesData
                    {
                        Language = Language.ToString(),
                        Theme = Theme.ToString(),
                        DisabledParserNames = new List<string>(DisabledParserNames)
                    };
                    string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(_filePath, json);
                }
                catch
                {
                    // Best effort
                }
            }
        }

        private string GetZh(TextKey key) => key switch
        {
            TextKey.History => "历史",
            TextKey.CopyFirstResult => "复制第一条结果",
            TextKey.CopyResult => "复制解析结果",
            TextKey.CurrentClipboard => "当前剪切板",
            TextKey.CopyOriginal => "复制原文",
            TextKey.Paused => "已暂停监听",
            TextKey.Waiting => "等待剪切板内容",
            TextKey.EmptyHint => "复制可解析内容后会在这里显示。",
            TextKey.RefreshHistory => "刷新历史",
            TextKey.Quit => "退出",
            TextKey.ClearHistory => "清空历史",
            TextKey.NoHistory => "暂无历史",
            TextKey.Settings => "设置",
            TextKey.Language => "语言",
            TextKey.Chinese => "中文",
            TextKey.English => "英文",
            TextKey.Theme => "主题",
            TextKey.LightWord => "浅色",
            TextKey.DarkWord => "深色",
            TextKey.Parsers => "解析器",
            TextKey.StartAtLogin => "开机自启动",
            TextKey.Pause => "暂停监听",
            TextKey.Resume => "继续监听",
            TextKey.CopyHistoryResult => "复制这条历史结果",
            TextKey.Copied => "已复制",
            TextKey.OpenSettings => "打开设置",
            TextKey.Close => "关闭",
            TextKey.Description => "说明",
            TextKey.Examples => "示例",
            TextKey.ClipboardContent => "剪切板内容",
            TextKey.ExpectedOutput => "预期输出",
            _ => ""
        };

        private string GetEn(TextKey key) => key switch
        {
            TextKey.History => "History",
            TextKey.CopyFirstResult => "Copy first result",
            TextKey.CopyResult => "Copy result",
            TextKey.CurrentClipboard => "Current clipboard",
            TextKey.CopyOriginal => "Copy original",
            TextKey.Paused => "Paused",
            TextKey.Waiting => "Waiting for clipboard",
            TextKey.EmptyHint => "Copy supported content to show parsed results here.",
            TextKey.RefreshHistory => "Refresh history",
            TextKey.Quit => "Quit",
            TextKey.ClearHistory => "Clear history",
            TextKey.NoHistory => "No history",
            TextKey.Settings => "Settings",
            TextKey.Language => "Language",
            TextKey.Chinese => "Chinese",
            TextKey.English => "English",
            TextKey.Theme => "Theme",
            TextKey.LightWord => "Light",
            TextKey.DarkWord => "Dark",
            TextKey.Parsers => "Parsers",
            TextKey.StartAtLogin => "Start at login",
            TextKey.Pause => "Pause",
            TextKey.Resume => "Resume",
            TextKey.CopyHistoryResult => "Copy this history result",
            TextKey.Copied => "Copied",
            TextKey.OpenSettings => "Open settings",
            TextKey.Close => "Close",
            TextKey.Description => "Description",
            TextKey.Examples => "Examples",
            TextKey.ClipboardContent => "Clipboard content",
            TextKey.ExpectedOutput => "Expected output",
            _ => ""
        };
    }

    internal class AppPreferencesData
    {
        public string Language { get; set; } = "Zh";
        public string Theme { get; set; } = "Light";
        public List<string>? DisabledParserNames { get; set; }
    }
}
