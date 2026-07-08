namespace CraftyCannon.Upload;

public sealed record BinaryContent(byte[] Bytes, string? ContentType = null);

public sealed record TransportRequest(
    HttpMethod Method,
    Uri Url,
    IReadOnlyDictionary<string, string> Headers,
    BinaryContent? Content = null,
    TimeSpan? Timeout = null);

public sealed record TransportResponse(int StatusCode, byte[] Body, IReadOnlyDictionary<string, string> Headers)
{
    public string BodyText => System.Text.Encoding.UTF8.GetString(Body);
}

public interface IHttpTransport
{
    Task<TransportResponse> SendAsync(TransportRequest request, CancellationToken cancellationToken = default);
}

public sealed class HttpClientTransport : IHttpTransport
{
    private readonly HttpClient client;

    public HttpClientTransport(HttpClient? client = null)
    {
        this.client = client ?? new HttpClient();
    }

    public async Task<TransportResponse> SendAsync(TransportRequest request, CancellationToken cancellationToken = default)
    {
        using var message = new HttpRequestMessage(request.Method, request.Url);
        foreach (var header in request.Headers)
        {
            message.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        if (request.Content is { } content)
        {
            message.Content = new ByteArrayContent(content.Bytes);
            if (!string.IsNullOrWhiteSpace(content.ContentType))
            {
                message.Content.Headers.TryAddWithoutValidation("Content-Type", content.ContentType);
            }
        }

        using var cts = request.Timeout.HasValue
            ? CancellationTokenSource.CreateLinkedTokenSource(cancellationToken)
            : null;
        if (cts is not null)
        {
            cts.CancelAfter(request.Timeout.GetValueOrDefault());
            cancellationToken = cts.Token;
        }

        using var response = await client.SendAsync(message, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        var headers = response.Headers.Concat(response.Content.Headers)
            .ToDictionary(pair => pair.Key, pair => string.Join(",", pair.Value), StringComparer.OrdinalIgnoreCase);
        return new TransportResponse((int)response.StatusCode, body, headers);
    }
}

