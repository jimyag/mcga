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

            _timer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(500)
            };
            _timer.Tick += (s, e) => PollClipboard();
        }

        public void Start()
        {
            RefreshHistory();
            _timer.Start();
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
                var entries = await HistoryStore.Shared.GetRecentAsync(30);
                Application.Current.Dispatcher.Invoke(() =>
                {
                    History = entries;
                });
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
                // Clipboard might be locked by another process
            }

            CopyNotice = _preferences.Text(TextKey.Copied);

            Task.Run(async () =>
            {
                await Task.Delay(1400);
                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (CopyNotice == _preferences.Text(TextKey.Copied))
                    {
                        CopyNotice = null;
                    }
                });
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
                return; // Clipboard currently locked, try next time
            }

            if (string.IsNullOrEmpty(content) || content == CurrentContent) return;

            var enabledParsers = _preferences.EnabledParserNames(_engine.ParserNames);
            var parsed = _engine.ParseAll(content, _previousContent, enabledParsers);

            _previousContent = content;

            if (parsed.Count == 0) return;

            CurrentContent = content;
            Results = parsed;
            LastUpdated = DateTime.Now;

            OnNewResults?.Invoke(content, parsed);

            Task.Run(async () =>
            {
                await HistoryStore.Shared.AppendAsync(content, parsed);
                Application.Current.Dispatcher.Invoke(RefreshHistory);
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
