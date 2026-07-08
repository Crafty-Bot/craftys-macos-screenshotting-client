using System.Text.Json;
using System.Text.RegularExpressions;
using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public static class ZiplineUploadUtilities
{
    public static Uri EndpointUrl(string rawEndpoint)
    {
        if (!Uri.TryCreate(rawEndpoint, UriKind.Absolute, out var uri) ||
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(uri.Host))
        {
            throw new UploadException("Endpoint is not a valid HTTPS URL.");
        }

        var builder = new UriBuilder(uri)
        {
            Query = string.Empty,
            Fragment = string.Empty
        };

        var basePath = builder.Path;
        if (basePath == "/")
        {
            basePath = string.Empty;
        }

        if (basePath.Length > 1 && basePath.EndsWith('/'))
        {
            basePath = basePath[..^1];
        }

        basePath = StripSuffix(basePath, "/api/upload");
        builder.Path = string.IsNullOrEmpty(basePath) ? "/api/upload" : basePath + "/api/upload";
        return builder.Uri;
    }

    public static string MultipartSafeFilename(string raw)
    {
        var cleaned = Regex.Replace(raw, "[\"\\\\\r\n]", "_").Trim();
        var meaningful = cleaned.Trim('_');
        return meaningful.Length == 0 ? "file.bin" : cleaned;
    }

    public static ZiplineFilenameHeaders FilenameHeaders(string filename)
    {
        var cleaned = MultipartSafeFilename(filename);
        var extension = Path.GetExtension(cleaned).Trim('.', ' ');
        var basename = Path.GetFileNameWithoutExtension(cleaned).Trim();
        return new ZiplineFilenameHeaders(
            string.IsNullOrEmpty(basename) ? cleaned : basename,
            string.IsNullOrEmpty(extension) ? null : extension);
    }

    public static ZiplineUploadResponse ParseUploadResponse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new UploadException("Zipline response was not a JSON object.");
        }

        DateTimeOffset? deletesAt = TryReadDate(root, "deletesAt") ?? TryReadDate(root, "deletes_at");
        if (root.TryGetProperty("files", out var files) && files.ValueKind == JsonValueKind.Array)
        {
            var first = files.EnumerateArray().FirstOrDefault();
            if (first.ValueKind == JsonValueKind.Object)
            {
                deletesAt ??= TryReadDate(first, "deletesAt") ?? TryReadDate(first, "deletes_at");
                var nestedUrl = TryReadString(first, "url") ?? TryReadString(first, "link");
                if (!string.IsNullOrWhiteSpace(nestedUrl))
                {
                    return new ZiplineUploadResponse(nestedUrl, deletesAt);
                }
            }
        }

        var url = TryReadString(root, "url");
        if (!string.IsNullOrWhiteSpace(url))
        {
            return new ZiplineUploadResponse(url, deletesAt);
        }

        throw new UploadException("Zipline response did not include a URL.");
    }

    public static EndpointValidationResult EndpointValidationResult(UploadBackend backend, int statusCode, string? body = null)
    {
        if (backend != UploadBackend.ZiplineV4)
        {
            return new EndpointValidationResult(false, "S3 validation must use S3 backend probe.");
        }

        if ((statusCode >= 200 && statusCode <= 299) || statusCode is 401 or 403 or 404 or 405)
        {
            return statusCode == 404
                ? new EndpointValidationResult(true, "Zipline endpoint responded (HTTP 404). Assuming reachable.")
                : new EndpointValidationResult(true, "Zipline endpoint is reachable.");
        }

        return new EndpointValidationResult(false, $"Zipline probe returned HTTP {statusCode}.");
    }

    private static string StripSuffix(string basePath, string suffix)
    {
        if (basePath == suffix)
        {
            return string.Empty;
        }

        if (basePath.EndsWith(suffix, StringComparison.Ordinal))
        {
            var trimmed = basePath[..^suffix.Length];
            if (trimmed == "/")
            {
                return string.Empty;
            }

            return trimmed.Length > 1 && trimmed.EndsWith('/') ? trimmed[..^1] : trimmed;
        }

        return basePath;
    }

    private static string? TryReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static DateTimeOffset? TryReadDate(JsonElement element, string name)
    {
        var raw = TryReadString(element, name);
        return DateTimeOffset.TryParse(raw, out var parsed) ? parsed.ToUniversalTime() : null;
    }
}
