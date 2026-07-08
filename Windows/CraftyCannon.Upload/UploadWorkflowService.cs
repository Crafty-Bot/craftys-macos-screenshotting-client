using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public sealed record UploadWorkflowOptions(
    UploadProfile PrimaryProfile,
    ProfileSecrets PrimarySecrets,
    int DefaultFileExpirySeconds,
    AfterUploadTaskOptions AfterUpload,
    AfterCaptureTaskOptions AfterCapture,
    PasteTargetInfo PasteTarget,
    UrlRewriteOptions? Rewrite = null,
    UploadProfile? SecondaryProfile = null,
    ProfileSecrets? SecondarySecrets = null,
    ShortenerRequest? Shortener = null,
    DateTimeOffset? Now = null,
    string? RandomToken = null,
    UploadRedactionPolicy RedactionPolicy = UploadRedactionPolicy.Off,
    bool EnableOcrIndexing = true,
    IReadOnlyList<UploadRouteProfile>? RoutedProfiles = null,
    IReadOnlyList<UploaderFilterRule>? UploaderFilters = null,
    DestinationRoutingConfig? DestinationRouting = null,
    SmartRedactionRenderMode SmartRedactionRenderMode = SmartRedactionRenderMode.Pixelate,
    bool StripImageMetadataBeforeUpload = false,
    ImageUploadFormat ImageUploadFormat = ImageUploadFormat.Png,
    UploadFileNamingOptions? FileNaming = null);

public enum UploadWorkflowOutcomeKind
{
    Uploaded,
    UploadedBatch,
    ShortenedUrl,
    CopiedUrl,
    Unsupported
}

public sealed record UploadWorkflowOutcome(
    UploadWorkflowOutcomeKind Kind,
    IReadOnlyList<UploadRecord> Records,
    string? Url = null,
    string? Message = null,
    IReadOnlyList<PostUploadExecutionStep>? PostUploadSteps = null)
{
    public IReadOnlyList<PostUploadExecutionStep> EffectivePostUploadSteps => PostUploadSteps ?? [];
}

public sealed class UploadWorkflowService(
    UploadPayloadPreparer preparer,
    UploadOrchestrator orchestrator,
    URLShortenerClient shortenerClient,
    PostUploadActionExecutor postUploadExecutor,
    TempFileGuard tempFileGuard,
    IOcrIndexingService? ocrIndexingService = null,
    IUploadRedactionService? uploadRedactionService = null,
    IImageUploadPreprocessor? imageUploadPreprocessor = null)
{
    public async Task<UploadWorkflowOutcome> ExecuteClipboardAsync(
        ClipboardSnapshot snapshot,
        ClipboardUploadRules rules,
        UploadWorkflowOptions options,
        CancellationToken cancellationToken = default)
    {
        var dispatch = ClipboardUploadDispatcher.Resolve(snapshot, rules);
        return dispatch.Kind switch
        {
            ClipboardDispatchActionKind.UploadImage => await UploadPayloadAsync(
                new PreparedUploadPayload(RequiredValue(dispatch), UploadPayloadKind.Image, dispatch.SourceKind, UploadContext: "clipboard-image"),
                options,
                cancellationToken).ConfigureAwait(false),
            ClipboardDispatchActionKind.UploadFile => await UploadPayloadAsync(
                preparer.PrepareLocalFile(RequiredValue(dispatch), dispatch.SourceKind),
                options,
                cancellationToken).ConfigureAwait(false),
            ClipboardDispatchActionKind.IndexFolder => await UploadPayloadAsync(
                await preparer.PrepareFolderIndexAsync(RequiredValue(dispatch), includeSubdirectories: true, dispatch.SourceKind, cancellationToken: cancellationToken).ConfigureAwait(false),
                options,
                cancellationToken).ConfigureAwait(false),
            ClipboardDispatchActionKind.UploadRemoteUrl => await UploadPayloadAsync(
                await preparer.PrepareRemoteUrlAsync(RequiredValue(dispatch), dispatch.SourceKind, cancellationToken).ConfigureAwait(false),
                options,
                cancellationToken).ConfigureAwait(false),
            ClipboardDispatchActionKind.UploadText => await UploadPayloadAsync(
                await preparer.PrepareTextAsync(RequiredValue(dispatch), dispatch.SourceKind, cancellationToken).ConfigureAwait(false),
                options,
                cancellationToken).ConfigureAwait(false),
            ClipboardDispatchActionKind.ShortenUrl => await ShortenUrlAsync(RequiredValue(dispatch), options, cancellationToken).ConfigureAwait(false),
            ClipboardDispatchActionKind.CopyUrlOnly => CopyUrl(RequiredValue(dispatch)),
            _ => new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.Unsupported, [], Message: "Clipboard content is not supported by the current upload rules.")
        };
    }

    public Task<UploadWorkflowOutcome> UploadLocalFileAsync(
        string filePath,
        UploadWorkflowOptions options,
        UploadSourceKind sourceKind = UploadSourceKind.ManualFile,
        bool isManagedLocalCopy = false,
        CancellationToken cancellationToken = default)
    {
        var payload = preparer.PrepareLocalFile(filePath, sourceKind);
        if (sourceKind == UploadSourceKind.ManualFile)
        {
            payload = payload with { UploadContext = payload.Kind == UploadPayloadKind.Image ? "manual-file" : "file" };
        }

        return UploadPayloadAsync(payload, options, cancellationToken, isManagedLocalCopy: isManagedLocalCopy);
    }

    public Task<UploadWorkflowOutcome> UploadExpiringLocalFileAsync(
        string filePath,
        int expiresSeconds,
        UploadWorkflowOptions options,
        UploadSourceKind sourceKind = UploadSourceKind.ManualFile,
        bool isManagedLocalCopy = false,
        CancellationToken cancellationToken = default)
    {
        if (expiresSeconds <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(expiresSeconds), "Expiry must be positive.");
        }

        var payload = preparer.PrepareLocalFile(filePath, sourceKind) with
        {
            Kind = UploadPayloadKind.File,
            UploadContext = "manual-file"
        };
        return UploadPayloadAsync(payload, options with { DefaultFileExpirySeconds = expiresSeconds }, cancellationToken);
    }

    public async Task<UploadWorkflowOutcome> ReuploadHistoryRecordAsync(
        UploadRecord record,
        UploadWorkflowOptions options,
        int? expiresSeconds = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(record.LocalFilePath))
        {
            throw new UploadPayloadPreparationException("No local file available to re-upload.");
        }

        var payload = preparer.PrepareLocalFile(record.LocalFilePath, UploadSourceKind.Reupload);
        if (record.RecordKind == UploadRecordKind.File)
        {
            payload = payload with { Kind = UploadPayloadKind.File, UploadContext = "file" };
        }

        var effectiveOptions = expiresSeconds is int seconds
            ? options with { DefaultFileExpirySeconds = seconds }
            : options;
        var preparation = await PreparePayloadForUploadAsync(payload, effectiveOptions, record.IsManagedLocalCopy, cancellationToken).ConfigureAwait(false);
        if (preparation.BlockedOutcome is not null)
        {
            return preparation.BlockedOutcome;
        }

        var uploadPayload = preparation.Payload;
        try
        {
            var route = ResolveUploadRoute(payload, effectiveOptions);
            var remoteFilename = UploadFilenameGenerator.GenerateRemoteFilename(uploadPayload.FilePath, effectiveOptions.FileNaming, effectiveOptions.Now ?? DateTimeOffset.UtcNow, effectiveOptions.RandomToken);
            var reuploaded = await orchestrator.ReuploadAsync(record, new UploadOrchestrationRequest(
                uploadPayload.FilePath,
                route.Primary.Profile,
                route.Primary.Secrets,
                UploadSourceKind.Reupload,
                RemoteFilename: remoteFilename,
                UploadContext: uploadPayload.UploadContext,
                ExpiresSeconds: DefaultExpiryFor(uploadPayload, effectiveOptions),
                Rewrite: effectiveOptions.Rewrite,
                SecondaryProfile: route.Secondary?.Profile,
                SecondarySecrets: route.Secondary?.Secrets,
                Now: effectiveOptions.Now,
                RandomToken: effectiveOptions.RandomToken,
                RecordKind: RecordKindFor(uploadPayload),
                OperationKind: OperationKindFor(uploadPayload),
                OcrStatus: InitialOcrStatusFor(uploadPayload, effectiveOptions),
                IsManagedLocalCopy: preparation.IsManagedLocalCopy), cancellationToken).ConfigureAwait(false);

            reuploaded = await IndexOcrIfNeededAsync(reuploaded, uploadPayload, effectiveOptions, cancellationToken).ConfigureAwait(false);
            var steps = ExecutePostUpload(reuploaded, uploadPayload, effectiveOptions);
            return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.Uploaded, [reuploaded], SuccessfulUrl(reuploaded), Message: FailureMessage(reuploaded), PostUploadSteps: steps);
        }
        finally
        {
            if (!string.Equals(uploadPayload.FilePath, payload.FilePath, StringComparison.OrdinalIgnoreCase))
            {
                CleanupTemporaryPayload(uploadPayload);
            }
        }
    }
    public async Task<UploadWorkflowOutcome> UploadRemoteUrlAsync(
        string url,
        UploadWorkflowOptions options,
        UploadSourceKind sourceKind = UploadSourceKind.ManualRemoteUrl,
        CancellationToken cancellationToken = default) =>
        await UploadPayloadAsync(
            await preparer.PrepareRemoteUrlAsync(url, sourceKind, cancellationToken).ConfigureAwait(false),
            options,
            cancellationToken).ConfigureAwait(false);

    public async Task<UploadWorkflowOutcome> UploadTextAsync(
        string text,
        UploadWorkflowOptions options,
        UploadSourceKind sourceKind = UploadSourceKind.ManualText,
        CancellationToken cancellationToken = default) =>
        await UploadPayloadAsync(
            await preparer.PrepareTextAsync(text, sourceKind, cancellationToken).ConfigureAwait(false),
            options,
            cancellationToken).ConfigureAwait(false);

    public async Task<UploadWorkflowOutcome> UploadFolderIndexAsync(
        string folderPath,
        UploadWorkflowOptions options,
        UploadSourceKind sourceKind = UploadSourceKind.ManualFolderIndex,
        CancellationToken cancellationToken = default) =>
        await UploadPayloadAsync(
            await preparer.PrepareFolderIndexAsync(folderPath, includeSubdirectories: true, sourceKind, cancellationToken: cancellationToken).ConfigureAwait(false),
            options,
            cancellationToken).ConfigureAwait(false);
    public async Task<UploadWorkflowOutcome> UploadFolderBatchAsync(
        string folderPath,
        bool includeSubdirectories,
        UploadWorkflowOptions options,
        UploadSourceKind sourceKind = UploadSourceKind.ManualFolderBatch,
        CancellationToken cancellationToken = default)
    {
        var batch = preparer.PrepareFolderBatch(folderPath, includeSubdirectories, sourceKind);
        if (batch.Payloads.Count == 0)
        {
            return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.Unsupported, [], Message: "Folder contains no files.");
        }

        var records = new List<UploadRecord>();
        var steps = new List<PostUploadExecutionStep>();
        foreach (var payload in batch.Payloads)
        {
            var outcome = await UploadPayloadAsync(payload, options, cancellationToken, batch.BatchId).ConfigureAwait(false);
            records.AddRange(outcome.Records);
            steps.AddRange(outcome.EffectivePostUploadSteps);
        }

        return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.UploadedBatch, records, Message: $"Queued {records.Count} file(s).", PostUploadSteps: steps);
    }

    public async Task<UploadWorkflowOutcome> UploadPayloadAsync(
        PreparedUploadPayload payload,
        UploadWorkflowOptions options,
        CancellationToken cancellationToken = default,
        string? batchId = null,
        bool isManagedLocalCopy = false)
    {
        var preparation = await PreparePayloadForUploadAsync(payload, options, isManagedLocalCopy, cancellationToken).ConfigureAwait(false);
        if (preparation.BlockedOutcome is not null)
        {
            CleanupTemporaryPayload(payload);
            return preparation.BlockedOutcome;
        }

        var uploadPayload = preparation.Payload;
        var effectiveManagedLocalCopy = preparation.IsManagedLocalCopy;
        try
        {
            var route = ResolveUploadRoute(payload, options);
            var remoteFilename = UploadFilenameGenerator.GenerateRemoteFilename(uploadPayload.FilePath, options.FileNaming, options.Now ?? DateTimeOffset.UtcNow, options.RandomToken);
            var record = await orchestrator.UploadAsync(new UploadOrchestrationRequest(
                uploadPayload.FilePath,
                route.Primary.Profile,
                route.Primary.Secrets,
                uploadPayload.SourceKind,
                RemoteFilename: remoteFilename,
                UploadContext: uploadPayload.UploadContext,
                ExpiresSeconds: DefaultExpiryFor(uploadPayload, options),
                Rewrite: options.Rewrite,
                SecondaryProfile: route.Secondary?.Profile,
                SecondarySecrets: route.Secondary?.Secrets,
                Now: options.Now,
                RandomToken: options.RandomToken,
                BatchId: batchId,
                RecordKind: RecordKindFor(uploadPayload),
                OperationKind: OperationKindFor(uploadPayload),
                OcrStatus: InitialOcrStatusFor(uploadPayload, options),
                IsManagedLocalCopy: effectiveManagedLocalCopy), cancellationToken).ConfigureAwait(false);

            record = await IndexOcrIfNeededAsync(record, uploadPayload, options, cancellationToken).ConfigureAwait(false);
            var steps = ExecutePostUpload(record, uploadPayload, options);
            return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.Uploaded, [record], SuccessfulUrl(record), Message: FailureMessage(record), PostUploadSteps: steps);
        }
        finally
        {
            CleanupTemporaryPayload(payload);
            if (!string.Equals(uploadPayload.FilePath, payload.FilePath, StringComparison.OrdinalIgnoreCase))
            {
                CleanupTemporaryPayload(uploadPayload);
            }
        }
    }
    private async Task<PreparedPayloadForUpload> PreparePayloadForUploadAsync(
        PreparedUploadPayload payload,
        UploadWorkflowOptions options,
        bool isManagedLocalCopy,
        CancellationToken cancellationToken)
    {
        if (!IsImagePayload(payload))
        {
            return new PreparedPayloadForUpload(payload, isManagedLocalCopy);
        }

        var preparedPayload = payload;
        var preparedManagedCopy = isManagedLocalCopy;

        if (RequiresRedactionCheck(preparedPayload, options))
        {
            if (uploadRedactionService is null)
            {
                return PreparedPayloadForUpload.Blocked("Redaction check is required for image uploads, but Windows smart redaction detection is not available yet.");
            }

            var redaction = await uploadRedactionService.PrepareImageAsync(
                preparedPayload.FilePath,
                options.RedactionPolicy,
                options.SmartRedactionRenderMode,
                cancellationToken).ConfigureAwait(false);
            switch (redaction.Kind)
            {
                case UploadRedactionResultKind.Original:
                    break;
                case UploadRedactionResultKind.Redacted when !string.IsNullOrWhiteSpace(redaction.FilePath):
                    preparedPayload = preparedPayload with { FilePath = redaction.FilePath, TemporarySourceFile = !redaction.IsManagedLocalCopy, MimeType = "image/png" };
                    preparedManagedCopy = preparedManagedCopy || redaction.IsManagedLocalCopy;
                    break;
                case UploadRedactionResultKind.Cancelled:
                    return PreparedPayloadForUpload.Blocked(redaction.Message ?? "Upload cancelled.");
                default:
                    return PreparedPayloadForUpload.Blocked(redaction.Message ?? "Redaction check failed; upload was not sent.");
            }
        }

        if (imageUploadPreprocessor is null)
        {
            return new PreparedPayloadForUpload(preparedPayload, preparedManagedCopy);
        }

        var preprocessing = await imageUploadPreprocessor.PrepareImageAsync(
            preparedPayload.FilePath,
            options.StripImageMetadataBeforeUpload,
            options.ImageUploadFormat,
            cancellationToken).ConfigureAwait(false);
        return preprocessing.Kind switch
        {
            ImageUploadPreprocessingResultKind.Original => new PreparedPayloadForUpload(preparedPayload, preparedManagedCopy),
            ImageUploadPreprocessingResultKind.Preprocessed when !string.IsNullOrWhiteSpace(preprocessing.FilePath) => new PreparedPayloadForUpload(
                preparedPayload with { FilePath = preprocessing.FilePath, TemporarySourceFile = true, MimeType = preprocessing.MimeType },
                preparedManagedCopy),
            _ => PreparedPayloadForUpload.Blocked(preprocessing.Message ?? "Image upload preparation failed; upload was not sent.")
        };
    }
    public async Task<UploadWorkflowOutcome> ShortenUrlAsync(string url, UploadWorkflowOptions options, CancellationToken cancellationToken = default)
    {
        if (options.Shortener is null)
        {
            return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.Unsupported, [], Message: "URL shortener is not configured.");
        }

        var shortened = await shortenerClient.ShortenAsync(url, options.Shortener, cancellationToken).ConfigureAwait(false);
        var steps = postUploadExecutor.Execute([new PostUploadAction(PostUploadActionKind.CopyText, shortened)]);
        return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.ShortenedUrl, [], shortened, PostUploadSteps: steps);
    }


    private sealed record PreparedPayloadForUpload(
        PreparedUploadPayload Payload,
        bool IsManagedLocalCopy,
        UploadWorkflowOutcome? BlockedOutcome = null)
    {
        public static PreparedPayloadForUpload Blocked(string message) =>
            new(new PreparedUploadPayload(string.Empty, UploadPayloadKind.File, UploadSourceKind.File), false, new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.Unsupported, [], Message: message));
    }
    private static ResolvedUploadRoute ResolveUploadRoute(PreparedUploadPayload payload, UploadWorkflowOptions options)
    {
        var profiles = BuildRouteProfiles(options);
        var primary = ResolvePrimaryRoute(payload, DestinationKindFor(payload), options, profiles);
        var secondary = ResolveSecondaryRoute(primary.Profile, profiles);
        return new ResolvedUploadRoute(primary, secondary);
    }

    private static UploadRouteProfile ResolvePrimaryRoute(
        PreparedUploadPayload payload,
        DestinationKind destinationKind,
        UploadWorkflowOptions options,
        IReadOnlyList<UploadRouteProfile> profiles)
    {
        var extension = Path.GetExtension(payload.FilePath);
        foreach (var rule in options.UploaderFilters ?? [])
        {
            var normalizedRule = rule.Normalized;
            if (normalizedRule.Matches(extension) && FindRouteProfile(profiles, normalizedRule.ProfileId) is { } routedByExtension)
            {
                return routedByExtension;
            }
        }

        var routeProfileId = options.DestinationRouting?.ProfileIdFor(destinationKind);
        if (FindRouteProfile(profiles, routeProfileId) is { } routedByKind)
        {
            return routedByKind;
        }

        return profiles.First();
    }

    private static UploadRouteProfile? ResolveSecondaryRoute(UploadProfile primary, IReadOnlyList<UploadRouteProfile> profiles)
    {
        if (primary.Backend != UploadBackend.ZiplineV4 || string.IsNullOrWhiteSpace(primary.SecondaryS3ProfileId))
        {
            return null;
        }

        var secondary = FindRouteProfile(profiles, primary.SecondaryS3ProfileId);
        return secondary?.Profile.Backend == UploadBackend.S3Compatible ? secondary : null;
    }

    private static IReadOnlyList<UploadRouteProfile> BuildRouteProfiles(UploadWorkflowOptions options)
    {
        var routes = (options.RoutedProfiles ?? [])
            .Where(route => route.Profile != UploadProfile.Unconfigured)
            .GroupBy(route => route.Profile.Id, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToArray();

        if (routes.Length > 0)
        {
            return routes;
        }

        var fallback = new List<UploadRouteProfile> { new(options.PrimaryProfile, options.PrimarySecrets) };
        if (options.SecondaryProfile is not null && options.SecondarySecrets is not null)
        {
            fallback.Add(new UploadRouteProfile(options.SecondaryProfile, options.SecondarySecrets));
        }

        return fallback;
    }

    private static UploadRouteProfile? FindRouteProfile(IReadOnlyList<UploadRouteProfile> profiles, string? profileId) =>
        string.IsNullOrWhiteSpace(profileId)
            ? null
            : profiles.FirstOrDefault(route => string.Equals(route.Profile.Id, profileId.Trim(), StringComparison.Ordinal));

    private static DestinationKind DestinationKindFor(PreparedUploadPayload payload) =>
        payload.Kind switch
        {
            UploadPayloadKind.Image or UploadPayloadKind.RemoteImage => DestinationKind.Image,
            UploadPayloadKind.Text or UploadPayloadKind.FolderIndex => DestinationKind.Text,
            _ => DestinationKind.File
        };

    private sealed record ResolvedUploadRoute(UploadRouteProfile Primary, UploadRouteProfile? Secondary);
    private async Task<UploadRecord> IndexOcrIfNeededAsync(
        UploadRecord record,
        PreparedUploadPayload payload,
        UploadWorkflowOptions options,
        CancellationToken cancellationToken)
    {
        if (ocrIndexingService is null || !IsImagePayload(payload))
        {
            return record;
        }

        return await ocrIndexingService.IndexRecordAsync(
            record,
            payload.FilePath,
            enabled: options.EnableOcrIndexing,
            cancellationToken: cancellationToken).ConfigureAwait(false);
    }
    private static string? SuccessfulUrl(UploadRecord record) =>
        record.Status == UploadStatus.Uploaded ? UploadHistoryActions.PreferredUrl(record) : null;

    private static string? FailureMessage(UploadRecord record) =>
        record.Status == UploadStatus.Failed ? "Upload failed: " + (record.ErrorMessage ?? "Unknown error") : null;

    private UploadWorkflowOutcome CopyUrl(string url)
    {
        var steps = postUploadExecutor.Execute([new PostUploadAction(PostUploadActionKind.CopyText, url)]);
        return new UploadWorkflowOutcome(UploadWorkflowOutcomeKind.CopiedUrl, [], url, PostUploadSteps: steps);
    }

    private IReadOnlyList<PostUploadExecutionStep> ExecutePostUpload(UploadRecord record, PreparedUploadPayload payload, UploadWorkflowOptions options)
    {
        var url = UploadHistoryActions.PreferredUrl(record);
        if (record.Status != UploadStatus.Uploaded || string.IsNullOrWhiteSpace(url))
        {
            return [];
        }

        var imagePath = IsImagePayload(payload) ? payload.FilePath : null;
        var actions = PostUploadPlanner.Plan(record, url, imagePath, options.AfterUpload, options.AfterCapture, options.PasteTarget);
        return postUploadExecutor.Execute(actions);
    }

    private void CleanupTemporaryPayload(PreparedUploadPayload payload)
    {
        if (!payload.TemporarySourceFile || !File.Exists(payload.FilePath) || !tempFileGuard.IsSafeToDelete(payload.FilePath))
        {
            return;
        }

        File.Delete(payload.FilePath);
    }

    private static UploadRecordKind RecordKindFor(PreparedUploadPayload payload) =>
        payload.Kind switch
        {
            UploadPayloadKind.Image => UploadRecordKind.Image,
            UploadPayloadKind.RemoteImage => UploadRecordKind.RemoteImage,
            UploadPayloadKind.Text => UploadRecordKind.Text,
            UploadPayloadKind.RemoteFile => UploadRecordKind.RemoteFile,
            UploadPayloadKind.FolderIndex => UploadRecordKind.FolderIndex,
            _ => UploadRecordKind.File
        };

    private static OcrIndexStatus InitialOcrStatusFor(PreparedUploadPayload payload, UploadWorkflowOptions options) =>
        IsImagePayload(payload) ? (options.EnableOcrIndexing ? OcrIndexStatus.Pending : OcrIndexStatus.Disabled) : OcrIndexStatus.NotQueued;

    private static UploadOperationKind OperationKindFor(PreparedUploadPayload payload) =>
        payload.Kind switch
        {
            UploadPayloadKind.Image or UploadPayloadKind.RemoteImage => UploadOperationKind.ImageUpload,
            UploadPayloadKind.Text => UploadOperationKind.TextUpload,
            UploadPayloadKind.FolderIndex => UploadOperationKind.FolderIndexUpload,
            _ => UploadOperationKind.FileUpload
        };

    private static int? DefaultExpiryFor(PreparedUploadPayload payload, UploadWorkflowOptions options) =>
        IsImagePayload(payload) || options.DefaultFileExpirySeconds <= 0 ? null : options.DefaultFileExpirySeconds;

    private static bool RequiresRedactionCheck(PreparedUploadPayload payload, UploadWorkflowOptions options) =>
        options.RedactionPolicy != UploadRedactionPolicy.Off && IsImagePayload(payload);

    private static bool IsImagePayload(PreparedUploadPayload payload) =>
        payload.Kind is UploadPayloadKind.Image or UploadPayloadKind.RemoteImage;

    private static string RequiredValue(ClipboardDispatchResult result) =>
        string.IsNullOrWhiteSpace(result.Value) ? throw new UploadPayloadPreparationException("Clipboard action has no value.") : result.Value;
}





















