using System;
using System.Diagnostics;
using System.Threading;
using System.Windows;

namespace MCGA
{
    public static class Program
    {
        private static Mutex? _singleInstanceMutex;
        private static bool _ownsSingleInstanceMutex;
        private const string SingleInstanceMutexName = @"Local\MCGA.Windows.SingleInstance";

        [STAThread]
        public static int Main(string[] args)
        {
            AppLogger.Initialize();
            AppLogger.Info($"Program.Main entered. Args={args.Length}, BaseDirectory={AppContext.BaseDirectory}");

            try
            {
                _singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out bool createdNew);
                if (!createdNew)
                {
                    AppLogger.Info("Another MCGA instance is already running; terminating old instance");
                    TerminateExistingInstances();
                    AcquireSingleInstanceMutex();
                }
                else
                {
                    _ownsSingleInstanceMutex = true;
                }

                var app = new App();
                AppLogger.Info("App instance created");

                app.InitializeComponent();
                AppLogger.Info("App InitializeComponent completed");

                int exitCode = app.Run();
                AppLogger.Info($"App.Run returned. ExitCode={exitCode}");
                return exitCode;
            }
            catch (Exception ex)
            {
                AppLogger.Error("Fatal exception in Program.Main", ex);
                MessageBox.Show(
                    $"MCGA crashed during startup. Log: {AppLogger.LogPath}\n\n{ex}",
                    "MCGA startup error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                return 1;
            }
            finally
            {
                if (_singleInstanceMutex != null)
                {
                    if (_ownsSingleInstanceMutex)
                    {
                        _singleInstanceMutex.ReleaseMutex();
                    }
                    _singleInstanceMutex.Dispose();
                    _singleInstanceMutex = null;
                    _ownsSingleInstanceMutex = false;
                    AppLogger.Info("Single instance mutex released");
                }
            }
        }

        private static void AcquireSingleInstanceMutex()
        {
            if (_singleInstanceMutex == null)
            {
                return;
            }

            try
            {
                _ownsSingleInstanceMutex = _singleInstanceMutex.WaitOne(TimeSpan.FromSeconds(5));
                AppLogger.Info($"Single instance mutex reacquired after terminating old instance. Acquired={_ownsSingleInstanceMutex}");
            }
            catch (AbandonedMutexException)
            {
                _ownsSingleInstanceMutex = true;
                AppLogger.Info("Single instance mutex was abandoned by old instance and is now owned");
            }

            if (!_ownsSingleInstanceMutex)
            {
                throw new InvalidOperationException("Could not acquire MCGA single instance mutex after terminating old instance.");
            }
        }

        private static void TerminateExistingInstances()
        {
            int currentProcessId = Environment.ProcessId;
            string currentPath = Environment.ProcessPath ?? "";
            string currentName = Process.GetCurrentProcess().ProcessName;

            foreach (var process in Process.GetProcesses())
            {
                try
                {
                    if (process.Id == currentProcessId)
                    {
                        continue;
                    }

                    if (!LooksLikeMcgaProcess(process, currentName, currentPath))
                    {
                        continue;
                    }

                    AppLogger.Info($"Terminating old MCGA process. Pid={process.Id}, Name={process.ProcessName}");
                    process.Kill();
                    process.WaitForExit(3000);
                    AppLogger.Info($"Old MCGA process terminated. Pid={process.Id}, HasExited={process.HasExited}");
                }
                catch (Exception ex)
                {
                    AppLogger.Error($"Failed to terminate candidate old MCGA process. Pid={SafeProcessId(process)}", ex);
                }
                finally
                {
                    process.Dispose();
                }
            }
        }

        private static bool LooksLikeMcgaProcess(Process process, string currentName, string currentPath)
        {
            if (process.ProcessName.Equals(currentName, StringComparison.OrdinalIgnoreCase)
                || process.ProcessName.StartsWith("MCGA", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            try
            {
                string? path = process.MainModule?.FileName;
                return !string.IsNullOrWhiteSpace(currentPath)
                    && !string.IsNullOrWhiteSpace(path)
                    && path.Equals(currentPath, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        private static int SafeProcessId(Process process)
        {
            try
            {
                return process.Id;
            }
            catch
            {
                return -1;
            }
        }
    }
}
