using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using MCGA.MCGACore;

namespace MCGA
{
    public partial class SettingsWindow : Window, INotifyPropertyChanged
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
        private string _settingsTitle = "";
        private string _languageText = "";
        private string _chineseText = "";
        private string _englishText = "";
        private string _themeText = "";
        private string _lightText = "";
        private string _darkText = "";
        private string _parsersText = "";
        private string _clipboardContentText = "";
        private string _expectedOutputText = "";

        public string SettingsTitle { get => _settingsTitle; set => SetProperty(ref _settingsTitle, value); }
        public string LanguageText { get => _languageText; set => SetProperty(ref _languageText, value); }
        public string ChineseText { get => _chineseText; set => SetProperty(ref _chineseText, value); }
        public string EnglishText { get => _englishText; set => SetProperty(ref _englishText, value); }
        public string ThemeText { get => _themeText; set => SetProperty(ref _themeText, value); }
        public string LightText { get => _lightText; set => SetProperty(ref _lightText, value); }
        public string DarkText { get => _darkText; set => SetProperty(ref _darkText, value); }
        public string ParsersText { get => _parsersText; set => SetProperty(ref _parsersText, value); }
        public string ClipboardContentText { get => _clipboardContentText; set => SetProperty(ref _clipboardContentText, value); }
        public string ExpectedOutputText { get => _expectedOutputText; set => SetProperty(ref _expectedOutputText, value); }

        // RadioButton Bindings
        public bool IsChineseChecked
        {
            get => Preferences.Language == AppLanguage.Zh;
            set
            {
                if (value)
                {
                    Preferences.Language = AppLanguage.Zh;
                    Preferences.Save();
                    ((App)Application.Current).NotifyPreferenceChanged();
                }
            }
        }

        public bool IsEnglishChecked
        {
            get => Preferences.Language == AppLanguage.En;
            set
            {
                if (value)
                {
                    Preferences.Language = AppLanguage.En;
                    Preferences.Save();
                    ((App)Application.Current).NotifyPreferenceChanged();
                }
            }
        }

        public bool IsLightChecked
        {
            get => Preferences.Theme == AppTheme.Light;
            set
            {
                if (value)
                {
                    Preferences.Theme = AppTheme.Light;
                    Preferences.Save();
                    ((App)Application.Current).NotifyPreferenceChanged();
                }
            }
        }

        public bool IsDarkChecked
        {
            get => Preferences.Theme == AppTheme.Dark;
            set
            {
                if (value)
                {
                    Preferences.Theme = AppTheme.Dark;
                    Preferences.Save();
                    ((App)Application.Current).NotifyPreferenceChanged();
                }
            }
        }

        public List<ParserViewModel> ParserViewModelList { get; }

        public SettingsWindow(ClipboardModel model, AppPreferences preferences)
        {
            Model = model;
            Preferences = preferences;
            
            // Build the parser view models list
            ParserViewModelList = Model.ParserInfos.Select(info => new ParserViewModel(info, Preferences)).ToList();

            DataContext = this;

            InitializeComponent();
            UpdateThemeAndLanguage();
        }

        public void UpdateThemeAndLanguage()
        {
            // 1. Strings update
            SettingsTitle = Preferences.Text(TextKey.Settings);
            LanguageText = Preferences.Text(TextKey.Language);
            ChineseText = Preferences.Text(TextKey.Chinese);
            EnglishText = Preferences.Text(TextKey.English);
            ThemeText = Preferences.Text(TextKey.Theme);
            LightText = Preferences.Text(TextKey.LightWord);
            DarkText = Preferences.Text(TextKey.DarkWord);
            ParsersText = Preferences.Text(TextKey.Parsers);
            ClipboardContentText = Preferences.Text(TextKey.ClipboardContent);
            ExpectedOutputText = Preferences.Text(TextKey.ExpectedOutput);

            // 2. Radio button selections (raising PropertyChanged)
            OnPropertyChanged(nameof(IsChineseChecked));
            OnPropertyChanged(nameof(IsEnglishChecked));
            OnPropertyChanged(nameof(IsLightChecked));
            OnPropertyChanged(nameof(IsDarkChecked));

            // 3. Colors update
            if (Preferences.Theme == AppTheme.Light)
            {
                WindowBackground = new SolidColorBrush(Color.FromRgb(0xF4, 0xF7, 0xF6));
                HeaderBackground = Brushes.White;
                CardBackground = Brushes.White;
                BorderBrushColor = new SolidColorBrush(Color.FromRgb(0xD0, 0xDF, 0xDE));
                TextPrimaryBrush = new SolidColorBrush(Color.FromRgb(0x14, 0x21, 0x22));
                TextSecondaryBrush = new SolidColorBrush(Color.FromRgb(0x4C, 0x61, 0x63));
                AccentBrush = new SolidColorBrush(Color.FromRgb(0x10, 0x56, 0x60));
            }
            else
            {
                WindowBackground = new SolidColorBrush(Color.FromRgb(0x10, 0x13, 0x14));
                HeaderBackground = new SolidColorBrush(Color.FromRgb(0x1A, 0x21, 0x24));
                CardBackground = new SolidColorBrush(Color.FromRgb(0x1A, 0x21, 0x24));
                BorderBrushColor = new SolidColorBrush(Color.FromRgb(0x32, 0x3E, 0x42));
                TextPrimaryBrush = Brushes.White;
                TextSecondaryBrush = new SolidColorBrush(Color.FromRgb(0xB5, 0xC7, 0xC9));
                AccentBrush = new SolidColorBrush(Color.FromRgb(0x14, 0x6B, 0x78));
            }

            // 4. Update individual parser VMs (for description & examples language switches)
            foreach (var vm in ParserViewModelList)
            {
                vm.RefreshLanguage();
            }
        }

        private void BtnClose_Click(object sender, RoutedEventArgs e)
        {
            Close();
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

    public class ParserViewModel : INotifyPropertyChanged
    {
        private readonly ParserInfo _info;
        private readonly AppPreferences _preferences;

        public string Name => _info.Name;
        public string Description => _preferences.Language == AppLanguage.Zh ? _info.ZhDescription : _info.EnDescription;
        public List<ParserExampleViewModel> Examples { get; }
        public Visibility ExamplesVisibility => Examples.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        public bool IsEnabled
        {
            get => _preferences.IsParserEnabled(Name);
            set
            {
                _preferences.SetParserEnabled(Name, value);
                OnPropertyChanged();
            }
        }

        public ParserViewModel(ParserInfo info, AppPreferences preferences)
        {
            _info = info;
            _preferences = preferences;
            Examples = _info.Examples.Select(ex => new ParserExampleViewModel(ex, _preferences)).ToList();
        }

        public void RefreshLanguage()
        {
            OnPropertyChanged(nameof(Description));
            OnPropertyChanged(nameof(IsEnabled));
            foreach (var ex in Examples)
            {
                ex.RefreshLanguage();
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected void OnPropertyChanged([CallerMemberName] string? name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }

    public class ParserExampleViewModel : INotifyPropertyChanged
    {
        private readonly ParserExample _example;
        private readonly AppPreferences _preferences;

        public string Input => _example.Input;
        public string Expected => _preferences.Language == AppLanguage.Zh ? _example.ZhExpected : _example.EnExpected;

        public ParserExampleViewModel(ParserExample example, AppPreferences preferences)
        {
            _example = example;
            _preferences = preferences;
        }

        public void RefreshLanguage()
        {
            OnPropertyChanged(nameof(Expected));
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected void OnPropertyChanged([CallerMemberName] string? name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }
}
