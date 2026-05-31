using System;
using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Resources;
using Forms = System.Windows.Forms;

namespace MCGA
{
    public partial class TrayIconView : System.Windows.Controls.UserControl, IDisposable
    {
        private Icon? _icon;
        private Forms.ContextMenuStrip? _contextMenu;

        public Forms.NotifyIcon TrayIcon { get; private set; } = null!;

        public TrayIconView()
        {
            AppLogger.Info("TrayIconView constructor started");
            InitializeComponent();
            CreateTrayIcon();
            AppLogger.Info("TrayIconView initialized");
        }

        private void CreateTrayIcon()
        {
            try
            {
                _icon = LoadTrayIcon();
                _contextMenu = new Forms.ContextMenuStrip();
                _contextMenu.Items.Add("Settings", null, (_, _) => ShowSettings());
                _contextMenu.Items.Add(new Forms.ToolStripSeparator());
                _contextMenu.Items.Add("Quit", null, (_, _) => Shutdown());

                TrayIcon = new Forms.NotifyIcon
                {
                    Icon = _icon,
                    Text = "MCGA - Clipboard Guard",
                    ContextMenuStrip = _contextMenu,
                    Visible = true
                };
                TrayIcon.MouseUp += OnTrayIconMouseUp;
                AppLogger.Info("WinForms NotifyIcon created and made visible");
            }
            catch (Exception ex)
            {
                AppLogger.Error("Failed to create WinForms NotifyIcon", ex);
            }
        }

        private Icon LoadTrayIcon()
        {
            StreamResourceInfo? info = System.Windows.Application.GetResourceStream(
                new Uri("pack://application:,,,/tray_icon.ico", UriKind.Absolute));
            if (info?.Stream == null)
            {
                AppLogger.Error("Tray icon resource stream is missing; using default application icon");
                return SystemIcons.Application;
            }

            using Stream stream = info.Stream;
            return new Icon(stream);
        }

        private void OnTrayIconMouseUp(object? sender, Forms.MouseEventArgs e)
        {
            if (e.Button == Forms.MouseButtons.Left)
            {
                AppLogger.Info("Tray icon left mouse up");
                ((App)System.Windows.Application.Current).ShowPopover();
            }
        }

        private void ShowSettings()
        {
            AppLogger.Info("Tray settings clicked");
            ((App)Application.Current).ShowSettings();
        }

        private void Shutdown()
        {
            AppLogger.Info("Tray quit clicked");
            Application.Current.Shutdown();
        }

        public void Dispose()
        {
            AppLogger.Info("Disposing tray icon view");
            if (TrayIcon != null)
            {
                TrayIcon.Visible = false;
                TrayIcon.Dispose();
            }
            _contextMenu?.Dispose();
            _icon?.Dispose();
        }
    }
}
