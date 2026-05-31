using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Windows;
using MCGA.MCGACore;

namespace MCGA
{
    public partial class App : System.Windows.Application
    {
        public AppPreferences Preferences { get; private set; } = null!;
        public ClipboardModel Model { get; private set; } = null!;

        private TrayIconView? _trayIconView;
        private ClipboardPopoverWindow? _popoverWindow;
        private SettingsWindow? _settingsWindow;
        private readonly List<FloatingOverlayWindow> _activeOverlays = new List<FloatingOverlayWindow>();

        public App()
        {
            AppLogger.Initialize();
            AppLogger.Info("App constructor started");

            DispatcherUnhandledException += (sender, args) =>
            {
                AppLogger.Error("Dispatcher unhandled exception", args.Exception);
            };

            AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
            {
                AppLogger.Error($"AppDomain unhandled exception. IsTerminating={args.IsTerminating}", args.ExceptionObject as Exception);
            };

            TaskScheduler.UnobservedTaskException += (sender, args) =>
            {
                AppLogger.Error("Unobserved task exception", args.Exception);
            };

            AppLogger.Info("App exception handlers registered");
        }

        protected override void OnStartup(StartupEventArgs e)
        {
            AppLogger.Info("OnStartup started");

            try
            {
                base.OnStartup(e);
                AppLogger.Info("Base OnStartup completed");

                ShutdownMode = ShutdownMode.OnExplicitShutdown;
                AppLogger.Info("ShutdownMode set to OnExplicitShutdown");

                Preferences = new AppPreferences();
                AppLogger.Info("Preferences loaded");

                Model = new ClipboardModel(Preferences);
                AppLogger.Info("Clipboard model created");

                _trayIconView = (TrayIconView)FindResource("TrayIconView");
                AppLogger.Info("Tray icon resource resolved");

                Model.OnNewResults = (content, results) =>
                {
                    AppLogger.Info($"New parser results received. ContentLength={content.Length}, ResultCount={results.Count}");
                    ShowFloatingOverlay(content, results);
                };

                Model.Start();
                AppLogger.Info($"Application startup completed. LogPath={AppLogger.LogPath}");
            }
            catch (Exception ex)
            {
                AppLogger.Error("OnStartup failed", ex);
                throw;
            }
        }

        public void ShowPopover()
        {
            AppLogger.Info("ShowPopover requested");

            EnsurePopoverWindow();

            if (_popoverWindow!.IsVisible)
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

        private void EnsurePopoverWindow()
        {
            if (_popoverWindow != null)
            {
                return;
            }

            _popoverWindow = new ClipboardPopoverWindow(Model, Preferences);
            _popoverWindow.Closed += (s, e) => _popoverWindow = null;
            AppLogger.Info("Popover window created");
        }

        public void ShowSettings()
        {
            AppLogger.Info("ShowSettings requested");

            if (_settingsWindow != null)
            {
                if (!_settingsWindow.IsVisible)
                {
                    _settingsWindow.Show();
                }
                if (_settingsWindow.WindowState == WindowState.Minimized)
                {
                    _settingsWindow.WindowState = WindowState.Normal;
                }
                _settingsWindow.Activate();
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
            _settingsWindow?.CloseForExit();
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
                AppLogger.Info($"Showing floating overlay. ActiveOverlayCount={_activeOverlays.Count}, ResultCount={results.Count}");

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
                AppLogger.Info($"Removing floating overlay. ActiveOverlayCount={_activeOverlays.Count}");

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
            AppLogger.Info($"OnExit started. ApplicationExitCode={e.ApplicationExitCode}");
            CloseSettings();
            _trayIconView?.Dispose();
            AppLogger.Info("Tray icon disposed");
            base.OnExit(e);
            AppLogger.Info("OnExit completed");
        }
    }
}
