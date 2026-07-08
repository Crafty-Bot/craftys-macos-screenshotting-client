using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public sealed record UploadFileNamingOptions(
    bool UseNamePattern = false,
    bool UseRandom16Name = false,
    string Pattern = "{date}-{rand}",
    int AutoIncrement = 1,
    bool ReplaceProblematicCharacters = true);

public static class UploadFilenameGenerator
{
    private const string Alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";

    public static string? GenerateRemoteFilename(string filePath, UploadFileNamingOptions? options, DateTimeOffset now, string? randomToken = null)
    {
        if (options is null || (!options.UseNamePattern && !options.UseRandom16Name))
        {
            return null;
        }

        var baseName = options.UseRandom16Name
            ? RandomToken(16, randomToken)
            : PatternBase(filePath, options, now, randomToken);
        var extension = Path.GetExtension(filePath).Trim().TrimStart('.').ToLowerInvariant();
        return string.IsNullOrWhiteSpace(extension) ? baseName : baseName + "." + extension;
    }

    public static string PatternBase(string filePath, UploadFileNamingOptions options, DateTimeOffset now, string? randomToken = null)
    {
        var sourceBase = Path.GetFileNameWithoutExtension(filePath);
        var pattern = string.IsNullOrWhiteSpace(options.Pattern) ? "{date}-{rand}" : options.Pattern.Trim();
        pattern = pattern.Replace("{date}", now.ToString("yyyy-MM-dd"), StringComparison.Ordinal);
        pattern = pattern.Replace("{time}", now.ToString("HH-mm-ss"), StringComparison.Ordinal);
        pattern = pattern.Replace("{datetime}", now.ToString("yyyy-MM-dd_HH-mm-ss"), StringComparison.Ordinal);
        pattern = pattern.Replace("{rand}", RandomToken(6, randomToken), StringComparison.Ordinal);
        pattern = pattern.Replace("{name}", sourceBase, StringComparison.Ordinal);
        pattern = pattern.Replace("{inc}", Math.Max(1, options.AutoIncrement).ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal);
        return SanitizeFilenameComponent(pattern, options.ReplaceProblematicCharacters);
    }

    public static string SanitizeFilenameComponent(string raw, bool aggressive)
    {
        var sanitized = raw;
        foreach (var invalid in "/\\?%*|\"<>:")
        {
            sanitized = sanitized.Replace(invalid, '-');
        }

        sanitized = sanitized.Replace('\n', '-').Replace('\r', '-');
        if (aggressive)
        {
            sanitized = sanitized.Replace(' ', '-').Replace('\t', '-');
            while (sanitized.Contains("--", StringComparison.Ordinal))
            {
                sanitized = sanitized.Replace("--", "-", StringComparison.Ordinal);
            }
        }

        var trimmed = sanitized.Trim('-', '_', '.', ' ');
        return string.IsNullOrWhiteSpace(trimmed) ? "upload" : trimmed;
    }

    private static string RandomToken(int length, string? randomToken)
    {
        var normalized = new string((randomToken ?? string.Empty).Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
        if (normalized.Length >= length)
        {
            return normalized[..length];
        }

        var random = new Random();
        return normalized + new string(Enumerable.Range(0, length - normalized.Length).Select(_ => Alphabet[random.Next(Alphabet.Length)]).ToArray());
    }
}