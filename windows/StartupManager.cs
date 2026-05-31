using System;
using Microsoft.Win32;

namespace MCGA
{
    public static class StartupManager
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "MCGA";

        public static bool IsEnabled()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false);
                return key?.GetValue(ValueName) is string value && !string.IsNullOrWhiteSpace(value);
            }
            catch (Exception ex)
            {
                AppLogger.Error("Failed to read startup setting", ex);
                return false;
            }
        }

        public static void SetEnabled(bool enabled)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true)
                    ?? Registry.CurrentUser.CreateSubKey(RunKeyPath, true);

                if (enabled)
                {
                    string exePath = Environment.ProcessPath ?? System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? "";
                    if (string.IsNullOrWhiteSpace(exePath))
                    {
                        AppLogger.Error("Cannot enable startup because executable path is empty");
                        return;
                    }

                    key.SetValue(ValueName, $"\"{exePath}\"", RegistryValueKind.String);
                    AppLogger.Info($"Startup enabled. Path={exePath}");
                }
                else
                {
                    key.DeleteValue(ValueName, false);
                    AppLogger.Info("Startup disabled");
                }
            }
            catch (Exception ex)
            {
                AppLogger.Error("Failed to update startup setting", ex);
            }
        }
    }
}
