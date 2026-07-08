namespace CraftyCannon.Core;

public static class ProfileSecretAccounts
{
    public const string UploadProfileService = "upload-profile";
    public const string CloudflareService = "cloudflare-allowlist";

    public static string ZiplineApiKey(string profileId) => Account(profileId, "zipline-api-key");

    public static string S3AccessKey(string profileId) => Account(profileId, "s3-access-key");

    public static string S3SecretKey(string profileId) => Account(profileId, "s3-secret-key");

    public static string S3SessionToken(string profileId) => Account(profileId, "s3-session-token");

    public static string CloudflareApiToken(string installId) => Account(installId, "cloudflare-api-token");

    private static string Account(string ownerId, string kind)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(ownerId);
        return $"{ownerId}:{kind}";
    }
}
