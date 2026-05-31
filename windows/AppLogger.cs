using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace MCGA
{
    public static class AppLogger
    {
        private static readonly object LockObject = new object();
        private static bool _initialized;
        private static readonly List<string> LogPaths = new List<string>();

        public static string LogPath
        {
            get
            {
                EnsureInitialized();
                return LogPaths.Count > 0 ? LogPaths[0] : "";
            }
        }

        public static void Initialize()
        {
            EnsureInitialized();
            Info("Logger initialized");
        }

        public static void Info(string message)
        {
            Write("INFO", message, null);
        }

        public static void Error(string message, Exception? exception = null)
        {
            Write("ERROR", message, exception);
        }

        private static void EnsureInitialized()
        {
            if (_initialized) return;

            lock (LockObject)
            {
                if (_initialized) return;

                string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                AddLogPath(AppContext.BaseDirectory);
                AddLogPath(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MCGA");
                AddLogPath(userProfile, ".local", "share", "mcga");
                AddLogPath(Path.GetTempPath(), "MCGA");
                _initialized = true;
            }
        }

        private static void AddLogPath(params string[] parts)
        {
            try
            {
                if (parts.Length == 0 || string.IsNullOrWhiteSpace(parts[0])) return;

                string dir = Path.Combine(parts);
                Directory.CreateDirectory(dir);
                string path = Path.Combine(dir, "mcga.log");
                if (!LogPaths.Contains(path))
                {
                    LogPaths.Add(path);
                }
            }
            catch
            {
                // Ignore unwritable locations and keep any other available target.
            }
        }

        private static void Write(string level, string message, Exception? exception)
        {
            try
            {
                EnsureInitialized();
                string line = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz} [{level}] [pid:{Environment.ProcessId}] [thread:{Thread.CurrentThread.ManagedThreadId}] {message}";
                if (exception != null)
                {
                    line += Environment.NewLine + exception;
                }

                lock (LockObject)
                {
                    foreach (var path in LogPaths)
                    {
                        try
                        {
                            File.AppendAllText(path, line + Environment.NewLine);
                        }
                        catch
                        {
                            // Keep writing to other locations.
                        }
                    }
                }
            }
            catch
            {
                // Logging must never crash the app.
            }
        }
    }
}
