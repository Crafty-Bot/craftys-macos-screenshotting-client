using System.Net;
using System.Text;
using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public sealed record UploadFileRequest(
    string FilePath,
    UploadProfile Profile,
    ProfileSecrets Secrets,
    string? RemoteFilename = null,
    string? UploadContext = null,
    DateTimeOffset? DeletesAt = null,
    int? ExpiresSeconds = null,
    string? RandomToken = null,
    DateTimeOffset? Now = null);

public sealed record UploadFileResult(string Url, string? Key = null, DateTimeOffset? ExpiresAt = null);

public sealed class ZiplineClient
{
    private readonly IHttpTransport transport;

    public ZiplineClient(IHttpTransport transport)
    {
        this.transport = transport;
    }

    public async Task<UploadFileResult> UploadAsync(UploadFileRequest request, CancellationToken cancellationToken = default)
    {
        if (request.Profile.Backend != UploadBackend.ZiplineV4)
        {
            throw new UploadException("Profile backend is not Zipline.");
        }

        var token = request.Secrets.ZiplineApiKey?.Trim();
        if (string.IsNullOrEmpty(token))
        {
            throw new UploadException("Missing Zipline API token.");
        }

        var endpoint = ZiplineUploadUtilities.EndpointUrl(request.Profile.Endpoint);
        var filename = ZiplineUploadUtilities.MultipartSafeFilename(string.IsNullOrWhiteSpace(request.RemoteFilename)
            ? Path.GetFileName(request.FilePath)
            : request.RemoteFilename!);
        var boundary = "Boundary-" + Guid.NewGuid().ToString("N");
        var body = await BuildMultipartBodyAsync(request.FilePath, filename, boundary, cancellationToken).ConfigureAwait(false);
        var headersInfo = ZiplineUploadUtilities.FilenameHeaders(filename);
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Authorization"] = token,
            ["x-zipline-filename"] = headersInfo.FileNameWithoutExtension
        };
        if (headersInfo.FileExtension is not null)
        {
            headers["x-zipline-file-extension"] = headersInfo.FileExtension;
        }
        if (request.DeletesAt is { } deletesAt)
        {
            headers["x-zipline-deletes-at"] = "date=" + Iso8601Utc(deletesAt);
        }

        var response = await transport.SendAsync(new TransportRequest(
            HttpMethod.Post,
            endpoint,
            headers,
            new BinaryContent(body, "multipart/form-data; boundary=" + boundary)), cancellationToken).ConfigureAwait(false);

        if (response.StatusCode < 200 || response.StatusCode > 299)
        {
            throw new UploadException(string.IsNullOrWhiteSpace(response.BodyText) ? $"HTTP {response.StatusCode}" : response.BodyText);
        }

        var parsed = ZiplineUploadUtilities.ParseUploadResponse(response.BodyText);
        return new UploadFileResult(parsed.Url, ExpiresAt: parsed.DeletesAt ?? request.DeletesAt);
    }

    public async Task<EndpointValidationResult> ValidateAsync(UploadProfile profile, CancellationToken cancellationToken = default)
    {
        Uri endpoint;
        try
        {
            endpoint = ZiplineUploadUtilities.EndpointUrl(profile.Endpoint);
        }
        catch
        {
            return new EndpointValidationResult(false, "Endpoint is not a valid URL.");
        }

        try
        {
            var response = await transport.SendAsync(new TransportRequest(
                HttpMethod.Head,
                endpoint,
                new Dictionary<string, string>(),
                Timeout: TimeSpan.FromSeconds(8)), cancellationToken).ConfigureAwait(false);
            return ZiplineUploadUtilities.EndpointValidationResult(profile.Backend, response.StatusCode, response.BodyText);
        }
        catch (Exception ex)
        {
            return new EndpointValidationResult(false, $"Could not reach endpoint ({ex.Message}).");
        }
    }

    private static async Task<byte[]> BuildMultipartBodyAsync(string filePath, string filename, string boundary, CancellationToken cancellationToken)
    {
        var preamble = $"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\nContent-Type: application/octet-stream\r\n\r\n";
        var epilogue = $"\r\n--{boundary}--\r\n";
        await using var output = new MemoryStream();
        await output.WriteAsync(Encoding.UTF8.GetBytes(preamble), cancellationToken).ConfigureAwait(false);
        await using (var input = File.OpenRead(filePath))
        {
            await input.CopyToAsync(output, cancellationToken).ConfigureAwait(false);
        }
        await output.WriteAsync(Encoding.UTF8.GetBytes(epilogue), cancellationToken).ConfigureAwait(false);
        return output.ToArray();
    }

    private static string Iso8601Utc(DateTimeOffset value) =>
        value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture);
}

public sealed class S3Client
{
    private readonly IHttpTransport transport;

    public S3Client(IHttpTransport transport)
    {
        this.transport = transport;
    }

    public async Task<UploadFileResult> UploadAsync(UploadFileRequest request, CancellationToken cancellationToken = default)
    {
        var cfg = RequiredConfig(request.Profile);
        var credentials = RequiredCredentials(request.Secrets);
        var endpoint = S3UploadUtilities.ParseEndpoint(cfg.Endpoint);
        var now = request.Now ?? DateTimeOffset.UtcNow;
        var filename = string.IsNullOrWhiteSpace(request.RemoteFilename) ? Path.GetFileName(request.FilePath) : request.RemoteFilename!;
        var key = S3UploadUtilities.MakeObjectKey(now, filename, cfg.KeyPrefix, request.UploadContext, request.RandomToken ?? Guid.NewGuid().ToString("N"));
        var bytes = await File.ReadAllBytesAsync(request.FilePath, cancellationToken).ConfigureAwait(false);
        var payloadHash = S3UploadUtilities.Sha256Hex(bytes);
        var contentType = MimeType(Path.GetExtension(filename).TrimStart('.'));
        var signed = S3UploadUtilities.SignRequest("PUT", key, [], payloadHash, contentType, endpoint, cfg, credentials, now);
        var headers = signed.Headers.ToDictionary(StringComparer.OrdinalIgnoreCase);
        headers["Authorization"] = signed.Authorization;
        var response = await transport.SendAsync(new TransportRequest(
            HttpMethod.Put,
            signed.Url,
            headers,
            new BinaryContent(bytes, contentType)), cancellationToken).ConfigureAwait(false);

        if (response.StatusCode < 200 || response.StatusCode > 299)
        {
            throw new UploadException($"S3 PUT failed (HTTP {response.StatusCode})");
        }

        if (request.ExpiresSeconds is int expiresSeconds && expiresSeconds > 0)
        {
            var signedGet = S3UploadUtilities.SignedGetUrl(key, expiresSeconds, endpoint, cfg, credentials, now);
            return new UploadFileResult(signedGet.Url.AbsoluteUri, key, signedGet.ExpiresAt);
        }

        if (!string.IsNullOrWhiteSpace(cfg.PublicBaseUrl))
        {
            return new UploadFileResult(PublicUrl(key, cfg.PublicBaseUrl!), key);
        }

        if (cfg.UseSignedGetUrls)
        {
            var signedGet = S3UploadUtilities.SignedGetUrl(key, (int)cfg.SignedGetUrlExpiry.TotalSeconds, endpoint, cfg, credentials, now);
            return new UploadFileResult(signedGet.Url.AbsoluteUri, key, signedGet.ExpiresAt);
        }

        return new UploadFileResult(S3UploadUtilities.ObjectUrl(key, endpoint, cfg).AbsoluteUri, key);
    }

    public async Task<EndpointValidationResult> ProbeAsync(UploadProfile profile, ProfileSecrets secrets, DateTimeOffset? now = null, CancellationToken cancellationToken = default)
    {
        try
        {
            var cfg = RequiredConfig(profile);
            var credentials = RequiredCredentials(secrets);
            var endpoint = S3UploadUtilities.ParseEndpoint(cfg.Endpoint);
            var timestamp = now ?? DateTimeOffset.UtcNow;
            var key = S3UploadUtilities.MakeObjectKey(timestamp, "craftycannon-probe.txt", cfg.KeyPrefix, "probe", Guid.NewGuid().ToString("N"));
            var body = Encoding.UTF8.GetBytes("probe");
            var payloadHash = S3UploadUtilities.Sha256Hex(body);
            var put = S3UploadUtilities.SignRequest("PUT", key, [], payloadHash, "text/plain; charset=utf-8", endpoint, cfg, credentials, timestamp);
            var putHeaders = put.Headers.ToDictionary(StringComparer.OrdinalIgnoreCase);
            putHeaders["Authorization"] = put.Authorization;
            var putResponse = await transport.SendAsync(new TransportRequest(
                HttpMethod.Put,
                put.Url,
                putHeaders,
                new BinaryContent(body, "text/plain; charset=utf-8")), cancellationToken).ConfigureAwait(false);

            if (putResponse.StatusCode < 200 || putResponse.StatusCode > 299)
            {
                return new EndpointValidationResult(false, $"S3 probe upload failed (HTTP {putResponse.StatusCode}). Check credentials, bucket policy, region, and endpoint.");
            }

            var delete = S3UploadUtilities.SignRequest("DELETE", key, [], "UNSIGNED-PAYLOAD", null, endpoint, cfg, credentials, timestamp);
            var deleteHeaders = delete.Headers.ToDictionary(StringComparer.OrdinalIgnoreCase);
            deleteHeaders["Authorization"] = delete.Authorization;
            try
            {
                _ = await transport.SendAsync(new TransportRequest(HttpMethod.Delete, delete.Url, deleteHeaders), cancellationToken).ConfigureAwait(false);
            }
            catch
            {
                // Cleanup is best effort; upload validation has already succeeded.
            }

            return new EndpointValidationResult(true, "S3 endpoint and credentials validated.");
        }
        catch (UploadException ex)
        {
            return new EndpointValidationResult(false, ex.Message);
        }
        catch (Exception ex)
        {
            return new EndpointValidationResult(false, "S3 probe failed (" + ex.Message + ").");
        }
    }

    private static S3DestinationConfig RequiredConfig(UploadProfile profile)
    {
        if (profile.Backend != UploadBackend.S3Compatible)
        {
            throw new UploadException("Profile backend is not S3-compatible.");
        }
        if (profile.S3Config is not { } cfg)
        {
            throw new UploadException("Missing S3 configuration in profile.");
        }
        if (string.IsNullOrWhiteSpace(cfg.Endpoint)) throw new UploadException("S3 endpoint is required.");
        if (string.IsNullOrWhiteSpace(cfg.Region)) throw new UploadException("S3 region is required.");
        if (string.IsNullOrWhiteSpace(cfg.Bucket)) throw new UploadException("S3 bucket is required.");
        return cfg;
    }

    private static S3Credentials RequiredCredentials(ProfileSecrets secrets)
    {
        var accessKey = secrets.S3AccessKey?.Trim();
        var secretKey = secrets.S3SecretKey?.Trim();
        if (string.IsNullOrEmpty(accessKey) || string.IsNullOrEmpty(secretKey))
        {
            throw new UploadException("Missing S3 credentials. Set access key ID and secret access key in profile settings.");
        }
        var token = secrets.S3SessionToken?.Trim();
        return new S3Credentials(accessKey, secretKey, string.IsNullOrEmpty(token) ? null : token);
    }

    private static string PublicUrl(string key, string publicBaseUrl)
    {
        var builder = new UriBuilder(publicBaseUrl.Trim()) { Query = string.Empty, Fragment = string.Empty };
        var basePath = builder.Path.EndsWith('/') ? builder.Path : builder.Path + "/";
        builder.Path = basePath + string.Join('/', key.Split('/').Select(S3UploadUtilities.AwsPercentEncode));
        return builder.Uri.AbsoluteUri;
    }

    private static string MimeType(string ext) => ext.ToLowerInvariant() switch
    {
        "png" => "image/png",
        "jpg" or "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "bmp" => "image/bmp",
        "tif" or "tiff" => "image/tiff",
        "heic" => "image/heic",
        "heif" => "image/heif",
        "txt" => "text/plain; charset=utf-8",
        "json" => "application/json",
        "pdf" => "application/pdf",
        "zip" => "application/zip",
        _ => "application/octet-stream"
    };
}

public sealed class URLShortenerClient
{
    private readonly IHttpTransport transport;

    public URLShortenerClient(IHttpTransport transport)
    {
        this.transport = transport;
    }

    public async Task<string> ShortenAsync(string url, ShortenerRequest config, CancellationToken cancellationToken = default)
    {
        var request = URLShortenerUtilities.BuildRequest(url, config);
        var response = await transport.SendAsync(new TransportRequest(request.EffectiveMethod, request.Url, new Dictionary<string, string>(), Timeout: request.Timeout), cancellationToken).ConfigureAwait(false);
        return config.Provider == ShortenerProvider.TinyUrl
            ? URLShortenerUtilities.ParseTinyUrlResponse(response.StatusCode, response.BodyText)
            : URLShortenerUtilities.ParseCustomResponse(response.StatusCode, response.BodyText);
    }
}

