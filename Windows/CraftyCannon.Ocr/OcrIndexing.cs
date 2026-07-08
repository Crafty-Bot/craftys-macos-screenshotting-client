using CraftyCannon.Core;

namespace CraftyCannon.Ocr;

public sealed record OcrTextResult(string Text, string EngineName, string? EngineVersion = null);

public interface IOcrTextRecognizer
{
    string EngineName { get; }

    string? EngineVersion { get; }

    Task<OcrTextResult> RecognizeAsync(string imagePath, CancellationToken cancellationToken = default);
}

public sealed class SidecarOcrTextRecognizer : IOcrTextRecognizer
{
    public string EngineName => "Sidecar OCR test recognizer";

    public string? EngineVersion => "pipeline-v1";

    public Task<OcrTextResult> RecognizeAsync(string imagePath, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var sidecar = imagePath + ".ocr.txt";
        var text = File.Exists(sidecar) ? File.ReadAllText(sidecar) : string.Empty;
        return Task.FromResult(new OcrTextResult(text, EngineName, EngineVersion));
    }
}

public sealed class OcrIndexingService : IOcrIndexingService
{
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff", ".heic", ".heif"
    };

    private readonly IUploadHistoryWriter history;
    private readonly IOcrTextRecognizer recognizer;
    private readonly Func<bool> enabledProvider;

    public OcrIndexingService(
        IUploadHistoryWriter history,
        IOcrTextRecognizer? recognizer = null,
        Func<bool>? enabledProvider = null)
    {
        this.history = history;
        this.recognizer = recognizer ?? new SidecarOcrTextRecognizer();
        this.enabledProvider = enabledProvider ?? (() => true);
    }

    public async Task<UploadRecord> IndexRecordAsync(
        UploadRecord record,
        string? sourcePath = null,
        bool force = false,
        bool enabled = true,
        CancellationToken cancellationToken = default)
    {
        if (!IsImageRecord(record))
        {
            return record;
        }

        if (!enabled || !enabledProvider())
        {
            var disabled = ClearOcr(record) with { OcrStatus = OcrIndexStatus.Disabled };
            await history.UpsertAsync(disabled, cancellationToken).ConfigureAwait(false);
            return disabled;
        }

        var path = string.IsNullOrWhiteSpace(sourcePath) ? record.LocalFilePath : sourcePath;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            var missing = ClearOcr(record) with { OcrStatus = OcrIndexStatus.LocalImageMissing, OcrError = "Local image file is missing." };
            await history.UpsertAsync(missing, cancellationToken).ConfigureAwait(false);
            return missing;
        }

        var fileInfo = new FileInfo(path);
        var modifiedAt = new DateTimeOffset(fileInfo.LastWriteTimeUtc, TimeSpan.Zero);
        if (!force &&
            record.OcrStatus == OcrIndexStatus.Indexed &&
            record.OcrFileSize == fileInfo.Length &&
            record.OcrFileModifiedAt == modifiedAt &&
            record.OcrText is not null)
        {
            return record with { OcrStatus = OcrIndexStatus.Skipped };
        }

        var pending = record with { OcrStatus = OcrIndexStatus.Pending, OcrError = null };
        await history.UpsertAsync(pending, cancellationToken).ConfigureAwait(false);

        try
        {
            var result = await recognizer.RecognizeAsync(path, cancellationToken).ConfigureAwait(false);
            var indexed = pending with
            {
                OcrStatus = OcrIndexStatus.Indexed,
                OcrText = result.Text.Trim(),
                OcrEngine = result.EngineName,
                OcrEngineVersion = result.EngineVersion,
                OcrIndexedAt = DateTimeOffset.UtcNow,
                OcrFileSize = fileInfo.Length,
                OcrFileModifiedAt = modifiedAt,
                OcrError = null,
                OcrRetryCount = 0
            };
            await history.UpsertAsync(indexed, cancellationToken).ConfigureAwait(false);
            return indexed;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            var failed = pending with
            {
                OcrStatus = OcrIndexStatus.Failed,
                OcrEngine = recognizer.EngineName,
                OcrEngineVersion = recognizer.EngineVersion,
                OcrIndexedAt = DateTimeOffset.UtcNow,
                OcrFileSize = fileInfo.Length,
                OcrFileModifiedAt = modifiedAt,
                OcrError = ex.Message,
                OcrRetryCount = (record.OcrRetryCount ?? 0) + 1
            };
            await history.UpsertAsync(failed, cancellationToken).ConfigureAwait(false);
            return failed;
        }
    }

    public async Task<OcrBatchSummary> RunBatchAsync(OcrBatchMode mode, CancellationToken cancellationToken = default)
    {
        var force = mode == OcrBatchMode.Rebuild;
        var records = history.Records.Where(IsImageRecord).ToArray();
        var summary = new MutableBatchSummary(Total: records.Length);
        foreach (var record in records)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var beforeStatus = record.OcrStatus;
            var updated = await IndexRecordAsync(record, force: force, enabled: enabledProvider(), cancellationToken: cancellationToken).ConfigureAwait(false);
            Count(summary, beforeStatus, updated.OcrStatus);
        }

        return summary.ToSummary();
    }

    public async Task ClearIndexAsync(CancellationToken cancellationToken = default)
    {
        foreach (var record in history.Records.ToArray())
        {
            if (IsImageRecord(record) && HasOcrMetadata(record))
            {
                await history.UpsertAsync(ClearOcr(record), cancellationToken).ConfigureAwait(false);
            }
        }
    }

    public static bool IsImageRecord(UploadRecord record) =>
        record.RecordKind is UploadRecordKind.Image or UploadRecordKind.RemoteImage ||
        (record.RecordKind == UploadRecordKind.Unknown && IsImagePath(record.LocalFilePath ?? record.FileName));

    private static bool IsImagePath(string path) => ImageExtensions.Contains(Path.GetExtension(path));

    private static bool HasOcrMetadata(UploadRecord record) =>
        record.OcrStatus != OcrIndexStatus.NotQueued ||
        !string.IsNullOrWhiteSpace(record.OcrText) ||
        !string.IsNullOrWhiteSpace(record.OcrEngine) ||
        !string.IsNullOrWhiteSpace(record.OcrEngineVersion) ||
        record.OcrIndexedAt is not null ||
        record.OcrFileSize is not null ||
        record.OcrFileModifiedAt is not null ||
        !string.IsNullOrWhiteSpace(record.OcrError) ||
        record.OcrRetryCount is not null;

    private static UploadRecord ClearOcr(UploadRecord record) => record with
    {
        OcrStatus = OcrIndexStatus.NotQueued,
        OcrText = null,
        OcrEngine = null,
        OcrEngineVersion = null,
        OcrIndexedAt = null,
        OcrFileSize = null,
        OcrFileModifiedAt = null,
        OcrError = null,
        OcrRetryCount = null
    };

    private static void Count(MutableBatchSummary summary, OcrIndexStatus before, OcrIndexStatus after)
    {
        switch (after)
        {
            case OcrIndexStatus.Indexed:
                if (before == OcrIndexStatus.Indexed)
                {
                    summary.Skipped++;
                }
                else
                {
                    summary.Indexed++;
                }
                break;
            case OcrIndexStatus.Disabled:
                summary.Disabled++;
                break;
            case OcrIndexStatus.LocalImageMissing:
                summary.Missing++;
                break;
            case OcrIndexStatus.Skipped:
                summary.Skipped++;
                break;
            case OcrIndexStatus.Failed:
                summary.Failed++;
                break;
            default:
                summary.Skipped++;
                break;
        }
    }

    private sealed class MutableBatchSummary(int Total)
    {
        public int Total { get; } = Total;
        public int Indexed { get; set; }
        public int Skipped { get; set; }
        public int Failed { get; set; }
        public int Missing { get; set; }
        public int Disabled { get; set; }

        public OcrBatchSummary ToSummary() => new(Total, Indexed, Skipped, Failed, Missing, Disabled);
    }
}




