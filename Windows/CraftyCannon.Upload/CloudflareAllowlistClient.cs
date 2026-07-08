using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public sealed record CloudflareAllowlistUpdateResult(string IpAddress, string? OperationId, string Message);

public sealed record CloudflareListItem(string? Id, string? Ip, string? Comment);

public sealed record CloudflareManagedListItem(string Ip, string Comment);

public sealed class CloudflareAllowlistException(string message) : Exception(message);

public sealed class CloudflareAllowlistClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly IHttpTransport transport;
    private readonly Uri apiBaseUri;
    private readonly Uri publicIpUri;

    public CloudflareAllowlistClient(
        IHttpTransport transport,
        Uri? apiBaseUri = null,
        Uri? publicIpUri = null)
    {
        this.transport = transport;
        this.apiBaseUri = apiBaseUri ?? new Uri("https://api.cloudflare.com/client/v4/");
        this.publicIpUri = publicIpUri ?? new Uri("https://cloudflare.com/cdn-cgi/trace");
    }

    public async Task<CloudflareAllowlistUpdateResult> UpdateAsync(
        CloudflareAllowlistConfig config,
        string apiToken,
        string deviceMarker,
        DateTimeOffset? updatedAt = null,
        CancellationToken cancellationToken = default)
    {
        config = config.Normalized;
        if (string.IsNullOrWhiteSpace(config.AccountId))
        {
            throw new CloudflareAllowlistException("Missing Cloudflare account ID.");
        }

        if (string.IsNullOrWhiteSpace(config.ListId))
        {
            throw new CloudflareAllowlistException("Missing Cloudflare list name or ID.");
        }

        if (string.IsNullOrWhiteSpace(apiToken))
        {
            throw new CloudflareAllowlistException("Missing Cloudflare API token.");
        }

        var listId = await ResolveListIdAsync(config.AccountId, config.ListId, apiToken.Trim(), cancellationToken).ConfigureAwait(false);
        var ip = await FetchPublicIpAsync(cancellationToken).ConfigureAwait(false);
        var currentItems = await FetchListItemsAsync(config.AccountId, listId, apiToken.Trim(), cancellationToken).ConfigureAwait(false);
        var managedItems = ManagedItems(currentItems, ip, deviceMarker, config.DeviceName, updatedAt ?? DateTimeOffset.UtcNow);
        var operationId = await ReplaceListItemsAsync(config.AccountId, listId, apiToken.Trim(), managedItems, cancellationToken).ConfigureAwait(false);
        await WaitForBulkOperationIfNeededAsync(config.AccountId, apiToken.Trim(), operationId, cancellationToken).ConfigureAwait(false);
        return new CloudflareAllowlistUpdateResult(ip, operationId, $"Cloudflare allowlist updated for {ip}.");
    }

    public static string? PublicIpFromCloudflareTrace(string text)
    {
        foreach (var line in text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            if (!line.StartsWith("ip=", StringComparison.Ordinal))
            {
                continue;
            }

            var value = line[3..].Trim();
            return value.Length == 0 ? null : value;
        }

        return null;
    }

    public static bool IsValidIpAddress(string value) => IPAddress.TryParse(value, out _);

    public static bool LooksLikeCloudflareId(string value) =>
        value.Length == 32 && value.All(c => char.IsDigit(c) || c is >= 'a' and <= 'f' || c is >= 'A' and <= 'F');

    public static IReadOnlyList<CloudflareManagedListItem> ManagedItems(
        IEnumerable<CloudflareListItem> currentItems,
        string currentIp,
        string deviceMarker,
        string deviceName,
        DateTimeOffset updatedAt)
    {
        var preserved = new List<CloudflareManagedListItem>();
        foreach (var item in currentItems)
        {
            if (string.IsNullOrWhiteSpace(item.Ip) || !IsValidIpAddress(item.Ip))
            {
                continue;
            }

            if (item.Comment?.StartsWith(deviceMarker, StringComparison.Ordinal) == true)
            {
                continue;
            }

            preserved.Add(new CloudflareManagedListItem(item.Ip, item.Comment ?? string.Empty));
        }

        if (preserved.Any(item => string.Equals(item.Ip, currentIp, StringComparison.OrdinalIgnoreCase)))
        {
            return preserved;
        }

        var comment = $"{deviceMarker} {deviceName} updated {updatedAt.UtcDateTime:O}";
        preserved.Add(new CloudflareManagedListItem(currentIp, comment));
        return preserved;
    }

    public static string NetworkPathSignature(string status, IEnumerable<string> interfaces) =>
        status + "|" + string.Join(',', interfaces.Order(StringComparer.Ordinal));

    public static bool ShouldRefreshAfterPathChange(string? previousSignature, string newSignature, bool isSatisfied) =>
        isSatisfied && previousSignature is not null && !string.Equals(previousSignature, newSignature, StringComparison.Ordinal);

    private async Task<string> FetchPublicIpAsync(CancellationToken cancellationToken)
    {
        var response = await transport.SendAsync(new TransportRequest(HttpMethod.Get, publicIpUri, new Dictionary<string, string>(), Timeout: TimeSpan.FromSeconds(10)), cancellationToken).ConfigureAwait(false);
        if (response.StatusCode is < 200 or > 299)
        {
            throw new CloudflareAllowlistException("Cloudflare returned an unexpected response.");
        }

        var ip = PublicIpFromCloudflareTrace(response.BodyText);
        if (string.IsNullOrWhiteSpace(ip))
        {
            throw new CloudflareAllowlistException("Cloudflare returned an unexpected response.");
        }

        if (!IsValidIpAddress(ip))
        {
            throw new CloudflareAllowlistException($"Public IP lookup returned an invalid address: {ip}");
        }

        return ip;
    }

    private async Task<string> ResolveListIdAsync(string accountId, string listNameOrId, string apiToken, CancellationToken cancellationToken)
    {
        var trimmed = listNameOrId.Trim();
        if (LooksLikeCloudflareId(trimmed))
        {
            return trimmed;
        }

        var envelope = await CloudflareRequestAsync<IReadOnlyList<CloudflareList>>(HttpMethod.Get, $"accounts/{accountId}/rules/lists", apiToken, cancellationToken: cancellationToken).ConfigureAwait(false);
        var lists = envelope.Result ?? [];
        var exact = lists.FirstOrDefault(list => string.Equals(list.Kind, "ip", StringComparison.OrdinalIgnoreCase) && string.Equals(list.Name, trimmed, StringComparison.Ordinal));
        if (exact is not null)
        {
            return exact.Id;
        }

        var insensitive = lists.FirstOrDefault(list => string.Equals(list.Kind, "ip", StringComparison.OrdinalIgnoreCase) && string.Equals(list.Name, trimmed, StringComparison.OrdinalIgnoreCase));
        if (insensitive is not null)
        {
            return insensitive.Id;
        }

        throw new CloudflareAllowlistException($"Could not find a Cloudflare IP list named or identified by '{trimmed}'.");
    }

    private async Task<IReadOnlyList<CloudflareListItem>> FetchListItemsAsync(string accountId, string listId, string apiToken, CancellationToken cancellationToken)
    {
        var allItems = new List<CloudflareListItem>();
        string? cursor = null;
        do
        {
            var path = $"accounts/{accountId}/rules/lists/{listId}/items?per_page=500" + (string.IsNullOrWhiteSpace(cursor) ? string.Empty : "&cursor=" + Uri.EscapeDataString(cursor));
            var envelope = await CloudflareRequestAsync<IReadOnlyList<CloudflareListItem>>(HttpMethod.Get, path, apiToken, cancellationToken: cancellationToken).ConfigureAwait(false);
            allItems.AddRange(envelope.Result ?? []);
            cursor = envelope.ResultInfo?.Cursors?.After;
        } while (!string.IsNullOrWhiteSpace(cursor));

        return allItems;
    }

    private async Task<string?> ReplaceListItemsAsync(string accountId, string listId, string apiToken, IReadOnlyList<CloudflareManagedListItem> items, CancellationToken cancellationToken)
    {
        var envelope = await CloudflareRequestAsync<CloudflareOperationResponse>(HttpMethod.Put, $"accounts/{accountId}/rules/lists/{listId}/items", apiToken, items, cancellationToken).ConfigureAwait(false);
        return envelope.Result?.OperationId;
    }

    private async Task WaitForBulkOperationIfNeededAsync(string accountId, string apiToken, string? operationId, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(operationId))
        {
            return;
        }

        for (var i = 0; i < 12; i++)
        {
            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken).ConfigureAwait(false);
            var envelope = await CloudflareRequestAsync<CloudflareBulkOperationStatus>(HttpMethod.Get, $"accounts/{accountId}/rules/lists/bulk_operations/{operationId}", apiToken, cancellationToken: cancellationToken).ConfigureAwait(false);
            switch (envelope.Result?.Status)
            {
                case "completed":
                    return;
                case "failed":
                    throw new CloudflareAllowlistException(envelope.Result?.Error ?? "Cloudflare list update failed.");
            }
        }

        throw new CloudflareAllowlistException("Timed out waiting for the Cloudflare list update to complete.");
    }

    private async Task<CloudflareEnvelope<TResult>> CloudflareRequestAsync<TResult>(HttpMethod method, string path, string apiToken, object? body = null, CancellationToken cancellationToken = default)
    {
        var url = new Uri(apiBaseUri, path);
        var headers = new Dictionary<string, string>
        {
            ["Authorization"] = "Bearer " + apiToken,
            ["Accept"] = "application/json"
        };
        BinaryContent? content = null;
        if (body is not null)
        {
            content = new BinaryContent(JsonSerializer.SerializeToUtf8Bytes(body, JsonOptions), "application/json");
        }

        var response = await transport.SendAsync(new TransportRequest(method, url, headers, content, Timeout: TimeSpan.FromSeconds(20)), cancellationToken).ConfigureAwait(false);
        CloudflareEnvelope<TResult>? envelope;
        try
        {
            envelope = JsonSerializer.Deserialize<CloudflareEnvelope<TResult>>(response.Body, JsonOptions);
        }
        catch (JsonException ex)
        {
            throw new CloudflareAllowlistException("Cloudflare returned an unexpected response: " + ex.Message);
        }

        if (envelope is null)
        {
            throw new CloudflareAllowlistException("Cloudflare returned an unexpected response.");
        }

        if (response.StatusCode is < 200 or > 299 || !envelope.Success)
        {
            throw new CloudflareAllowlistException(ErrorMessage(envelope.Errors, response.StatusCode));
        }

        return envelope;
    }

    private static string ErrorMessage(IReadOnlyList<CloudflareError>? errors, int statusCode)
    {
        var messages = errors?
            .Select(error => error.Code is int code ? $"{code}: {error.Message}" : error.Message)
            .Where(message => !string.IsNullOrWhiteSpace(message))
            .ToArray() ?? [];
        return messages.Length == 0 ? $"Cloudflare API request failed (HTTP {statusCode})." : string.Join(' ', messages);
    }

    private sealed record CloudflareEnvelope<TResult>(
        bool Success,
        TResult? Result,
        IReadOnlyList<CloudflareError>? Errors,
        [property: JsonPropertyName("result_info")] CloudflareResultInfo? ResultInfo);

    private sealed record CloudflareError(int? Code, string Message);

    private sealed record CloudflareResultInfo(CloudflareCursors? Cursors);

    private sealed record CloudflareCursors(string? After);

    private sealed record CloudflareList(string Id, string Name, string Kind);

    private sealed record CloudflareOperationResponse([property: JsonPropertyName("operation_id")] string? OperationId);

    private sealed record CloudflareBulkOperationStatus(string? Id, string Status, string? Error);
}
