using System.Configuration;
using System.Data;
using System.Windows;

namespace MCGA;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    private TrayIconView? _trayIconView;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Initialize the tray icon
        _trayIconView = new TrayIconView();
        
        // Prevent the application from closing when the "main window" is closed
        // since we don't have a main window.
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayIconView?.TrayIcon.Dispose();
        base.OnExit(e);
    }
}

