using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public static class S3UploadUtilities
{
    public static S3EndpointInfo ParseEndpoint(string raw)
    {
        if (!Uri.TryCreate(raw, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp) ||
            string.IsNullOrWhiteSpace(uri.Host))
        {
            throw new UploadException("S3 endpoint is invalid.");
        }

        var basePath = uri.AbsolutePath == "/" ? string.Empty : uri.AbsolutePath.TrimEnd('/');
        return new S3EndpointInfo(uri.Scheme, uri.Host, uri.IsDefaultPort ? null : uri.Port, basePath);
    }

    public static string SafeFilename(string raw)
    {
        var baseName = raw.Split('/', '\\').LastOrDefault() ?? raw;
        var cleaned = Regex.Replace(baseName, "[^A-Za-z0-9._-]+", "_");
        var trimmed = cleaned.Trim('_');
        return trimmed.Length == 0 ? "file.bin" : trimmed[..Math.Min(180, trimmed.Length)];
    }

    public static string SanitizeContext(string? raw)
    {
        var cleaned = Regex.Replace((raw ?? string.Empty).Trim().ToLowerInvariant(), "[^a-z0-9]+", "-");
        cleaned = Regex.Replace(cleaned, "-+", "-").Trim('-');
        return cleaned[..Math.Min(64, cleaned.Length)];
    }

    public static string MakeObjectKey(
        DateTimeOffset date,
        string filename,
        string keyPrefix,
        string? uploadContext,
        string randomToken)
    {
        var dateFolder = date.UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var safeName = SafeFilename(filename);
        var random = Regex.Replace(randomToken, "[^A-Za-z0-9]", string.Empty).ToLowerInvariant();
        if (random.Length == 0)
        {
            random = Guid.NewGuid().ToString("N");
        }

        var context = SanitizeContext(uploadContext);
        var name = string.IsNullOrEmpty(context) ? $"{random}-{safeName}" : $"{context}-{random}-{safeName}";
        var prefix = keyPrefix.Trim().Trim('/');
        return string.IsNullOrEmpty(prefix) ? $"{dateFolder}/{name}" : $"{prefix}/{dateFolder}/{name}";
    }

    public static int ClampSignedGetExpirySeconds(int expiresSeconds) =>
        Math.Max(60, Math.Min(7 * 24 * 60 * 60, expiresSeconds));

    public static string AwsPercentEncode(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        var builder = new StringBuilder(bytes.Length);
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
                builder.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
            }
        }

        return builder.ToString();
    }

    public static string CanonicalQueryString(IEnumerable<KeyValuePair<string, string?>> queryItems) =>
        string.Join("&", queryItems
            .Select(item => (Name: AwsPercentEncode(item.Key), Value: AwsPercentEncode(item.Value ?? string.Empty)))
            .OrderBy(item => item.Name, StringComparer.Ordinal)
            .ThenBy(item => item.Value, StringComparer.Ordinal)
            .Select(item => $"{item.Name}={item.Value}"));

    public static Uri ObjectUrl(string key, S3EndpointInfo endpoint, S3DestinationConfig cfg, IEnumerable<KeyValuePair<string, string?>>? queryItems = null)
    {
        var bucket = cfg.Bucket.Trim();
        var escapedKey = EscapePathSegments(key);
        var prefix = endpoint.BasePath.Trim('/');
        var builder = new UriBuilder
        {
            Scheme = endpoint.Scheme,
            Port = endpoint.Port ?? -1
        };

        if (cfg.UsePathStyle)
        {
            builder.Host = endpoint.Host;
            builder.Path = string.IsNullOrEmpty(prefix)
                ? $"/{bucket}/{escapedKey}"
                : $"/{prefix}/{bucket}/{escapedKey}";
        }
        else
        {
            builder.Host = $"{bucket}.{endpoint.Host}";
            builder.Path = string.IsNullOrEmpty(prefix) ? $"/{escapedKey}" : $"/{prefix}/{escapedKey}";
        }

        var query = queryItems is null ? string.Empty : CanonicalQueryString(queryItems);
        builder.Query = query;
        return builder.Uri;
    }

    public static S3SignedRequest SignRequest(
        string method,
        string key,
        IEnumerable<KeyValuePair<string, string?>> queryItems,
        string payloadHash,
        string? contentType,
        S3EndpointInfo endpoint,
        S3DestinationConfig cfg,
        S3Credentials credentials,
        DateTimeOffset timestamp)
    {
        var amzDate = timestamp.UtcDateTime.ToString("yyyyMMdd'T'HHmmss'Z'", CultureInfo.InvariantCulture);
        var dateStamp = amzDate[..8];
        var region = cfg.Region.Trim();
        var service = "s3";
        var objectUrl = ObjectUrl(key, endpoint, cfg, queryItems);
        var canonicalUri = string.IsNullOrEmpty(objectUrl.AbsolutePath) ? "/" : objectUrl.AbsolutePath;

        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["host"] = HostHeader(endpoint, cfg),
            ["x-amz-content-sha256"] = payloadHash,
            ["x-amz-date"] = amzDate
        };
        if (!string.IsNullOrWhiteSpace(credentials.SessionToken))
        {
            headers["x-amz-security-token"] = credentials.SessionToken!;
        }
        if (!string.IsNullOrWhiteSpace(contentType))
        {
            headers["content-type"] = contentType!;
        }

        var sortedHeaders = headers
            .Select(pair => (Key: pair.Key.ToLowerInvariant(), Value: pair.Value.Trim()))
            .OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .ToList();
        var canonicalHeaders = string.Concat(sortedHeaders.Select(pair => $"{pair.Key}:{pair.Value}\n"));
        var signedHeaders = string.Join(';', sortedHeaders.Select(pair => pair.Key));
        var canonicalQuery = CanonicalQueryString(queryItems);
        var canonicalRequest = string.Join("\n", [
            method,
            canonicalUri,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ]);

        var credentialScope = $"{dateStamp}/{region}/{service}/aws4_request";
        var stringToSign = string.Join("\n", [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            Sha256Hex(canonicalRequest)
        ]);
        var signature = HmacHex(SigningKey(credentials.SecretAccessKey, dateStamp, region, service), stringToSign);
        var authorization = $"AWS4-HMAC-SHA256 Credential={credentials.AccessKeyId}/{credentialScope}, SignedHeaders={signedHeaders}, Signature={signature}";

        return new S3SignedRequest(objectUrl, authorization, amzDate, payloadHash, canonicalRequest, signedHeaders, headers);
    }

    public static S3SignedUrl SignedGetUrl(
        string key,
        int expiresSeconds,
        S3EndpointInfo endpoint,
        S3DestinationConfig cfg,
        S3Credentials credentials,
        DateTimeOffset timestamp)
    {
        var amzDate = timestamp.UtcDateTime.ToString("yyyyMMdd'T'HHmmss'Z'", CultureInfo.InvariantCulture);
        var dateStamp = amzDate[..8];
        var region = cfg.Region.Trim();
        var service = "s3";
        var expires = ClampSignedGetExpirySeconds(expiresSeconds);
        var credentialScope = $"{dateStamp}/{region}/{service}/aws4_request";
        var query = new List<KeyValuePair<string, string?>>
        {
            new("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            new("X-Amz-Credential", $"{credentials.AccessKeyId}/{credentialScope}"),
            new("X-Amz-Date", amzDate),
            new("X-Amz-Expires", expires.ToString(CultureInfo.InvariantCulture)),
            new("X-Amz-SignedHeaders", "host")
        };
        if (!string.IsNullOrWhiteSpace(credentials.SessionToken))
        {
            query.Add(new("X-Amz-Security-Token", credentials.SessionToken));
        }

        var objectUrl = ObjectUrl(key, endpoint, cfg, query);
        var canonicalUri = string.IsNullOrEmpty(objectUrl.AbsolutePath) ? "/" : objectUrl.AbsolutePath;
        var canonicalQuery = CanonicalQueryString(query);
        var canonicalHeaders = $"host:{HostHeader(endpoint, cfg)}\n";
        var canonicalRequest = string.Join("\n", [
            "GET",
            canonicalUri,
            canonicalQuery,
            canonicalHeaders,
            "host",
            "UNSIGNED-PAYLOAD"
        ]);
        var stringToSign = string.Join("\n", [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            Sha256Hex(canonicalRequest)
        ]);
        var signature = HmacHex(SigningKey(credentials.SecretAccessKey, dateStamp, region, service), stringToSign);
        query.Add(new("X-Amz-Signature", signature));

        var signed = ObjectUrl(key, endpoint, cfg, query);
        return new S3SignedUrl(signed, timestamp.AddSeconds(expires), expires);
    }

    public static string HostHeader(S3EndpointInfo endpoint, S3DestinationConfig cfg)
    {
        var host = cfg.UsePathStyle ? endpoint.Host : $"{cfg.Bucket.Trim()}.{endpoint.Host}";
        return endpoint.Port is int port ? $"{host}:{port}" : host;
    }

    public static string Sha256Hex(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

    public static string Sha256Hex(byte[] value) =>
        Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();

    private static string EscapePathSegments(string path) =>
        string.Join('/', path.Split('/', StringSplitOptions.RemoveEmptyEntries).Select(AwsPercentEncode));

    private static byte[] SigningKey(string secretKey, string date, string region, string service)
    {
        var kDate = Hmac(Encoding.UTF8.GetBytes("AWS4" + secretKey), date);
        var kRegion = Hmac(kDate, region);
        var kService = Hmac(kRegion, service);
        return Hmac(kService, "aws4_request");
    }

    private static byte[] Hmac(byte[] key, string data) =>
        HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(data));

    private static string HmacHex(byte[] key, string data) =>
        Convert.ToHexString(HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(data))).ToLowerInvariant();
}
