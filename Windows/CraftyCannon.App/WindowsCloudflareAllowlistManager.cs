using System.IO;
using System.Net.NetworkInformation;
using CraftyCannon.Core;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public sealed class WindowsCloudflareAllowlistManager : IDisposable
{
    private readonly RuntimePreferencesStore preferencesStore;
    private readonly ISecretStore secretStore;
    private readonly CloudflareAllowlistClient client;
    private readonly string deviceIdPath;
    private readonly Action<string> statusSink;
    private readonly object gate = new();
    private System.Threading.Timer? timer;
    private System.Threading.Timer? networkDebounceTimer;
    private string? lastNetworkSignature;
    private bool updateInFlight;
    private bool networkSubscribed;

    public WindowsCloudflareAllowlistManager(
        AppStoragePaths paths,
        RuntimePreferencesStore preferencesStore,
        ISecretStore secretStore,
        CloudflareAllowlistClient client,
        Action<string> statusSink)
    {
        this.preferencesStore = preferencesStore;
        this.secretStore = secretStore;
        this.client = client;
        this.statusSink = statusSink;
        deviceIdPath = Path.Combine(paths.RoamingRoot, "cloudflare-device-id.txt");
    }

    public string StatusLine { get; private set; } = "Cloudflare allowlist has not run yet.";

    public string? ApiToken
    {
        get => secretStore.GetSecret(ProfileSecretAccounts.CloudflareService, ProfileSecretAccounts.CloudflareApiToken(DeviceId()))?.Trim();
        set
        {
            var trimmed = value?.Trim() ?? string.Empty;
            if (trimmed.Length == 0)
            {
                secretStore.DeleteSecret(ProfileSecretAccounts.CloudflareService, ProfileSecretAccounts.CloudflareApiToken(DeviceId()));
                SetStatus("Cloudflare API token cleared.");
            }
            else
            {
                secretStore.SetSecret(ProfileSecretAccounts.CloudflareService, ProfileSecretAccounts.CloudflareApiToken(DeviceId()), trimmed);
                SetStatus("Cloudflare API token saved in Credential Manager.");
            }
        }
    }

    public bool HasApiToken => !string.IsNullOrWhiteSpace(ApiToken);

    public void ApplyCurrentPreferences()
    {
        lock (gate)
        {
            timer?.Dispose();
            timer = null;
            networkDebounceTimer?.Dispose();
            networkDebounceTimer = null;
            lastNetworkSignature = null;

            var config = preferencesStore.Current.CloudflareAllowlist?.Normalized ?? new CloudflareAllowlistConfig();
            if (!config.Enabled)
            {
                UnsubscribeNetworkChanges();
                SetStatus("Cloudflare allowlist is disabled.");
                return;
            }

            if (!ConfigurationIsRunnable(config))
            {
                UnsubscribeNetworkChanges();
                SetStatus("Cloudflare allowlist needs an account ID, list name or ID, and API token.");
                return;
            }

            var interval = TimeSpan.FromMinutes(config.CheckIntervalMinutes);
            timer = new System.Threading.Timer(_ => _ = UpdateNowAsync(), null, TimeSpan.FromSeconds(2), interval);
            SubscribeNetworkChanges();
            SetStatus($"Cloudflare allowlist will refresh every {config.CheckIntervalMinutes} minutes and after network changes.");
        }
    }

    public async Task<Result<CloudflareAllowlistUpdateResult>> UpdateNowAsync(CancellationToken cancellationToken = default)
    {
        lock (gate)
        {
            if (updateInFlight)
            {
                return Result<CloudflareAllowlistUpdateResult>.Failure("Cloudflare allowlist update is already running.");
            }

            updateInFlight = true;
        }

        try
        {
            var config = preferencesStore.Current.CloudflareAllowlist?.Normalized ?? new CloudflareAllowlistConfig();
            var token = ApiToken;
            if (string.IsNullOrWhiteSpace(token))
            {
                throw new CloudflareAllowlistException("Missing Cloudflare API token.");
            }

            var result = await client.UpdateAsync(config, token, DeviceMarker(), cancellationToken: cancellationToken).ConfigureAwait(false);
            SetStatus(result.Message);
            return Result<CloudflareAllowlistUpdateResult>.Success(result);
        }
        catch (Exception ex)
        {
            var message = "Cloudflare allowlist update failed: " + ex.Message;
            SetStatus(message);
            return Result<CloudflareAllowlistUpdateResult>.Failure(message);
        }
        finally
        {
            lock (gate)
            {
                updateInFlight = false;
            }
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            timer?.Dispose();
            networkDebounceTimer?.Dispose();
            UnsubscribeNetworkChanges();
        }
    }

    private bool ConfigurationIsRunnable(CloudflareAllowlistConfig config) =>
        !string.IsNullOrWhiteSpace(config.AccountId) &&
        !string.IsNullOrWhiteSpace(config.ListId) &&
        HasApiToken;

    private void SubscribeNetworkChanges()
    {
        if (networkSubscribed)
        {
            return;
        }

        NetworkChange.NetworkAddressChanged += NetworkAddressChanged;
        NetworkChange.NetworkAvailabilityChanged += NetworkAvailabilityChanged;
        networkSubscribed = true;
    }

    private void UnsubscribeNetworkChanges()
    {
        if (!networkSubscribed)
        {
            return;
        }

        NetworkChange.NetworkAddressChanged -= NetworkAddressChanged;
        NetworkChange.NetworkAvailabilityChanged -= NetworkAvailabilityChanged;
        networkSubscribed = false;
    }

    private void NetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs e) => HandleNetworkChange(e.IsAvailable);

    private void NetworkAddressChanged(object? sender, EventArgs e) => HandleNetworkChange(NetworkInterface.GetIsNetworkAvailable());

    private void HandleNetworkChange(bool isSatisfied)
    {
        var signature = CurrentNetworkSignature();
        var shouldRefresh = CloudflareAllowlistClient.ShouldRefreshAfterPathChange(lastNetworkSignature, signature, isSatisfied);
        lastNetworkSignature = signature;
        if (!shouldRefresh)
        {
            return;
        }

        networkDebounceTimer?.Dispose();
        networkDebounceTimer = new System.Threading.Timer(_ => _ = UpdateNowAsync(), null, TimeSpan.FromSeconds(3), Timeout.InfiniteTimeSpan);
    }

    private static string CurrentNetworkSignature()
    {
        var interfaces = NetworkInterface.GetAllNetworkInterfaces()
            .Where(candidate => candidate.OperationalStatus == OperationalStatus.Up)
            .Select(candidate => candidate.Name)
            .ToArray();
        return CloudflareAllowlistClient.NetworkPathSignature(NetworkInterface.GetIsNetworkAvailable() ? "satisfied" : "unsatisfied", interfaces);
    }

    private string DeviceMarker() => "craftycannon-device:" + DeviceId();

    private string DeviceId()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(deviceIdPath)!);
        if (File.Exists(deviceIdPath))
        {
            var existing = File.ReadAllText(deviceIdPath).Trim();
            if (existing.Length > 0)
            {
                return existing;
            }
        }

        var value = Guid.NewGuid().ToString();
        File.WriteAllText(deviceIdPath, value);
        return value;
    }

    private void SetStatus(string value)
    {
        StatusLine = value;
        statusSink(value);
    }
}

public sealed record Result<T>(bool IsSuccess, T? Value, string? Error)
{
    public static Result<T> Success(T value) => new(true, value, null);

    public static Result<T> Failure(string error) => new(false, default, error);
}


