using System.Text.RegularExpressions;

namespace CraftyCannon.Upload;

public static class URLRewriteService
{
    public static string Apply(string url, bool enabled, string pattern, string replacement)
    {
        if (!enabled || string.IsNullOrEmpty(pattern))
        {
            return url;
        }

        try
        {
            return Regex.Replace(url, pattern, replacement ?? string.Empty);
        }
        catch (ArgumentException)
        {
            return url;
        }
    }
}

