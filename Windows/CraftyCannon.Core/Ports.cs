namespace CraftyCannon.Core;

public interface ISecretStore
{
    string? GetSecret(string service, string account);

    void SetSecret(string service, string account, string secret);

    void DeleteSecret(string service, string account);
}

public interface IProfileStore
{
    IReadOnlyList<UploadProfile> Profiles { get; }

    UploadProfile? ActiveProfile { get; }
}

public interface IUploadHistoryStore
{
    IReadOnlyList<UploadRecord> Records { get; }
}

public interface IUploadHistoryWriter : IUploadHistoryStore
{
    Task UpsertAsync(UploadRecord record, CancellationToken cancellationToken = default);

    Task DeleteAsync(string id, CancellationToken cancellationToken = default);
}

public interface IOcrIndexingService
{
    Task<UploadRecord> IndexRecordAsync(
        UploadRecord record,
        string? sourcePath = null,
        bool force = false,
        bool enabled = true,
        CancellationToken cancellationToken = default);

    Task<OcrBatchSummary> RunBatchAsync(OcrBatchMode mode, CancellationToken cancellationToken = default);

    Task ClearIndexAsync(CancellationToken cancellationToken = default);
}

public enum OcrBatchMode
{
    IndexExisting,
    Rebuild
}

public sealed record OcrBatchSummary(
    int Total,
    int Indexed = 0,
    int Skipped = 0,
    int Failed = 0,
    int Missing = 0,
    int Disabled = 0);
public interface IClipboardService
{
    ClipboardSnapshot ReadSnapshot();

    bool TrySetText(string text);

    bool TrySetImage(string imagePath);
}

public interface IShellLauncher
{
    bool TryOpenUrl(string url);
}

public interface IFileRevealLauncher
{
    bool TryRevealFile(string path);
}

public interface IEditorLauncher
{
    bool TryOpenRecord(string recordId);
}



