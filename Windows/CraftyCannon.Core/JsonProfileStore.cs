using System.Text.Json;

namespace CraftyCannon.Core;

public sealed class JsonProfileStore : IProfileStore
{
    private readonly string path;
    private readonly string profileBackupPath;
    private readonly ISecretStore secretStore;
    private readonly List<UploadProfile> profiles = [];
    private string? activeProfileId;

    public JsonProfileStore(AppStoragePaths paths, ISecretStore secretStore)
    {
        path = paths.ProfilesPath;
        profileBackupPath = paths.ProfileBackupPath;
        this.secretStore = secretStore;
    }

    public IReadOnlyList<UploadProfile> Profiles => profiles;

    public UploadProfile ActiveProfile =>
        profiles.FirstOrDefault(profile => profile.Id == activeProfileId) ??
        profiles.FirstOrDefault() ??
        UploadProfile.Unconfigured;

    UploadProfile? IProfileStore.ActiveProfile => ActiveProfile;

    public string? ActiveProfileId => ActiveProfile.Id == UploadProfile.Unconfigured.Id ? null : ActiveProfile.Id;

    public bool HasConfiguredProfiles() => profiles.Any(profile => profile.Id != UploadProfile.Unconfigured.Id);

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        profiles.Clear();
        activeProfileId = null;

        if (File.Exists(path) && await TryLoadPrimaryFileAsync(cancellationToken).ConfigureAwait(false))
        {
            EnsureActiveProfileSetIfNeeded();
            await PersistProfilesConfigBackupAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        var restored = await LoadProfilesConfigBackupAsync(cancellationToken).ConfigureAwait(false);
        if (restored.Count == 0)
        {
            return;
        }

        profiles.AddRange(restored);
        EnsureActiveProfileSetIfNeeded();
        await SaveAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ReplaceProfilesAsync(
        IEnumerable<UploadProfile> newProfiles,
        string? newActiveProfileId,
        CancellationToken cancellationToken = default)
    {
        ClearAllProfileSecrets();
        profiles.Clear();
        profiles.AddRange(newProfiles);
        activeProfileId = profiles.Any(profile => profile.Id == newActiveProfileId)
            ? newActiveProfileId
            : profiles.FirstOrDefault()?.Id;
        await SaveAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task SetActiveProfileAsync(string profileId, CancellationToken cancellationToken = default)
    {
        if (profiles.All(profile => profile.Id != profileId))
        {
            throw new InvalidOperationException($"Unknown upload profile: {profileId}");
        }

        activeProfileId = profileId;
        await SaveAsync(cancellationToken).ConfigureAwait(false);
    }

    public void SaveSecrets(string profileId, ProfileSecrets secrets)
    {
        WriteSecret(ProfileSecretAccounts.ZiplineApiKey(profileId), secrets.ZiplineApiKey);
        WriteSecret(ProfileSecretAccounts.S3AccessKey(profileId), secrets.S3AccessKey);
        WriteSecret(ProfileSecretAccounts.S3SecretKey(profileId), secrets.S3SecretKey);
        WriteSecret(ProfileSecretAccounts.S3SessionToken(profileId), secrets.S3SessionToken);
    }

    public ProfileSecrets GetSecrets(string profileId) => new(
        secretStore.GetSecret(ProfileSecretAccounts.UploadProfileService, ProfileSecretAccounts.ZiplineApiKey(profileId)),
        secretStore.GetSecret(ProfileSecretAccounts.UploadProfileService, ProfileSecretAccounts.S3AccessKey(profileId)),
        secretStore.GetSecret(ProfileSecretAccounts.UploadProfileService, ProfileSecretAccounts.S3SecretKey(profileId)),
        secretStore.GetSecret(ProfileSecretAccounts.UploadProfileService, ProfileSecretAccounts.S3SessionToken(profileId)));

    public ProfileExportBundle CreateExportBundle() => new(
        Version: 1,
        ActiveProfileId: ActiveProfileId,
        Profiles: profiles.Select(profile => new ExportedUploadProfile(
            profile.Id,
            profile.Name,
            profile.Endpoint,
            profile.Backend,
            profile.S3Config,
            profile.SecondaryS3ProfileId,
            ApiKey: null,
            S3AccessKey: null,
            S3SecretKey: null,
            S3SessionToken: null)).ToList(),
        ExportedAt: DateTimeOffset.UtcNow);

    public async Task<string> ExportJsonAsync(CancellationToken cancellationToken = default)
    {
        await using var stream = new MemoryStream();
        await JsonSerializer.SerializeAsync(stream, CreateExportBundle(), JsonOptions.Default, cancellationToken)
            .ConfigureAwait(false);
        stream.Position = 0;
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task ImportAsync(
        ProfileExportBundle bundle,
        bool importSecrets,
        bool replaceExisting = true,
        CancellationToken cancellationToken = default)
    {
        if (replaceExisting)
        {
            await ReplaceProfilesAsync(bundle.Profiles.Select(profile => profile.ToProfile()), bundle.ActiveProfileId, cancellationToken)
                .ConfigureAwait(false);
        }
        else
        {
            foreach (var importedProfile in bundle.Profiles.Select(profile => profile.ToProfile()))
            {
                var index = profiles.FindIndex(profile => profile.Id == importedProfile.Id);
                if (index >= 0)
                {
                    profiles[index] = importedProfile;
                }
                else
                {
                    profiles.Add(importedProfile);
                }
            }

            if (bundle.ActiveProfileId is not null && profiles.Any(profile => profile.Id == bundle.ActiveProfileId))
            {
                activeProfileId = bundle.ActiveProfileId;
            }
            else
            {
                activeProfileId ??= profiles.FirstOrDefault()?.Id;
            }

            await SaveAsync(cancellationToken).ConfigureAwait(false);
        }

        if (!importSecrets)
        {
            return;
        }

        foreach (var profile in bundle.Profiles)
        {
            SaveSecrets(profile.Id, profile.ToSecrets());
        }
    }

    private async Task<bool> TryLoadPrimaryFileAsync(CancellationToken cancellationToken)
    {
        string json;
        try
        {
            json = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(json))
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind == JsonValueKind.Array)
            {
                profiles.AddRange(JsonSerializer.Deserialize<IReadOnlyList<UploadProfile>>(json, JsonOptions.Default) ?? []);
                activeProfileId = profiles.FirstOrDefault()?.Id;
                await SaveAsync(cancellationToken).ConfigureAwait(false);
                return true;
            }

            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            if (document.RootElement.TryGetProperty("profiles", out _))
            {
                var file = JsonSerializer.Deserialize<ProfileFile>(json, JsonOptions.Default);
                profiles.AddRange(file?.Profiles ?? []);
                activeProfileId = file?.ActiveProfileId;
                return true;
            }

            if (TryLoadLegacySingleProfile(document.RootElement, out var profile, out var secrets))
            {
                profiles.Add(profile);
                activeProfileId = profile.Id;
                SaveSecrets(profile.Id, secrets);
                await SaveAsync(cancellationToken).ConfigureAwait(false);
                return true;
            }
        }
        catch (JsonException)
        {
            return false;
        }

        return false;
    }

    private static bool TryLoadLegacySingleProfile(JsonElement root, out UploadProfile profile, out ProfileSecrets secrets)
    {
        profile = UploadProfile.Unconfigured;
        secrets = new ProfileSecrets();
        var endpoint = StringProperty(root, "endpoint") ?? StringProperty(root, "uploadEndpoint") ?? StringProperty(root, "upload_endpoint");
        if (string.IsNullOrWhiteSpace(endpoint) || !Uri.TryCreate(endpoint.Trim(), UriKind.Absolute, out _))
        {
            return false;
        }

        var id = StringProperty(root, "id") ?? "migrated";
        var name = StringProperty(root, "name") ?? "Migrated";
        profile = new UploadProfile(
            string.IsNullOrWhiteSpace(id) ? "migrated" : id.Trim(),
            string.IsNullOrWhiteSpace(name) ? "Migrated" : name.Trim(),
            endpoint.Trim(),
            UploadBackend.ZiplineV4,
            null,
            null);
        secrets = new ProfileSecrets(ZiplineApiKey: FirstNonEmpty(
            StringProperty(root, "apiKey"),
            StringProperty(root, "uploadApiKey"),
            StringProperty(root, "upload_api_key")));
        return true;
    }

    private async Task<IReadOnlyList<UploadProfile>> LoadProfilesConfigBackupAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(profileBackupPath))
        {
            return [];
        }

        try
        {
            await using var stream = File.OpenRead(profileBackupPath);
            return await JsonSerializer.DeserializeAsync<IReadOnlyList<UploadProfile>>(stream, JsonOptions.Default, cancellationToken).ConfigureAwait(false) ?? [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return [];
        }
    }

    private async Task SaveAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await using var stream = File.Create(path);
        var file = new ProfileFile(Version: 1, ActiveProfileId: activeProfileId, Profiles: profiles);
        await JsonSerializer.SerializeAsync(stream, file, JsonOptions.Default, cancellationToken).ConfigureAwait(false);
        await PersistProfilesConfigBackupAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task PersistProfilesConfigBackupAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(profileBackupPath)!);
        await using var stream = File.Create(profileBackupPath);
        await JsonSerializer.SerializeAsync(stream, profiles, JsonOptions.Default, cancellationToken).ConfigureAwait(false);
    }

    private void EnsureActiveProfileSetIfNeeded()
    {
        if (profiles.Count == 0)
        {
            activeProfileId = null;
            return;
        }

        if (activeProfileId is not null && profiles.Any(profile => profile.Id == activeProfileId))
        {
            return;
        }

        activeProfileId = profiles[0].Id;
    }

    private void WriteSecret(string account, string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            secretStore.DeleteSecret(ProfileSecretAccounts.UploadProfileService, account);
            return;
        }

        secretStore.SetSecret(ProfileSecretAccounts.UploadProfileService, account, value);
    }

    private void ClearAllProfileSecrets()
    {
        foreach (var profile in profiles)
        {
            SaveSecrets(profile.Id, new ProfileSecrets());
        }
    }

    private static string? StringProperty(JsonElement element, string name) =>
        element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;

    private static string? FirstNonEmpty(params string?[] values) =>
        values.Select(value => value?.Trim()).FirstOrDefault(value => !string.IsNullOrEmpty(value));

    private sealed record ProfileFile(int Version, string? ActiveProfileId, IReadOnlyList<UploadProfile>? Profiles);
}
