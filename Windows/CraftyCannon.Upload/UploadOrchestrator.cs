using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public sealed record UrlRewriteOptions(bool Enabled, string Pattern, string Replacement);

public sealed record UploadOrchestrationRequest(
    string FilePath,
    UploadProfile PrimaryProfile,
    ProfileSecrets PrimarySecrets,
    UploadSourceKind SourceKind,
    string? RemoteFilename = null,
    string? UploadContext = null,
    int? ExpiresSeconds = null,
    UrlRewriteOptions? Rewrite = null,
    UploadProfile? SecondaryProfile = null,
    ProfileSecrets? SecondarySecrets = null,
    DateTimeOffset? Now = null,
    string? RandomToken = null,
    string? BatchId = null,
    UploadRecordKind RecordKind = UploadRecordKind.Unknown,
    UploadOperationKind OperationKind = UploadOperationKind.Unknown,
    OcrIndexStatus OcrStatus = OcrIndexStatus.NotQueued,
    bool IsManagedLocalCopy = false);

public sealed class UploadOrchestrator
{
    private readonly ZiplineClient ziplineClient;
    private readonly S3Client s3Client;
    private readonly IUploadHistoryWriter history;

    public UploadOrchestrator(ZiplineClient ziplineClient, S3Client s3Client, IUploadHistoryWriter history)
    {
        this.ziplineClient = ziplineClient;
        this.s3Client = s3Client;
        this.history = history;
    }

    public async Task<UploadRecord> UploadAsync(UploadOrchestrationRequest request, CancellationToken cancellationToken = default)
    {
        var now = request.Now ?? DateTimeOffset.UtcNow;
        var record = new UploadRecord(
            Guid.NewGuid().ToString("N"),
            UploadStatus.Uploading,
            now,
            Path.GetFileName(request.RemoteFilename ?? request.FilePath),
            request.FilePath,
            null,
            request.PrimaryProfile.Name,
            null,
            SourceKind: request.SourceKind,
            BatchId: request.BatchId,
            IsManagedLocalCopy: request.IsManagedLocalCopy,
            OcrStatus: request.OcrStatus,
            RecordKind: request.RecordKind,
            OperationKind: request.OperationKind);

        return await UploadIntoRecordAsync(record, request, now, cancellationToken).ConfigureAwait(false);
    }

    public async Task<UploadRecord> ReuploadAsync(UploadRecord existingRecord, UploadOrchestrationRequest request, CancellationToken cancellationToken = default)
    {
        var now = request.Now ?? DateTimeOffset.UtcNow;
        var record = existingRecord with
        {
            Status = UploadStatus.Uploading,
            ErrorMessage = null,
            SourceKind = UploadSourceKind.Reupload,
            ProfileName = request.PrimaryProfile.Name,
            FileName = Path.GetFileName(request.RemoteFilename ?? request.FilePath),
            LocalFilePath = request.FilePath,
            RecordKind = request.RecordKind,
            OperationKind = request.OperationKind,
            IsManagedLocalCopy = request.IsManagedLocalCopy,
            OcrStatus = request.OcrStatus,
            OcrText = null,
            OcrEngine = null,
            OcrEngineVersion = null,
            OcrIndexedAt = null,
            OcrFileSize = null,
            OcrFileModifiedAt = null,
            OcrError = null,
            OcrRetryCount = null
        };

        return await UploadIntoRecordAsync(record, request, now, cancellationToken).ConfigureAwait(false);
    }

    private async Task<UploadRecord> UploadIntoRecordAsync(UploadRecord record, UploadOrchestrationRequest request, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await history.UpsertAsync(record, cancellationToken).ConfigureAwait(false);

        try
        {
            var primary = await UploadPrimaryAsync(request, now, cancellationToken).ConfigureAwait(false);
            var rewrittenUrl = ApplyRewrite(primary.Url, request.Rewrite);
            record = record with
            {
                Status = UploadStatus.Uploaded,
                RemoteUrl = rewrittenUrl,
                RemotePath = primary.Key,
                ExpiresAt = primary.ExpiresAt,
                ErrorMessage = null
            };
            await history.UpsertAsync(record, cancellationToken).ConfigureAwait(false);

            record = await TrySecondaryMirrorAsync(request, record, now, cancellationToken).ConfigureAwait(false);
            return record;
        }
        catch (Exception ex)
        {
            record = record with
            {
                Status = UploadStatus.Failed,
                ErrorMessage = ex.Message
            };
            await history.UpsertAsync(record, cancellationToken).ConfigureAwait(false);
            return record;
        }
    }

    private Task<UploadFileResult> UploadPrimaryAsync(UploadOrchestrationRequest request, DateTimeOffset now, CancellationToken cancellationToken) =>
        request.PrimaryProfile.Backend switch
        {
            UploadBackend.ZiplineV4 => ziplineClient.UploadAsync(new UploadFileRequest(
                request.FilePath,
                request.PrimaryProfile,
                request.PrimarySecrets,
                request.RemoteFilename,
                request.UploadContext,
                request.ExpiresSeconds is int seconds ? now.AddSeconds(seconds) : null,
                request.ExpiresSeconds,
                request.RandomToken,
                now), cancellationToken),
            UploadBackend.S3Compatible => s3Client.UploadAsync(new UploadFileRequest(
                request.FilePath,
                request.PrimaryProfile,
                request.PrimarySecrets,
                request.RemoteFilename,
                request.UploadContext,
                null,
                request.ExpiresSeconds,
                request.RandomToken,
                now), cancellationToken),
            _ => throw new UploadException("Unsupported upload backend.")
        };

    private async Task<UploadRecord> TrySecondaryMirrorAsync(
        UploadOrchestrationRequest request,
        UploadRecord record,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (request.PrimaryProfile.Backend != UploadBackend.ZiplineV4 ||
            request.SecondaryProfile is not { Backend: UploadBackend.S3Compatible } secondary ||
            request.SecondarySecrets is null)
        {
            return record with { SecondaryStatus = SecondaryUploadStatus.NotConfigured };
        }

        record = record with { SecondaryStatus = SecondaryUploadStatus.Pending };
        await history.UpsertAsync(record, cancellationToken).ConfigureAwait(false);

        try
        {
            var mirror = await s3Client.UploadAsync(new UploadFileRequest(
                request.FilePath,
                secondary,
                request.SecondarySecrets,
                request.RemoteFilename,
                request.UploadContext,
                null,
                request.ExpiresSeconds,
                request.RandomToken,
                now), cancellationToken).ConfigureAwait(false);
            record = record with
            {
                SecondaryStatus = SecondaryUploadStatus.Uploaded,
                SecondaryUrl = ApplyRewrite(mirror.Url, request.Rewrite),
                SecondaryPath = mirror.Key,
                SecondaryError = null,
                SecondaryCompletedAt = DateTimeOffset.UtcNow
            };
        }
        catch (Exception ex)
        {
            record = record with
            {
                SecondaryStatus = SecondaryUploadStatus.Failed,
                SecondaryError = ex.Message,
                SecondaryCompletedAt = DateTimeOffset.UtcNow
            };
        }

        await history.UpsertAsync(record, cancellationToken).ConfigureAwait(false);
        return record;
    }

    private static string ApplyRewrite(string url, UrlRewriteOptions? rewrite) =>
        rewrite is null ? url : URLRewriteService.Apply(url, rewrite.Enabled, rewrite.Pattern, rewrite.Replacement);
}







