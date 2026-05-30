using System;
using System.Collections.Generic;
using System.Windows;
using MCGA.MCGACore;

namespace MCGA
{
    public partial class App : Application
    {
        public AppPreferences Preferences { get; private set; } = null!;
        public ClipboardModel Model { get; private set; } = null!;

        private TrayIconView? _trayIconView;
        private ClipboardPopoverWindow? _popoverWindow;
        private SettingsWindow? _settingsWindow;
        private readonly List<FloatingOverlayWindow> _activeOverlays = new List<FloatingOverlayWindow>();

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            ShutdownMode = ShutdownMode.OnExplicitShutdown;

            Preferences = new AppPreferences();
            Model = new ClipboardModel(Preferences);

            _trayIconView = new TrayIconView();

            Model.OnNewResults = (content, results) =>
            {
                ShowFloatingOverlay(content, results);
            };

            Model.Start();
        }

        public void ShowPopover()
        {
            if (_popoverWindow == null)
            {
                _popoverWindow = new ClipboardPopoverWindow(Model, Preferences);
                _popoverWindow.Closed += (s, e) => _popoverWindow = null;
            }

            if (_popoverWindow.IsVisible)
            {
                _popoverWindow.Hide();
            }
            else
            {
                PositionWindowNearMouse(_popoverWindow, 460, 560);
                _popoverWindow.Show();
                _popoverWindow.Activate();
            }
        }

        public void ShowSettings()
        {
            if (_settingsWindow != null)
            {
                _settingsWindow.Activate();
                if (_settingsWindow.WindowState == WindowState.Minimized)
                {
                    _settingsWindow.WindowState = WindowState.Normal;
                }
                return;
            }

            _settingsWindow = new SettingsWindow(Model, Preferences);
            _settingsWindow.Closed += (s, e) => _settingsWindow = null;
            _settingsWindow.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            _settingsWindow.Show();
            _settingsWindow.Activate();
        }

        public void CloseSettings()
        {
            _settingsWindow?.Close();
        }

        public void NotifyPreferenceChanged()
        {
            _popoverWindow?.UpdateThemeAndLanguage();
            _settingsWindow?.UpdateThemeAndLanguage();
            foreach (var overlay in _activeOverlays)
            {
                overlay.UpdateThemeAndLanguage();
            }
        }

        private void ShowFloatingOverlay(string content, List<ParseResult> results)
        {
            Dispatcher.Invoke(() =>
            {
                while (_activeOverlays.Count >= 2)
                {
                    var oldest = _activeOverlays[0];
                    _activeOverlays.RemoveAt(0);
                    oldest.Close();
                }

                var overlay = new FloatingOverlayWindow(content, results, Preferences);
                _activeOverlays.Add(overlay);

                UpdateOverlayPositions();

                overlay.Show();
                overlay.StartTimer();
            });
        }

        public void RemoveOverlay(FloatingOverlayWindow window)
        {
            Dispatcher.Invoke(() =>
            {
                if (_activeOverlays.Remove(window))
                {
                    window.Close();
                    UpdateOverlayPositions();
                }
            });
        }

        private void UpdateOverlayPositions()
        {
            var workArea = SystemParameters.WorkArea;
            double width = 420;
            double height = 300;
            double gap = 12;
            double marginRight = 16;
            double marginBottom = 16;

            for (int i = 0; i < _activeOverlays.Count; i++)
            {
                var overlay = _activeOverlays[i];
                double x = workArea.Right - width - marginRight;
                double y = workArea.Bottom - (height + gap) * (i + 1) - marginBottom + gap;

                overlay.Left = x;
                overlay.Top = y;
                overlay.Width = width;
                overlay.Height = height;
            }
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
        private static extern bool GetCursorPos(out Win32Point lppoint);

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct Win32Point
        {
            public int X;
            public int Y;
        }

        private (double ScaleX, double ScaleY) GetDpiScale()
        {
            try
            {
                using (var source = new System.Windows.Interop.HwndSource(new System.Windows.Interop.HwndSourceParameters()))
                {
                    if (source.CompositionTarget != null)
                    {
                        return (source.CompositionTarget.TransformToDevice.M11,
                                source.CompositionTarget.TransformToDevice.M22);
                    }
                }
            }
            catch
            {
                // Fallback
            }
            return (1.0, 1.0);
        }

        private void PositionWindowNearMouse(Window window, double width, double height)
        {
            window.Width = width;
            window.Height = height;

            GetCursorPos(out var mouse);
            var dpi = GetDpiScale();
            var workArea = SystemParameters.WorkArea;

            // Simple positioning: place window relative to cursor coordinates in DIPs
            double logicalMouseX = mouse.X / dpi.ScaleX;
            double logicalMouseY = mouse.Y / dpi.ScaleY;

            double x = logicalMouseX - width / 2;
            double y = logicalMouseY - height - 12; // place above mouse by default (for bottom-placed taskbars)

            // Clamp to screen working area to avoid offscreen positioning
            if (x < workArea.Left) x = workArea.Left + 8;
            if (x + width > workArea.Right) x = workArea.Right - width - 8;
            if (y < workArea.Top) y = workArea.Top + 8;
            if (y + height > workArea.Bottom)
            {
                // If it goes below working area (e.g. top taskbar), place below mouse
                y = logicalMouseY + 12;
            }

            window.Left = x;
            window.Top = y;
        }

        protected override void OnExit(ExitEventArgs e)
        {
            _trayIconView?.TrayIcon.Dispose();
            base.OnExit(e);
        }
    }
}
