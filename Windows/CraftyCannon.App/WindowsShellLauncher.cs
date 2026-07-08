using System.Diagnostics;
using CraftyCannon.Core;

namespace CraftyCannon.App;

public sealed class WindowsShellLauncher : IShellLauncher
{
    public bool TryOpenUrl(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return false;
        }

        try
        {
            return Process.Start(new ProcessStartInfo(uri.AbsoluteUri)
            {
                UseShellExecute = true
            }) is not null;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}
