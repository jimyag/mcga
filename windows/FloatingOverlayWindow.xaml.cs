using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using MCGA.MCGACore;

namespace MCGA
{
    public partial class FloatingOverlayWindow : Window, INotifyPropertyChanged
    {
        public string ContentRaw { get; }
        public List<ParseResult> Results { get; }
        public AppPreferences Preferences { get; }

        private Brush _windowBackground = Brushes.White;
        private Brush _headerBackground = Brushes.Teal;
        private Brush _cardBackground = Brushes.White;
        private Brush _borderBrushColor = Brushes.LightGray;
        private Brush _textPrimaryBrush = Brushes.Black;
        private Brush _textSecondaryBrush = Brushes.DarkGray;

        public Brush WindowBackground { get => _windowBackground; set => SetProperty(ref _windowBackground, value); }
        public Brush HeaderBackground { get => _headerBackground; set => SetProperty(ref _headerBackground, value); }
        public Brush CardBackground { get => _cardBackground; set => SetProperty(ref _cardBackground, value); }
        public Brush BorderBrushColor { get => _borderBrushColor; set => SetProperty(ref _borderBrushColor, value); }
        public Brush TextPrimaryBrush { get => _textPrimaryBrush; set => SetProperty(ref _textPrimaryBrush, value); }
        public Brush TextSecondaryBrush { get => _textSecondaryBrush; set => SetProperty(ref _textSecondaryBrush, value); }

        // Localized Strings
        private string _headerText = "";
        private string _historyTooltip = "";
        private string _copyFirstTooltip = "";
        private string _copyResultTooltip = "";

        public string HeaderText { get => _headerText; set => SetProperty(ref _headerText, value); }
        public string HistoryTooltip { get => _historyTooltip; set => SetProperty(ref _historyTooltip, value); }
        public string CopyFirstTooltip { get => _copyFirstTooltip; set => SetProperty(ref _copyFirstTooltip, value); }
        public string CopyResultTooltip { get => _copyResultTooltip; set => SetProperty(ref _copyResultTooltip, value); }

        private readonly DispatcherTimer _dismissTimer;
        private bool _isMouseOver;
        private bool _isFadingOut;

        // Win32 imports to make window non-activating (doesn't take focus)
        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hwnd, int index);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_NOACTIVATE = 0x08000000;

        public FloatingOverlayWindow(string content, List<ParseResult> results, AppPreferences preferences)
        {
            ContentRaw = content;
            Results = results;
            Preferences = preferences;
            DataContext = this;

            InitializeComponent();

            _dismissTimer = new DispatcherTimer(DispatcherPriority.Normal)
            {
                Interval = TimeSpan.FromSeconds(5)
            };
            _dismissTimer.Tick += DismissTimer_Tick;

            UpdateThemeAndLanguage();
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            var helper = new WindowInteropHelper(this);
            int exStyle = GetWindowLong(helper.Handle, GWL_EXSTYLE);
            SetWindowLong(helper.Handle, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE);
        }

        public void StartTimer()
        {
            _dismissTimer.Start();
        }

        public void UpdateThemeAndLanguage()
        {
            // 1. Update text
            string firstParser = Results.FirstOrDefault()?.ParserName ?? "MCGA";
            string preview = ContentRaw.Replace("\r", " ").Replace("\n", " ");
            if (preview.Length > 40)
            {
                preview = preview.Substring(0, 40) + "...";
            }
            HeaderText = $"[{firstParser}] {preview}";

            HistoryTooltip = Preferences.Text(TextKey.History);
            CopyFirstTooltip = Preferences.Text(TextKey.CopyFirstResult);
            CopyResultTooltip = Preferences.Text(TextKey.CopyResult);

            // 2. Update colors
            if (Preferences.Theme == AppTheme.Light)
            {
                WindowBackground = new SolidColorBrush(Color.FromArgb(0xFA, 0xF4, 0xF7, 0xF6));
                HeaderBackground = new SolidColorBrush(Color.FromRgb(0x10, 0x34, 0x38));
                CardBackground = new SolidColorBrush(Color.FromArgb(0xEB, 0xFF, 0xFF, 0xFF));
                BorderBrushColor = new SolidColorBrush(Color.FromArgb(0x47, 0x59, 0x77, 0x7A));
                TextPrimaryBrush = new SolidColorBrush(Color.FromRgb(0x08, 0x13, 0x14));
                TextSecondaryBrush = new SolidColorBrush(Color.FromRgb(0x30, 0x38, 0x39));
            }
            else
            {
                WindowBackground = new SolidColorBrush(Color.FromArgb(0xFA, 0x10, 0x13, 0x14));
                HeaderBackground = new SolidColorBrush(Color.FromRgb(0x05, 0x24, 0x29));
                CardBackground = new SolidColorBrush(Color.FromArgb(0xF5, 0x16, 0x20, 0x21));
                BorderBrushColor = new SolidColorBrush(Color.FromArgb(0x28, 0xFF, 0xFF, 0xFF));
                TextPrimaryBrush = new SolidColorBrush(Color.FromArgb(0xEB, 0xFF, 0xFF, 0xFF));
                TextSecondaryBrush = new SolidColorBrush(Color.FromArgb(0xAD, 0xFF, 0xFF, 0xFF));
            }
        }

        private void DismissTimer_Tick(object? sender, EventArgs e)
        {
            if (!_isMouseOver)
            {
                StartFadeOut();
            }
        }

        private void StartFadeOut()
        {
            if (_isFadingOut) return;
            _isFadingOut = true;
            _dismissTimer.Stop();

            var anim = new DoubleAnimation(0.0, TimeSpan.FromMilliseconds(300));
            anim.Completed += (s, e) =>
            {
                ((App)Application.Current).RemoveOverlay(this);
            };
            BeginAnimation(OpacityProperty, anim);
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            Opacity = 0.0;
            var anim = new DoubleAnimation(0.98, TimeSpan.FromMilliseconds(200));
            BeginAnimation(OpacityProperty, anim);
        }

        private void Window_MouseEnter(object sender, MouseEventArgs e)
        {
            _isMouseOver = true;
            _dismissTimer.Stop();
        }

        private void Window_MouseLeave(object sender, MouseEventArgs e)
        {
            _isMouseOver = false;
            // Dismiss after 2 seconds when mouse leaves
            _dismissTimer.Interval = TimeSpan.FromSeconds(2);
            _dismissTimer.Start();
        }

        private void BtnHistory_Click(object sender, RoutedEventArgs e)
        {
            ((App)Application.Current).ShowPopover();
        }

        private void BtnCopyFirst_Click(object sender, RoutedEventArgs e)
        {
            var first = Results.FirstOrDefault();
            if (first != null)
            {
                ((App)Application.Current).Model.Copy(first.Parsed);
            }
        }

        private void BtnCopyResult_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.DataContext is ParseResult res)
            {
                ((App)Application.Current).Model.Copy(res.Parsed);
            }
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
