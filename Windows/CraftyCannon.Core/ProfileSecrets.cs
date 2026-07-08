namespace CraftyCannon.Core;

public sealed record ProfileSecrets(
    string? ZiplineApiKey = null,
    string? S3AccessKey = null,
    string? S3SecretKey = null,
    string? S3SessionToken = null);

public sealed record ProfileExportBundle(
    int Version,
    string? ActiveProfileId,
    IReadOnlyList<ExportedUploadProfile> Profiles,
    DateTimeOffset? ExportedAt = null);

public sealed record ExportedUploadProfile(
    string Id,
    string Name,
    string Endpoint,
    UploadBackend Backend,
    S3DestinationConfig? S3Config,
    string? SecondaryS3ProfileId,
    string? ApiKey,
    string? S3AccessKey,
    string? S3SecretKey,
    string? S3SessionToken)
{
    public UploadProfile ToProfile() => new(Id, Name, Endpoint, Backend, S3Config, SecondaryS3ProfileId);

    public ProfileSecrets ToSecrets() => new(ApiKey, S3AccessKey, S3SecretKey, S3SessionToken);
}
