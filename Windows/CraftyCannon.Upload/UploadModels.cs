using System.Net;

using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public sealed record EndpointValidationResult(bool IsValid, string Message);

public sealed record ZiplineUploadResponse(string Url, DateTimeOffset? DeletesAt);

public sealed record ZiplineFilenameHeaders(string FileNameWithoutExtension, string? FileExtension);

public sealed record S3Credentials(string AccessKeyId, string SecretAccessKey, string? SessionToken = null);

public sealed record S3EndpointInfo(string Scheme, string Host, int? Port, string BasePath);

public sealed record S3SignedRequest(
    Uri Url,
    string Authorization,
    string AmzDate,
    string PayloadHash,
    string CanonicalRequest,
    string SignedHeaders,
    IReadOnlyDictionary<string, string> Headers);

public sealed record S3SignedUrl(Uri Url, DateTimeOffset ExpiresAt, int ExpiresSeconds);

public enum ShortenerProvider
{
    TinyUrl,
    CustomGetTemplate
}

public sealed record ShortenerRequest(ShortenerProvider Provider, string? CustomGetTemplate = null);

public sealed record UploadRouteProfile(UploadProfile Profile, ProfileSecrets Secrets);

public sealed record ShortenerHttpRequest(Uri Url, HttpMethod? Method = null, TimeSpan? Timeout = null)
{
    public HttpMethod EffectiveMethod => Method ?? HttpMethod.Get;
}

public sealed class UploadException : Exception
{
    public UploadException(string message) : base(message)
    {
    }
}

