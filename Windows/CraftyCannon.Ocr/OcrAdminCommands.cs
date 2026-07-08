using CraftyCannon.Core;

namespace CraftyCannon.Ocr;

public static class OcrAdminCommands
{
    private static readonly HashSet<string> SupportedCommands = new(StringComparer.Ordinal)
    {
        "index-existing",
        "rebuild-index",
        "index-status",
        "clear-index"
    };

    public static bool IsSupported(IReadOnlyList<string> arguments) =>
        arguments.Count >= 1 && SupportedCommands.Contains(arguments[0]);

    public static async Task<bool> RunIfNeededAsync(
        IReadOnlyList<string> arguments,
        IOcrIndexingService indexer,
        IUploadHistoryStore history,
        bool enabled,
        TextWriter output,
        CancellationToken cancellationToken = default)
    {
        if (!IsSupported(arguments))
        {
            return false;
        }

        switch (arguments[0])
        {
            case "index-existing":
                PrintSummary("Index existing complete", await indexer.RunBatchAsync(OcrBatchMode.IndexExisting, cancellationToken).ConfigureAwait(false), output);
                return true;
            case "rebuild-index":
                PrintSummary("Rebuild complete", await indexer.RunBatchAsync(OcrBatchMode.Rebuild, cancellationToken).ConfigureAwait(false), output);
                return true;
            case "index-status":
                PrintStatus(history, enabled, output);
                return true;
            case "clear-index":
                await indexer.ClearIndexAsync(cancellationToken).ConfigureAwait(false);
                output.WriteLine("OCR index cleared.");
                return true;
            default:
                return false;
        }
    }

    private static void PrintSummary(string title, OcrBatchSummary summary, TextWriter output)
    {
        output.WriteLine(title);
        output.WriteLine($"total: {summary.Total}");
        output.WriteLine($"indexed: {summary.Indexed}");
        output.WriteLine($"skipped: {summary.Skipped}");
        output.WriteLine($"missing: {summary.Missing}");
        output.WriteLine($"failed: {summary.Failed}");
    }

    private static void PrintStatus(IUploadHistoryStore history, bool enabled, TextWriter output)
    {
        var records = history.Records.Where(OcrIndexingService.IsImageRecord).ToArray();
        var counts = records
            .GroupBy(record => StatusKey(record.OcrStatus))
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);

        output.WriteLine("OCR index status");
        output.WriteLine($"imageRecords: {records.Length}");
        foreach (var key in new[] { "indexed", "pending", "failed", "missingFile", "disabled", "skipped", "notIndexed" })
        {
            if (counts.TryGetValue(key, out var count))
            {
                output.WriteLine($"{key}: {count}");
            }
        }

        output.WriteLine($"enabled: {enabled.ToString().ToLowerInvariant()}");
    }

    private static string StatusKey(OcrIndexStatus status) => status switch
    {
        OcrIndexStatus.Indexed => "indexed",
        OcrIndexStatus.Pending => "pending",
        OcrIndexStatus.Failed => "failed",
        OcrIndexStatus.LocalImageMissing => "missingFile",
        OcrIndexStatus.Disabled => "disabled",
        OcrIndexStatus.Skipped => "skipped",
        _ => "notIndexed"
    };
}
