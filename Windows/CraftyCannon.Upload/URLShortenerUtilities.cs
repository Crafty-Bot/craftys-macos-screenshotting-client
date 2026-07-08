using System.Text.Json;

namespace CraftyCannon.Upload;

public static class URLShortenerUtilities
{
    public static ShortenerHttpRequest BuildRequest(string urlString, ShortenerRequest config)
    {
        if (!IsHttpUrl(urlString))
        {
            throw new UploadException("URL is invalid.");
        }

        return config.Provider switch
        {
            ShortenerProvider.TinyUrl => new ShortenerHttpRequest(
                new Uri("https://tinyurl.com/api-create.php?url=" + Uri.EscapeDataString(urlString)),
                Timeout: TimeSpan.FromSeconds(10)),
            ShortenerProvider.CustomGetTemplate => BuildCustomTemplateRequest(urlString, config.CustomGetTemplate),
            _ => throw new UploadException("Unknown shortener provider.")
        };
    }

    public static string ParseTinyUrlResponse(int statusCode, string body)
    {
        if (statusCode < 200 || statusCode > 299)
        {
            throw new UploadException($"TinyURL request failed (HTTP {statusCode})");
        }

        var trimmed = body.Trim();
        if (!IsHttpUrl(trimmed))
        {
            throw new UploadException("TinyURL response did not contain a URL");
        }

        return trimmed;
    }

    public static string ParseCustomResponse(int statusCode, string body)
    {
        if (statusCode < 200 || statusCode > 299)
        {
            throw new UploadException($"Custom shortener failed (HTTP {statusCode})");
        }

        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                var url = TryReadString(document.RootElement, "url") ?? TryReadString(document.RootElement, "shortUrl");
                if (!string.IsNullOrWhiteSpace(url))
                {
                    return url;
                }
            }
        }
        catch (JsonException)
        {
            // Fall through to plaintext parsing.
        }

        var trimmed = body.Trim();
        if (IsHttpUrl(trimmed))
        {
            return trimmed;
        }

        throw new UploadException("Custom shortener response did not include a URL");
    }

    public static string StrictQueryEncode(string value)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(value);
        var builder = new System.Text.StringBuilder(bytes.Length);
        foreach (var b in bytes)
        {
            var c = (char)b;
            if ((c >= 'A' && c <= 'Z') ||
                (c >= 'a' && c <= 'z') ||
                (c >= '0' && c <= '9') ||
                c is '-' or '.' or '_' or '~')
            {
                builder.Append(c);
            }
            else
            {
                builder.Append('%').Append(b.ToString("X2"));
            }
        }

        return builder.ToString();
    }

    private static ShortenerHttpRequest BuildCustomTemplateRequest(string urlString, string? template)
    {
        var trimmed = (template ?? string.Empty).Trim();
        if (trimmed.Length == 0 || !trimmed.Contains("{url}", StringComparison.Ordinal))
        {
            throw new UploadException("Custom shortener template is invalid.");
        }

        var endpoint = trimmed.Replace("{url}", StrictQueryEncode(urlString), StringComparison.Ordinal);
        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var uri))
        {
            throw new UploadException("Custom shortener template produced an invalid URL.");
        }

        return new ShortenerHttpRequest(uri, Timeout: TimeSpan.FromSeconds(10));
    }

    private static bool IsHttpUrl(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
        (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);

    private static string? TryReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}
