using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using MCGA.MCGACore;

namespace MCGA
{
    public class ClipboardModel : INotifyPropertyChanged
    {
        private bool _isPaused;
        private string _currentContent = "";
        private List<ParseResult> _results = new List<ParseResult>();
        private List<HistoryEntry> _history = new List<HistoryEntry>();
        private DateTime? _lastUpdated;
        private string? _copyNotice;

        public bool IsPaused
        {
            get => _isPaused;
            set => SetProperty(ref _isPaused, value);
        }

        public string CurrentContent
        {
            get => _currentContent;
            set => SetProperty(ref _currentContent, value);
        }

        public List<ParseResult> Results
        {
            get => _results;
            set => SetProperty(ref _results, value);
        }

        public List<HistoryEntry> History
        {
            get => _history;
            set => SetProperty(ref _history, value);
        }

        public DateTime? LastUpdated
        {
            get => _lastUpdated;
            set => SetProperty(ref _lastUpdated, value);
        }

        public string? CopyNotice
        {
            get => _copyNotice;
            set => SetProperty(ref _copyNotice, value);
        }

        public Action<string, List<ParseResult>>? OnNewResults { get; set; }

        private readonly ParserEngine _engine = new ParserEngine();
        private readonly AppPreferences _preferences;
        private readonly DispatcherTimer _timer;
        
        private uint _lastSequence;
        private string _previousContent = "";

        [DllImport("user32.dll")]
        private static extern uint GetClipboardSequenceNumber();

        public List<string> ParserNames => _engine.ParserNames;
        public List<ParserInfo> ParserInfos => _engine.ParserInfos;

        public ClipboardModel(AppPreferences preferences)
        {
            _preferences = preferences;
            _lastSequence = GetClipboardSequenceNumber();
            AppLogger.Info($"ClipboardModel created. InitialSequence={_lastSequence}");

            _timer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(500)
            };
            _timer.Tick += (s, e) => PollClipboard();
        }

        public void Start()
        {
            AppLogger.Info("ClipboardModel.Start called");
            RefreshHistory();
            _timer.Start();
            AppLogger.Info("Clipboard polling timer started");
        }

        public void TogglePaused()
        {
            IsPaused = !IsPaused;
        }

        public void ClearHistory()
        {
            Task.Run(async () =>
            {
                await HistoryStore.Shared.ClearAsync();
                Application.Current.Dispatcher.Invoke(RefreshHistory);
            });
        }

        public void RefreshHistory()
        {
            Task.Run(async () =>
            {
                try
                {
                    var entries = await HistoryStore.Shared.GetRecentAsync(30);
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        History = entries;
                    });
                    AppLogger.Info($"History refreshed. EntryCount={entries.Count}");
                }
                catch (Exception ex)
                {
                    AppLogger.Error("RefreshHistory failed", ex);
                }
            });
        }

        public void Copy(string value)
        {
            try
            {
                Clipboard.SetText(value);
                // Synchronize sequence immediately to avoid self-parsing loops
                _lastSequence = GetClipboardSequenceNumber();
            }
            catch
            {
                AppLogger.Info("Clipboard copy failed because clipboard is locked");
                // Clipboard might be locked by another process
            }

            CopyNotice = _preferences.Text(TextKey.Copied);

            Task.Run(async () =>
            {
                await Task.Delay(1400);
                try
                {
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        if (CopyNotice == _preferences.Text(TextKey.Copied))
                        {
                            CopyNotice = null;
                        }
                    });
                }
                catch (Exception ex)
                {
                    AppLogger.Error("Copy notice cleanup failed", ex);
                }
            });
        }

        private void PollClipboard()
        {
            if (IsPaused) return;

            uint currentSequence = GetClipboardSequenceNumber();
            if (currentSequence == _lastSequence) return;
            _lastSequence = currentSequence;

            string content = "";
            try
            {
                if (Clipboard.ContainsText())
                {
                    content = Clipboard.GetText();
                }
            }
            catch
            {
                AppLogger.Info("Clipboard read skipped because clipboard is locked");
                return; // Clipboard currently locked, try next time
            }

            if (string.IsNullOrEmpty(content) || content == CurrentContent) return;

            var enabledParsers = _preferences.EnabledParserNames(_engine.ParserNames);
            string prevContent = _previousContent;
            uint sequenceAtStart = currentSequence;

            Task.Run(() =>
            {
                try
                {
                    AppLogger.Info($"Parsing clipboard content. Sequence={sequenceAtStart}, ContentLength={content.Length}, EnabledParserCount={enabledParsers.Count}");
                    var parsed = _engine.ParseAll(content, prevContent, enabledParsers);
                    AppLogger.Info($"Parsing completed. ResultCount={parsed.Count}");
                    if (parsed.Count == 0) return;

                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        // Verify clipboard sequence hasn't changed since we started parsing
                        if (sequenceAtStart == GetClipboardSequenceNumber())
                        {
                            CurrentContent = content;
                            Results = parsed;
                            LastUpdated = DateTime.Now;
                            _previousContent = content;

                            OnNewResults?.Invoke(content, parsed);

                            Task.Run(async () =>
                            {
                                try
                                {
                                    await HistoryStore.Shared.AppendAsync(content, parsed);
                                    Application.Current.Dispatcher.Invoke(RefreshHistory);
                                }
                                catch (Exception ex)
                                {
                                    AppLogger.Error("History append failed", ex);
                                }
                            });
                        }
                        else
                        {
                            AppLogger.Info("Parsed result skipped because clipboard sequence changed");
                        }
                    });
                }
                catch (Exception ex)
                {
                    AppLogger.Error("Clipboard parsing task failed", ex);
                }
            });
        }

        #region INotifyPropertyChanged
        public event PropertyChangedEventHandler? PropertyChanged;

        protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }

        protected bool SetProperty<T>(ref T storage, T value, [CallerMemberName] string? propertyName = null)
        {
            if (EqualityComparer<T>.Default.Equals(storage, value)) return false;
            storage = value;
            OnPropertyChanged(propertyName);
            return true;
        }
        #endregion
    }
}
