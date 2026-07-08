using System.Threading;
using CraftyCannon.Core;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public sealed class WindowsWatchFolderManager : IDisposable
{
    private readonly RuntimePreferencesStore preferencesStore;
    private readonly Func<UploadWorkflowOptions?> optionsFactory;
    private readonly Func<UploadWorkflowService?> workflowFactory;
    private readonly Action<string> statusSink;
    private readonly Action<UploadWorkflowOutcome> uploadSucceeded;
    private readonly Action<string, Exception> uploadFailed;
    private readonly Action historyChanged;
    private readonly WatchFolderScanner scanner = new();
    private readonly object gate = new();
    private System.Threading.Timer? timer;
    private bool scanRunning;

    public WindowsWatchFolderManager(
        RuntimePreferencesStore preferencesStore,
        Func<UploadWorkflowOptions?> optionsFactory,
        Func<UploadWorkflowService?> workflowFactory,
        Action<string> statusSink,
        Action<UploadWorkflowOutcome> uploadSucceeded,
        Action<string, Exception> uploadFailed,
        Action historyChanged)
    {
        this.preferencesStore = preferencesStore;
        this.optionsFactory = optionsFactory;
        this.workflowFactory = workflowFactory;
        this.statusSink = statusSink;
        this.uploadSucceeded = uploadSucceeded;
        this.uploadFailed = uploadFailed;
        this.historyChanged = historyChanged;
    }

    public void ApplyCurrentPreferences()
    {
        lock (gate)
        {
            var activeRules = ActiveRules();
            if (preferencesStore.Current.WatchFoldersEnabled && activeRules.Length > 0)
            {
                timer ??= new System.Threading.Timer(_ => _ = ScanAsync(), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2));
                timer.Change(TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2));
                statusSink($"Watch folders active: {activeRules.Length} rule(s).");
            }
            else
            {
                timer?.Dispose();
                timer = null;
                scanner.Reset();
            }
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            timer?.Dispose();
            timer = null;
        }
    }

    private async Task ScanAsync()
    {
        lock (gate)
        {
            if (scanRunning)
            {
                return;
            }

            scanRunning = true;
        }

        try
        {
            var candidates = scanner.Scan(ActiveRules(), DateTimeOffset.UtcNow);
            foreach (var candidate in candidates)
            {
                await UploadCandidateAsync(candidate).ConfigureAwait(false);
            }
        }
        finally
        {
            lock (gate)
            {
                scanRunning = false;
            }
        }
    }

    private async Task UploadCandidateAsync(WatchFolderCandidate candidate)
    {
        var workflow = workflowFactory();
        if (workflow is null)
        {
            statusSink("Watch folder upload skipped: upload services are not ready.");
            return;
        }

        var options = optionsFactory();
        if (options is null)
        {
            statusSink("Watch folder upload skipped: no upload profile configured.");
            return;
        }

        try
        {
            UploadWorkflowOutcome outcome;
            if (candidate.Mode == WatchFolderMode.ImageOnly && !candidate.IsImage)
            {
                return;
            }

            if (candidate.Mode == WatchFolderMode.FileOnly)
            {
                outcome = await workflow.UploadExpiringLocalFileAsync(
                    candidate.FilePath,
                    candidate.ExpirySeconds ?? options.DefaultFileExpirySeconds,
                    options,
                    UploadSourceKind.WatchFolder).ConfigureAwait(false);
            }
            else if (!candidate.IsImage)
            {
                var fileOptions = candidate.ExpirySeconds is int expiry
                    ? options with { DefaultFileExpirySeconds = expiry }
                    : options;
                outcome = await workflow.UploadLocalFileAsync(
                    candidate.FilePath,
                    fileOptions,
                    UploadSourceKind.WatchFolder).ConfigureAwait(false);
            }
            else
            {
                outcome = await workflow.UploadLocalFileAsync(
                    candidate.FilePath,
                    options,
                    UploadSourceKind.WatchFolder).ConfigureAwait(false);
            }

            statusSink(outcome.Message ?? (outcome.Url is null ? "Watch folder uploaded file." : "Watch folder uploaded: " + outcome.Url));
            uploadSucceeded(outcome);
            historyChanged();
        }
        catch (Exception ex)
        {
            statusSink("Watch folder upload failed: " + ex.Message);
            uploadFailed("Watch folder upload failed", ex);
            historyChanged();
        }
    }

    private WatchFolderRule[] ActiveRules() =>
        preferencesStore.Current.WatchFolderRules?
            .Where(rule => rule.Enabled)
            .ToArray() ?? [];
}