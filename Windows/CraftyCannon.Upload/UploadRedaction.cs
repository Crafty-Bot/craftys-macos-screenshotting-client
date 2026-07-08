using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public enum UploadRedactionResultKind
{
    Original,
    Redacted,
    Cancelled,
    Failed
}

public sealed record UploadRedactionResult(
    UploadRedactionResultKind Kind,
    string? FilePath = null,
    bool IsManagedLocalCopy = false,
    string? Message = null)
{
    public static UploadRedactionResult Original(string? message = null) => new(UploadRedactionResultKind.Original, Message: message);

    public static UploadRedactionResult Redacted(string filePath, bool isManagedLocalCopy = true, string? message = null) =>
        new(UploadRedactionResultKind.Redacted, filePath, isManagedLocalCopy, message);

    public static UploadRedactionResult Cancelled(string? message = null) => new(UploadRedactionResultKind.Cancelled, Message: message);

    public static UploadRedactionResult Failed(string message) => new(UploadRedactionResultKind.Failed, Message: message);
}

public interface IUploadRedactionService
{
    Task<UploadRedactionResult> PrepareImageAsync(
        string imagePath,
        UploadRedactionPolicy policy,
        SmartRedactionRenderMode renderMode,
        CancellationToken cancellationToken = default);
}