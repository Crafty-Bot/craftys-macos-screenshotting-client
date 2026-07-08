namespace CraftyCannon.Core;

public static class LocalMirrorFilename
{
    public static string? NormalizedPrefix(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var parts = new List<char>();
        var previousDash = false;
        foreach (var ch in value.Trim().ToLowerInvariant())
        {
            if (char.IsAsciiLetterOrDigit(ch))
            {
                parts.Add(ch);
                previousDash = false;
            }
            else if (!previousDash && parts.Count > 0)
            {
                parts.Add('-');
                previousDash = true;
            }
        }

        while (parts.Count > 0 && parts[^1] == '-')
        {
            parts.RemoveAt(parts.Count - 1);
        }

        return parts.Count == 0 ? null : new string([.. parts]);
    }

    public static string BuildFilename(string sourceFilePath, string? preferredPrefix, string fallbackPrefix = "capture", string? randomToken = null)
    {
        var extension = Path.GetExtension(sourceFilePath);
        extension = string.IsNullOrWhiteSpace(extension) ? "png" : extension.TrimStart('.').ToLowerInvariant();
        var token = NormalizedToken(randomToken);
        if (preferredPrefix is null)
        {
            return $"{token}.{extension}";
        }

        var prefix = NormalizedPrefix(preferredPrefix) ?? NormalizedPrefix(fallbackPrefix) ?? "capture";
        return $"{prefix}-{token}.{extension}";
    }

    private static string NormalizedToken(string? randomToken)
    {
        var raw = string.IsNullOrWhiteSpace(randomToken) ? Guid.NewGuid().ToString("N") : randomToken;
        var token = new string(raw.ToLowerInvariant().Where(char.IsAsciiLetterOrDigit).ToArray());
        if (token.Length == 0)
        {
            token = Guid.NewGuid().ToString("N");
        }

        return token[..Math.Min(8, token.Length)];
    }
}
