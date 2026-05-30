using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MCGA.MCGACore;

namespace MCGA
{
    public partial class ClipboardPopoverWindow : Window, INotifyPropertyChanged
    {
        public ClipboardModel Model { get; }
        public AppPreferences Preferences { get; }

        private Brush _windowBackground = Brushes.White;
        private Brush _headerBackground = Brushes.Teal;
        private Brush _cardBackground = Brushes.White;
        private Brush _borderBrushColor = Brushes.LightGray;
        private Brush _textPrimaryBrush = Brushes.Black;
        private Brush _textSecondaryBrush = Brushes.DarkGray;
        private Brush _accentBrush = Brushes.Teal;

        public Brush WindowBackground { get => _windowBackground; set => SetProperty(ref _windowBackground, value); }
        public Brush HeaderBackground { get => _headerBackground; set => SetProperty(ref _headerBackground, value); }
        public Brush CardBackground { get => _cardBackground; set => SetProperty(ref _cardBackground, value); }
        public Brush BorderBrushColor { get => _borderBrushColor; set => SetProperty(ref _borderBrushColor, value); }
        public Brush TextPrimaryBrush { get => _textPrimaryBrush; set => SetProperty(ref _textPrimaryBrush, value); }
        public Brush TextSecondaryBrush { get => _textSecondaryBrush; set => SetProperty(ref _textSecondaryBrush, value); }
        public Brush AccentBrush { get => _accentBrush; set => SetProperty(ref _accentBrush, value); }

        // Localized Strings
        private string _pauseBtnText = "";
        private string _pauseBtnTooltip = "";
        private string _refreshTooltip = "";
        private string _settingsTooltip = "";
        private string _quitTooltip = "";
        private string _emptyStateTitle = "";
        private string _emptyStateDesc = "";
        private string _currentClipboardText = "";
        private string _copyOriginalTooltip = "";
        private string _copyResultTooltip = "";
        private string _historyText = "";
        private string _clearHistoryTooltip = "";
        private string _noHistoryText = "";
        private string _copyHistoryResultTooltip = "";

        public string PauseBtnText { get => _pauseBtnText; set => SetProperty(ref _pauseBtnText, value); }
        public string PauseBtnTooltip { get => _pauseBtnTooltip; set => SetProperty(ref _pauseBtnTooltip, value); }
        public string RefreshTooltip { get => _refreshTooltip; set => SetProperty(ref _refreshTooltip, value); }
        public string SettingsTooltip { get => _settingsTooltip; set => SetProperty(ref _settingsTooltip, value); }
        public string QuitTooltip { get => _quitTooltip; set => SetProperty(ref _quitTooltip, value); }
        public string EmptyStateTitle { get => _emptyStateTitle; set => SetProperty(ref _emptyStateTitle, value); }
        public string EmptyStateDesc { get => _emptyStateDesc; set => SetProperty(ref _emptyStateDesc, value); }
        public string CurrentClipboardText { get => _currentClipboardText; set => SetProperty(ref _currentClipboardText, value); }
        public string CopyOriginalTooltip { get => _copyOriginalTooltip; set => SetProperty(ref _copyOriginalTooltip, value); }
        public string CopyResultTooltip { get => _copyResultTooltip; set => SetProperty(ref _copyResultTooltip, value); }
        public string HistoryText { get => _historyText; set => SetProperty(ref _historyText, value); }
        public string ClearHistoryTooltip { get => _clearHistoryTooltip; set => SetProperty(ref _clearHistoryTooltip, value); }
        public string NoHistoryText { get => _noHistoryText; set => SetProperty(ref _noHistoryText, value); }
        public string CopyHistoryResultTooltip { get => _copyHistoryResultTooltip; set => SetProperty(ref _copyHistoryResultTooltip, value); }

        // Dynamic Visibilities
        public Visibility NoticeVisibility => string.IsNullOrEmpty(Model.CopyNotice) ? Visibility.Collapsed : Visibility.Visible;
        public Visibility EmptyStateVisibility => Model.Results.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        public Visibility ContentVisibility => Model.Results.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        public Visibility NoHistoryVisibility => Model.History.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        public ClipboardPopoverWindow(ClipboardModel model, AppPreferences preferences)
        {
            Model = model;
            Preferences = preferences;
            DataContext = this;

            InitializeComponent();

            Model.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName == nameof(Model.Results))
                {
                    OnPropertyChanged(nameof(EmptyStateVisibility));
                    OnPropertyChanged(nameof(ContentVisibility));
                }
                else if (e.PropertyName == nameof(Model.History))
                {
                    OnPropertyChanged(nameof(NoHistoryVisibility));
                }
                else if (e.PropertyName == nameof(Model.CopyNotice))
                {
                    OnPropertyChanged(nameof(NoticeVisibility));
                }
                else if (e.PropertyName == nameof(Model.IsPaused))
                {
                    UpdatePauseBtnState();
                }
            };

            UpdateThemeAndLanguage();
        }

        public void UpdateThemeAndLanguage()
        {
            // 1. Language update
            PauseBtnTooltip = Preferences.Text(Model.IsPaused ? TextKey.Resume : TextKey.Pause);
            RefreshTooltip = Preferences.Text(TextKey.RefreshHistory);
            SettingsTooltip = Preferences.Text(TextKey.OpenSettings);
            QuitTooltip = Preferences.Text(TextKey.Quit);

            UpdatePauseBtnState();

            EmptyStateTitle = Preferences.Text(Model.IsPaused ? TextKey.Paused : TextKey.Waiting);
            EmptyStateDesc = Preferences.Text(TextKey.EmptyHint);
            CurrentClipboardText = Preferences.Text(TextKey.CurrentClipboard);
            CopyOriginalTooltip = Preferences.Text(TextKey.CopyOriginal);
            CopyResultTooltip = Preferences.Text(TextKey.CopyResult);
            HistoryText = Preferences.Text(TextKey.History);
            ClearHistoryTooltip = Preferences.Text(TextKey.ClearHistory);
            NoHistoryText = Preferences.Text(TextKey.NoHistory);
            CopyHistoryResultTooltip = Preferences.Text(TextKey.CopyHistoryResult);

            // 2. Theme update (Color Scheme)
            if (Preferences.Theme == AppTheme.Light)
            {
                WindowBackground = new SolidColorBrush(Color.FromRgb(0xF4, 0xF7, 0xF6));
                HeaderBackground = new SolidColorBrush(Color.FromRgb(0x10, 0x56, 0x60));
                CardBackground = Brushes.White;
                BorderBrushColor = new SolidColorBrush(Color.FromRgb(0xD0, 0xDF, 0xDE));
                TextPrimaryBrush = new SolidColorBrush(Color.FromRgb(0x14, 0x21, 0x22));
                TextSecondaryBrush = new SolidColorBrush(Color.FromRgb(0x4C, 0x61, 0x63));
                AccentBrush = new SolidColorBrush(Color.FromRgb(0x1A, 0x7E, 0x8C));
            }
            else
            {
                WindowBackground = new SolidColorBrush(Color.FromRgb(0x10, 0x13, 0x14));
                HeaderBackground = new SolidColorBrush(Color.FromRgb(0x0D, 0x3D, 0x4A));
                CardBackground = new SolidColorBrush(Color.FromRgb(0x1A, 0x21, 0x24));
                BorderBrushColor = new SolidColorBrush(Color.FromRgb(0x32, 0x3E, 0x42));
                TextPrimaryBrush = Brushes.White;
                TextSecondaryBrush = new SolidColorBrush(Color.FromRgb(0xB5, 0xC7, 0xC9));
                AccentBrush = new SolidColorBrush(Color.FromRgb(0x14, 0x6B, 0x78));
            }

            // Force refresh UI list bindings
            OnPropertyChanged(nameof(Model));
        }

        private void UpdatePauseBtnState()
        {
            PauseBtnText = Model.IsPaused ? "" : ""; // Segoe MDL2 Assets play / pause icons
            PauseBtnTooltip = Preferences.Text(Model.IsPaused ? TextKey.Resume : TextKey.Pause);
            EmptyStateTitle = Preferences.Text(Model.IsPaused ? TextKey.Paused : TextKey.Waiting);
        }

        private void Window_Deactivated(object sender, EventArgs e)
        {
            Hide();
        }

        private void BtnPause_Click(object sender, RoutedEventArgs e)
        {
            Model.TogglePaused();
        }

        private void BtnRefresh_Click(object sender, RoutedEventArgs e)
        {
            Model.RefreshHistory();
        }

        private void BtnSettings_Click(object sender, RoutedEventArgs e)
        {
            Hide();
            ((App)Application.Current).ShowSettings();
        }

        private void BtnQuit_Click(object sender, RoutedEventArgs e)
        {
            Application.Current.Shutdown();
        }

        private void BtnCopyOriginal_Click(object sender, RoutedEventArgs e)
        {
            Model.Copy(Model.CurrentContent);
        }

        private void BtnCopyResult_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is ParseResult res)
            {
                Model.Copy(res.Parsed);
            }
        }

        private void BtnCopyHistoryResult_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is HistoryResult res)
            {
                Model.Copy(res.Parsed);
            }
        }

        private void BtnClearHistory_Click(object sender, RoutedEventArgs e)
        {
            Model.ClearHistory();
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
