using System.Diagnostics;
using System.IO;
using CraftyCannon.Core;

namespace CraftyCannon.App;

public sealed class WindowsFileRevealLauncher : IFileRevealLauncher
{
    public bool TryRevealFile(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath) && !Directory.Exists(fullPath))
        {
            return false;
        }

        try
        {
            var arguments = File.Exists(fullPath)
                ? $"/select,\"{fullPath}\""
                : $"\"{fullPath}\"";
            Process.Start(new ProcessStartInfo("explorer.exe", arguments)
            {
                UseShellExecute = true
            });
            return true;
        }
        catch
        {
            return false;
        }
    }
}
