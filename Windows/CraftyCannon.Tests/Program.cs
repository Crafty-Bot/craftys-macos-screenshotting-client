using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CraftyCannon.App;
using CraftyCannon.Core;
using CraftyCannon.Editor;
using CraftyCannon.Ocr;
using CraftyCannon.Upload;

var tests = new (string Name, Func<Task> Run)[]
{
    ("profile exports redact secrets", ProfileExportsRedactSecrets),
    ("profile import secrets is opt-in", ProfileImportSecretsIsOptIn),
    ("profile import can merge", ProfileImportCanMerge),
    ("profile backup restores corrupt primary", ProfileBackupRestoresCorruptPrimary),
    ("profile load migrates legacy shapes", ProfileLoadMigratesLegacyShapes),
    ("profile active fallback is unconfigured", ProfileActiveFallbackIsUnconfigured),
    ("profile configured detection", ProfileConfiguredDetection),
    ("history upsert delete roundtrips", HistoryUpsertDeleteRoundtrips),
    ("history loads raw record arrays", HistoryLoadsRawRecordArrays),
    ("runtime preferences default and save", RuntimePreferencesDefaultAndSave),
    ("runtime preferences load legacy defaults", RuntimePreferencesLoadLegacyDefaults),
    ("ui palette catalog and runtime roundtrip", UiPaletteCatalogAndRuntimeRoundtrip),
    ("capture snap size parsing and geometry", CaptureSnapSizeParsingAndGeometry),
    ("local mirror filename helpers", LocalMirrorFilenameHelpers),
    ("editor tool catalog includes text variants", EditorToolCatalogIncludesTextVariants),
    ("hotkey preferences normalize", HotKeyPreferencesNormalize),
    ("watch folder preferences save and normalize", WatchFolderPreferencesSaveAndNormalize),
    ("watch folder scanner filters and enumeration", WatchFolderScannerFiltersAndEnumeration),
    ("watch folder scanner baseline stability and dedupe", WatchFolderScannerBaselineStabilityAndDedupe),
    ("smart redaction classifier finds sensitive patterns", SmartRedactionClassifierFindsSensitivePatterns),
    ("smart redaction classifier finds private key blocks", SmartRedactionClassifierFindsPrivateKeyBlocks),
    ("smart redaction classifier matches OCR spaced email", SmartRedactionClassifierMatchesOcrSpacedEmail),
    ("smart redaction classifier avoids common non matches", SmartRedactionClassifierAvoidsCommonNonMatches),
    ("smart redaction Luhn validation", SmartRedactionLuhnValidation),
    ("barcode redaction geometry", BarcodeRedactionGeometryUsesTopLeftBounds),
    ("windows smart redaction detector combines faces", WindowsSmartRedactionDetectorCombinesFaces),
    ("windows smart redaction detector honors settings", WindowsSmartRedactionDetectorHonorsSettings),
    ("redaction renderer applies normalized findings to pixels", RedactionRendererAppliesNormalizedFindingsToPixels),
    ("upload redaction renders normalized findings to png", UploadRedactionRendersNormalizedFindingsToPng),
    ("hash utilities compute text and file", HashUtilitiesComputeTextAndFile),
    ("temp file guard restricts deletion roots", TempFileGuardRestrictsDeletionRoots),
    ("clipboard dispatch prioritizes image file and url", ClipboardDispatchPrioritizesImageFileAndUrl),
    ("clipboard dispatch folders and url rules", ClipboardDispatchFoldersAndUrlRules),
    ("post upload planner handles clipboard and open tasks", PostUploadPlannerHandlesClipboardAndOpenTasks),
    ("post upload planner handles capture editor and discord", PostUploadPlannerHandlesCaptureEditorAndDiscord),
    ("post upload executor routes actions", PostUploadExecutorRoutesActions),
    ("upload history actions prefer shortened urls", UploadHistoryActionsPreferShortenedUrls),
    ("upload history actions identify editable images", UploadHistoryActionsIdentifyEditableImages),
    ("zipline endpoint normalizes", ZiplineEndpointNormalizes),
    ("zipline response parsing", ZiplineResponseParsing),
    ("zipline filename sanitization", ZiplineFilenameSanitization),
    ("zipline validation status classification", ZiplineValidationStatusClassification),
    ("s3 key and url helpers", S3KeyAndUrlHelpers),
    ("s3 canonical query and signing", S3CanonicalQueryAndSigning),
    ("url shortener helpers", UrlShortenerHelpers),
    ("url rewrite helper", UrlRewriteHelper),
    ("cloudflare allowlist helpers", CloudflareAllowlistHelpers),
    ("cloudflare allowlist client updates list", CloudflareAllowlistClientUpdatesList),
    ("upload payload preparer materializes text", UploadPayloadPreparerMaterializesText),
    ("upload payload preparer downloads remote url", UploadPayloadPreparerDownloadsRemoteUrl),
    ("upload payload preparer rejects unsafe remote responses", UploadPayloadPreparerRejectsUnsafeRemoteResponses),
    ("upload payload preparer creates folder index", UploadPayloadPreparerCreatesFolderIndex),
    ("upload payload preparer creates folder batch", UploadPayloadPreparerCreatesFolderBatch),
    ("upload workflow uploads clipboard text", UploadWorkflowUploadsClipboardText),
    ("upload workflow copies and shortens urls", UploadWorkflowCopiesAndShortensUrls),
    ("upload workflow rewrites uploaded urls", UploadWorkflowRewritesUploadedUrls),
    ("upload workflow uploads folder batch", UploadWorkflowUploadsFolderBatch),
    ("upload workflow routes by content kind and extension", UploadWorkflowRoutesByContentKindAndExtension),
    ("upload workflow preserves routed secondary mirror", UploadWorkflowPreservesRoutedSecondaryMirror),
    ("upload workflow uploads manual commands", UploadWorkflowUploadsManualCommands),
    ("upload workflow blocks image when redaction required", UploadWorkflowBlocksImageWhenRedactionRequired),
    ("upload workflow auto redacts image", UploadWorkflowAutoRedactsImage),
    ("upload workflow preprocesses image after redaction", UploadWorkflowPreprocessesImageAfterRedaction),
    ("upload filename generator patterns", UploadFilenameGeneratorPatterns),
    ("upload workflow applies generated remote filenames", UploadWorkflowAppliesGeneratedRemoteFilenames),
    ("upload workflow uploads expiring manual file", UploadWorkflowUploadsExpiringManualFile),
    ("upload workflow uploads managed editor save", UploadWorkflowUploadsManagedEditorSave),
    ("upload workflow reuploads existing record in place", UploadWorkflowReuploadsExistingRecordInPlace),
    ("upload workflow redacts reupload", UploadWorkflowRedactsReupload),
    ("upload workflow blocks reupload when redaction required", UploadWorkflowBlocksReuploadWhenRedactionRequired),
    ("ocr indexing updates image upload records", OcrIndexingUpdatesImageUploadRecords),
    ("ocr admin status and clear commands", OcrAdminStatusAndClearCommands),
    ("zipline client uploads and validates", ZiplineClientUploadsAndValidates),
    ("s3 client uploads and probes", S3ClientUploadsAndProbes),
    ("shortener client uses transport", ShortenerClientUsesTransport),
    ("upload orchestrator records primary and mirror", UploadOrchestratorRecordsPrimaryAndMirror)
};

var failed = 0;
foreach (var test in tests)
{
    try
    {
        await test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failed++;
        Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

if (failed > 0)
{
    return failed;
}

Console.WriteLine($"All {tests.Length} tests passed.");
return 0;

static async Task ProfileExportsRedactSecrets()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var secrets = new MemorySecretStore();
    var store = new JsonProfileStore(paths, secrets);
    var profile = NewZiplineProfile("primary");

    await store.ReplaceProfilesAsync([profile], profile.Id);
    store.SaveSecrets(profile.Id, new ProfileSecrets(ZiplineApiKey: "zipline-secret-token"));

    var exportJson = await store.ExportJsonAsync();
    AssertContains(exportJson, "\"exportedAt\":");
    AssertContains(exportJson, "\"apiKey\": null");
    AssertDoesNotContain(exportJson, "zipline-secret-token");

    var profileJson = await File.ReadAllTextAsync(paths.ProfilesPath);
    AssertDoesNotContain(profileJson, "zipline-secret-token");
}

static async Task ProfileImportSecretsIsOptIn()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var secrets = new MemorySecretStore();
    var store = new JsonProfileStore(paths, secrets);
    var profile = NewZiplineProfile("imported");
    var bundle = Bundle(profile, apiKey: "imported-token");

    await store.ImportAsync(bundle, importSecrets: false);
    AssertEqual(null, store.GetSecrets(profile.Id).ZiplineApiKey);

    await store.ImportAsync(bundle, importSecrets: true);
    AssertEqual("imported-token", store.GetSecrets(profile.Id).ZiplineApiKey);
}

static async Task ProfileImportCanMerge()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var store = new JsonProfileStore(paths, new MemorySecretStore());
    var existing = NewZiplineProfile("existing");
    var imported = NewZiplineProfile("imported");

    await store.ReplaceProfilesAsync([existing], existing.Id);
    await store.ImportAsync(Bundle(imported), importSecrets: false, replaceExisting: false);

    AssertEqual(2, store.Profiles.Count);
    AssertEqual("imported", store.ActiveProfile.Id);
}

static async Task ProfileBackupRestoresCorruptPrimary()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var secrets = new MemorySecretStore();
    var store = new JsonProfileStore(paths, secrets);
    var profile = NewZiplineProfile("backup");

    await store.ReplaceProfilesAsync([profile], profile.Id);
    store.SaveSecrets(profile.Id, new ProfileSecrets(ZiplineApiKey: "backup-secret"));

    var backupJson = await File.ReadAllTextAsync(paths.ProfileBackupPath);
    AssertContains(backupJson, "backup");
    AssertDoesNotContain(backupJson, "backup-secret");
    await File.WriteAllTextAsync(paths.ProfilesPath, "not json");

    var restored = new JsonProfileStore(paths, secrets);
    await restored.LoadAsync();

    AssertEqual("backup", restored.ActiveProfile.Id);
    AssertEqual(1, restored.Profiles.Count);
    AssertEqual("backup-secret", restored.GetSecrets(profile.Id).ZiplineApiKey);
    var rewritten = await File.ReadAllTextAsync(paths.ProfilesPath);
    AssertContains(rewritten, "\"activeProfileId\": \"backup\"");
}

static async Task ProfileLoadMigratesLegacyShapes()
{
    var rawPaths = new TestStoragePaths(NewTempRoot());
    Directory.CreateDirectory(rawPaths.RoamingRoot);
    await File.WriteAllTextAsync(rawPaths.ProfilesPath, """[{ "id": "legacy", "name": "Legacy", "endpoint": "https://legacy.example.com", "backend": "imgur" }]""");
    var rawStore = new JsonProfileStore(rawPaths, new MemorySecretStore());

    await rawStore.LoadAsync();

    AssertEqual("legacy", rawStore.ActiveProfile.Id);
    AssertEqual(UploadBackend.ZiplineV4, rawStore.ActiveProfile.Backend);
    AssertEqual(true, File.Exists(rawPaths.ProfileBackupPath));

    var singlePaths = new TestStoragePaths(NewTempRoot());
    var secrets = new MemorySecretStore();
    Directory.CreateDirectory(singlePaths.RoamingRoot);
    await File.WriteAllTextAsync(singlePaths.ProfilesPath, """{ "upload_endpoint": "https://old.example.com", "upload_api_key": "legacy-secret" }""");
    var singleStore = new JsonProfileStore(singlePaths, secrets);

    await singleStore.LoadAsync();

    AssertEqual("migrated", singleStore.ActiveProfile.Id);
    AssertEqual("Migrated", singleStore.ActiveProfile.Name);
    AssertEqual("https://old.example.com", singleStore.ActiveProfile.Endpoint);
    AssertEqual("legacy-secret", singleStore.GetSecrets("migrated").ZiplineApiKey);
    var primaryJson = await File.ReadAllTextAsync(singlePaths.ProfilesPath);
    var backupJson = await File.ReadAllTextAsync(singlePaths.ProfileBackupPath);
    AssertDoesNotContain(primaryJson, "legacy-secret");
    AssertDoesNotContain(backupJson, "legacy-secret");
}

static async Task ProfileActiveFallbackIsUnconfigured()
{
    var store = new JsonProfileStore(new TestStoragePaths(NewTempRoot()), new MemorySecretStore());
    await store.LoadAsync();
    AssertEqual(UploadProfile.Unconfigured, store.ActiveProfile);
}

static async Task ProfileConfiguredDetection()
{
    var store = new JsonProfileStore(new TestStoragePaths(NewTempRoot()), new MemorySecretStore());
    await store.LoadAsync();
    AssertEqual(false, store.HasConfiguredProfiles());

    var profile = NewZiplineProfile("configured");
    await store.ReplaceProfilesAsync([profile], profile.Id);
    AssertEqual(true, store.HasConfiguredProfiles());
}
static async Task HistoryUpsertDeleteRoundtrips()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var store = new JsonUploadHistoryStore(paths);
    var record = NewRecord("record-1") with { Status = UploadStatus.Uploading };

    await store.UpsertAsync(record);
    await store.UpsertAsync(record with { Status = UploadStatus.Uploaded, RemoteUrl = "https://example.test/capture.png" });

    var reloaded = new JsonUploadHistoryStore(paths);
    await reloaded.LoadAsync();
    AssertEqual(1, reloaded.Records.Count);
    AssertEqual(UploadStatus.Uploaded, reloaded.Records[0].Status);
    AssertEqual("https://example.test/capture.png", reloaded.Records[0].RemoteUrl);

    await reloaded.DeleteAsync("record-1");
    await reloaded.LoadAsync();
    AssertEqual(0, reloaded.Records.Count);
}

static async Task HistoryLoadsRawRecordArrays()
{
    var paths = new TestStoragePaths(NewTempRoot());
    Directory.CreateDirectory(Path.GetDirectoryName(paths.HistoryPath)!);
    await File.WriteAllTextAsync(paths.HistoryPath, JsonSerializer.Serialize(new[] { NewRecord("raw-1") }, JsonOptions.Default));

    var store = new JsonUploadHistoryStore(paths);
    await store.LoadAsync();

    AssertEqual(1, store.Records.Count);
    AssertEqual("raw-1", store.Records[0].Id);
}

static async Task RuntimePreferencesDefaultAndSave()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var store = new RuntimePreferencesStore(paths);

    await store.LoadAsync();
    AssertEqual(UploadRedactionPolicy.AskBeforeUpload, store.Current.RedactionPolicy);
    AssertEqual(true, store.Current.CopyUrlAfterUpload);
    AssertEqual(false, store.Current.OpenUrlAfterUpload);
    AssertEqual(true, store.Current.EnableOcrIndexing);
    AssertEqual(SmartRedactionRenderMode.Pixelate, store.Current.SmartRedactionRenderMode);
    AssertEqual(true, store.Current.ShowNotificationAfterUpload);
    AssertEqual(false, store.Current.CaptureIncludeCursor);
    AssertEqual(0, store.Current.CaptureDelaySeconds);
    AssertEqual(false, store.Current.CaptureFixedRegionEnabled);
    AssertEqual(1280, store.Current.CaptureFixedRegionWidth);
    AssertEqual(720, store.Current.CaptureFixedRegionHeight);
    AssertEqual(true, store.Current.CaptureShowInfoOverlay);
    AssertEqual(0, store.Current.CaptureSnapSizes?.Count ?? 0);
    AssertEqual(false, store.Current.CaptureMirrorToScreenshotsFolder);
    AssertEqual(string.Empty, store.Current.CaptureScreenshotsFolder);
    AssertEqual("7", store.Current.HotKeys!.UploadClipboard.Key);
    AssertEqual(false, store.Current.CloudflareAllowlist!.Enabled);
    AssertEqual(15, store.Current.CloudflareAllowlist.CheckIntervalMinutes);
    AssertEqual(false, store.Current.UrlRegexReplaceEnabled);
    AssertEqual(string.Empty, store.Current.UrlRegexPattern);
    AssertEqual(string.Empty, store.Current.UrlRegexReplacement);
    AssertEqual(false, store.Current.AfterCaptureCopyImageAndUrl);
    AssertEqual(true, store.Current.AfterCaptureCopyUrl);
    AssertEqual(86400, store.Current.DefaultFileExpirySeconds);
    AssertEqual(false, store.Current.StripImageMetadataBeforeUpload);
    AssertEqual(ImageUploadFormat.Png, store.Current.ImageUploadFormat);
    AssertEqual(false, store.Current.FileUploadUseNamePattern);
    AssertEqual(false, store.Current.FileUploadUseRandom16Name);
    AssertEqual("{date}-{rand}", store.Current.FileNamePattern);
    AssertEqual(1, store.Current.FileNameAutoIncrement);
    AssertEqual(true, store.Current.FileUploadReplaceProblematicCharacters);
    AssertEqual(true, store.Current.SmartRedactionDetectors!.Face);
    AssertEqual(true, store.Current.SmartRedactionDetectors.Barcode);
    AssertNear(0.20, store.Current.SmartRedactionDetectors.MinimumConfidence, 0.0001);
    AssertEqual(false, store.Current.ClipboardRules!.ShortenUrl);
    AssertEqual(true, store.Current.ClipboardRules.UploadUrlContents);
    AssertEqual(false, store.Current.ClipboardRules.ShareUrlAfterUpload);
    AssertEqual(false, store.Current.ClipboardRules.UploadTextContents);
    AssertEqual(false, store.Current.ClipboardRules.AutoIndexFolder);

    var screenshotsFolder = Path.Combine(paths.RoamingRoot, "..", "Shots");
    var updated = store.Current with { RedactionPolicy = UploadRedactionPolicy.AutoRedact, ActivePaletteId = "oledBlack", ShortenerProvider = "customGetTemplate", ShortenerCustomGetTemplate = "https://short.example/create?url={url}", UrlRegexReplaceEnabled = true, UrlRegexPattern = " https://origin.example/(.*) ", UrlRegexReplacement = " https://cdn.example/$1 ", SmartRedactionRenderMode = SmartRedactionRenderMode.BlackBox, ShowNotificationAfterUpload = false, CaptureIncludeCursor = true, CaptureDelaySeconds = 99, CaptureFixedRegionEnabled = true, CaptureFixedRegionX = -25, CaptureFixedRegionY = 40, CaptureFixedRegionWidth = 0, CaptureFixedRegionHeight = -8, CaptureShowInfoOverlay = false, CaptureSnapSizes = [new CaptureSnapSize(640, 480), new CaptureSnapSize(0, 0), new CaptureSnapSize(640, 480), new CaptureSnapSize(1280, 720)], CaptureMirrorToScreenshotsFolder = true, CaptureScreenshotsFolder = screenshotsFolder, UploaderFilters = [new UploaderFilterRule("", [" .PNG ", "png", "", ".gif"], " routed "), new UploaderFilterRule("drop", [], "profile")], DestinationRouting = new DestinationRoutingConfig(ImageProfileId: " image ", FileProfileId: " ", TextProfileId: "text"), CloudflareAllowlist = new CloudflareAllowlistConfig(true, " acct ", " list ", " ", 9999), ClipboardRules = new ClipboardUploadRules(ShortenUrl: true, UploadUrlContents: false, ShareUrlAfterUpload: true, UploadTextContents: true, AutoIndexFolder: true), AfterCaptureCopyImageAndUrl = true, AfterCaptureCopyUrl = false, DefaultFileExpirySeconds = 9999999, StripImageMetadataBeforeUpload = true, ImageUploadFormat = ImageUploadFormat.Jpeg, FileUploadUseNamePattern = true, FileUploadUseRandom16Name = false, FileNamePattern = " {date}_{name}_{inc}_{rand} ", FileNameAutoIncrement = 0, FileUploadReplaceProblematicCharacters = false, OnboardingState = OnboardingState.Completed, SmartRedactionDetectors = new SmartRedactionDetectorPreferences(Face: false, Barcode: true, MinimumConfidence: 2.0) };
    await store.SaveAsync(updated);

    var reloaded = new RuntimePreferencesStore(paths);
    await reloaded.LoadAsync();
    AssertEqual(UploadRedactionPolicy.AutoRedact, reloaded.Current.RedactionPolicy);
    AssertEqual("oledBlack", reloaded.Current.ActivePaletteId);
    AssertEqual("customGetTemplate", reloaded.Current.ShortenerProvider);
    AssertEqual("https://short.example/create?url={url}", reloaded.Current.ShortenerCustomGetTemplate);
    AssertEqual(true, reloaded.Current.UrlRegexReplaceEnabled);
    AssertEqual(" https://origin.example/(.*) ", reloaded.Current.UrlRegexPattern);
    AssertEqual(" https://cdn.example/$1 ", reloaded.Current.UrlRegexReplacement);
    AssertEqual(SmartRedactionRenderMode.BlackBox, reloaded.Current.SmartRedactionRenderMode);
    AssertEqual(false, reloaded.Current.ShowNotificationAfterUpload);
    AssertEqual(true, reloaded.Current.CaptureIncludeCursor);
    AssertEqual(5, reloaded.Current.CaptureDelaySeconds);
    AssertEqual(true, reloaded.Current.CaptureFixedRegionEnabled);
    AssertEqual(-25, reloaded.Current.CaptureFixedRegionX);
    AssertEqual(40, reloaded.Current.CaptureFixedRegionY);
    AssertEqual(1, reloaded.Current.CaptureFixedRegionWidth);
    AssertEqual(1, reloaded.Current.CaptureFixedRegionHeight);
    AssertEqual(false, reloaded.Current.CaptureShowInfoOverlay);
    AssertEqual(2, reloaded.Current.CaptureSnapSizes?.Count ?? 0);
    AssertEqual(640, reloaded.Current.CaptureSnapSizes![0].Width);
    AssertEqual(720, reloaded.Current.CaptureSnapSizes[1].Height);
    AssertEqual(true, reloaded.Current.CaptureMirrorToScreenshotsFolder);
    AssertEqual(AppStoragePaths.NormalizeUserDirectory(screenshotsFolder), reloaded.Current.CaptureScreenshotsFolder);
    AssertEqual(1, reloaded.Current.UploaderFilters?.Count ?? 0);
    AssertEqual("png", reloaded.Current.UploaderFilters![0].Extensions[0]);
    AssertEqual("gif", reloaded.Current.UploaderFilters[0].Extensions[1]);
    AssertEqual("routed", reloaded.Current.UploaderFilters[0].ProfileId);
    AssertEqual("image", reloaded.Current.DestinationRouting?.ImageProfileId);
    AssertEqual(null, reloaded.Current.DestinationRouting?.FileProfileId);
    AssertEqual("text", reloaded.Current.DestinationRouting?.TextProfileId);
    AssertEqual(true, reloaded.Current.CloudflareAllowlist?.Enabled);
    AssertEqual("acct", reloaded.Current.CloudflareAllowlist?.AccountId);
    AssertEqual("list", reloaded.Current.CloudflareAllowlist?.ListId);
    AssertEqual(false, string.IsNullOrWhiteSpace(reloaded.Current.CloudflareAllowlist?.DeviceName));
    AssertEqual(1440, reloaded.Current.CloudflareAllowlist?.CheckIntervalMinutes);
    AssertEqual(true, reloaded.Current.ClipboardRules?.ShortenUrl);
    AssertEqual(false, reloaded.Current.ClipboardRules?.UploadUrlContents);
    AssertEqual(true, reloaded.Current.ClipboardRules?.ShareUrlAfterUpload);
    AssertEqual(true, reloaded.Current.ClipboardRules?.UploadTextContents);
    AssertEqual(true, reloaded.Current.ClipboardRules?.AutoIndexFolder);
    AssertEqual(true, reloaded.Current.AfterCaptureCopyImageAndUrl);
    AssertEqual(false, reloaded.Current.AfterCaptureCopyUrl);
    AssertEqual(432000, reloaded.Current.DefaultFileExpirySeconds);
    AssertEqual(true, reloaded.Current.StripImageMetadataBeforeUpload);
    AssertEqual(ImageUploadFormat.Jpeg, reloaded.Current.ImageUploadFormat);
    AssertEqual(true, reloaded.Current.FileUploadUseNamePattern);
    AssertEqual(false, reloaded.Current.FileUploadUseRandom16Name);
    AssertEqual("{date}_{name}_{inc}_{rand}", reloaded.Current.FileNamePattern);
    AssertEqual(1, reloaded.Current.FileNameAutoIncrement);
    AssertEqual(false, reloaded.Current.FileUploadReplaceProblematicCharacters);
    AssertEqual(OnboardingState.Completed, reloaded.Current.OnboardingState);
    AssertEqual(false, reloaded.Current.SmartRedactionDetectors!.Face);
    AssertEqual(true, reloaded.Current.SmartRedactionDetectors.Barcode);
    AssertNear(1.0, reloaded.Current.SmartRedactionDetectors.MinimumConfidence, 0.0001);

    await reloaded.SaveAsync(reloaded.Current with { ShortenerProvider = "unknown" });
    AssertEqual("tinyURL", reloaded.Current.ShortenerProvider);
}


static async Task UiPaletteCatalogAndRuntimeRoundtrip()
{
    AssertEqual(7, UiPaletteCatalog.Presets.Count);
    AssertEqual("classic", UiPaletteCatalog.NormalizeId("missing"));
    AssertEqual("custom", UiPaletteCatalog.NormalizeId("CUSTOM"));
    AssertEqual("#1A73F2FF", UiPaletteCatalog.DefaultCustomSeed().WindowGradientA.ToHexRgba());
    AssertEqual(true, RgbaColor.TryParseHex("#33669980", out var parsed));
    AssertEqual("#33669980", parsed.ToHexRgba());

    var custom = UiPaletteCatalog.DefaultCustomSeed() with
    {
        WindowGradientA = new RgbaColor(-2, 2, double.NaN, double.NaN),
        CaptureAccent = parsed
    };
    var resolved = UiPaletteCatalog.Resolve("custom", custom);
    AssertEqual("Custom", resolved.DisplayName);
    AssertEqual("#00FF00FF", resolved.Data.WindowGradientA.ToHexRgba());
    AssertEqual("#33669980", resolved.Data.CaptureAccent.ToHexRgba());

    var paths = new TestStoragePaths(NewTempRoot());
    var store = new RuntimePreferencesStore(paths);
    await store.SaveAsync(RuntimePreferencesStore.Defaults with { ActivePaletteId = "unknown", CustomPalette = custom });
    AssertEqual("classic", store.Current.ActivePaletteId);
    AssertEqual("#33669980", store.Current.CustomPalette!.CaptureAccent.ToHexRgba());

    await store.SaveAsync(store.Current with { ActivePaletteId = "custom" });
    var reloaded = new RuntimePreferencesStore(paths);
    await reloaded.LoadAsync();
    AssertEqual("custom", reloaded.Current.ActivePaletteId);
    AssertEqual("#33669980", reloaded.Current.CustomPalette!.CaptureAccent.ToHexRgba());
    AssertEqual("Custom", UiPaletteCatalog.Resolve(reloaded.Current.ActivePaletteId, reloaded.Current.CustomPalette).DisplayName);
}
static async Task RuntimePreferencesLoadLegacyDefaults()
{
    var paths = new TestStoragePaths(NewTempRoot());
    Directory.CreateDirectory(paths.RoamingRoot);
    await File.WriteAllTextAsync(Path.Combine(paths.RoamingRoot, "runtime-preferences.json"), """
{
  "redactionPolicy": "askBeforeUpload",
  "copyUrlAfterUpload": true,
  "copyImageAfterUpload": false,
  "openUrlAfterUpload": false,
  "openEditorAfterCapture": false,
  "enableOcrIndexing": true,
  "activePaletteId": "classic",
  "shortenerProvider": "tinyURL",
  "shortenerCustomGetTemplate": ""
}
""");

    var store = new RuntimePreferencesStore(paths);
    await store.LoadAsync();

    AssertEqual(SmartRedactionRenderMode.Pixelate, store.Current.SmartRedactionRenderMode);
    AssertEqual(true, store.Current.ShowNotificationAfterUpload);
    AssertEqual(false, store.Current.CaptureIncludeCursor);
    AssertEqual(0, store.Current.CaptureDelaySeconds);
    AssertEqual(false, store.Current.CaptureFixedRegionEnabled);
    AssertEqual(1280, store.Current.CaptureFixedRegionWidth);
    AssertEqual(720, store.Current.CaptureFixedRegionHeight);
    AssertEqual(true, store.Current.CaptureShowInfoOverlay);
    AssertEqual(0, store.Current.CaptureSnapSizes?.Count ?? 0);
    AssertEqual(false, store.Current.CaptureMirrorToScreenshotsFolder);
    AssertEqual(string.Empty, store.Current.CaptureScreenshotsFolder);
    AssertEqual("7", store.Current.HotKeys!.UploadClipboard.Key);
    AssertEqual(false, store.Current.CloudflareAllowlist!.Enabled);
    AssertEqual(15, store.Current.CloudflareAllowlist.CheckIntervalMinutes);
    AssertEqual(false, store.Current.UrlRegexReplaceEnabled);
    AssertEqual(string.Empty, store.Current.UrlRegexPattern);
    AssertEqual(string.Empty, store.Current.UrlRegexReplacement);
    AssertEqual(false, store.Current.AfterCaptureCopyImageAndUrl);
    AssertEqual(true, store.Current.AfterCaptureCopyUrl);
    AssertEqual(86400, store.Current.DefaultFileExpirySeconds);
    AssertEqual(false, store.Current.StripImageMetadataBeforeUpload);
    AssertEqual(ImageUploadFormat.Png, store.Current.ImageUploadFormat);
    AssertEqual(false, store.Current.FileUploadUseNamePattern);
    AssertEqual(false, store.Current.FileUploadUseRandom16Name);
    AssertEqual("{date}-{rand}", store.Current.FileNamePattern);
    AssertEqual(1, store.Current.FileNameAutoIncrement);
    AssertEqual(true, store.Current.FileUploadReplaceProblematicCharacters);
    AssertEqual(true, store.Current.ClipboardRules?.UploadUrlContents);
}

static Task CaptureSnapSizeParsingAndGeometry()
{
    var sizes = CaptureSnapSize.ParseList("320x240, 640 x 480; nope\\n640x480, 0x9, 1280x720");
    AssertEqual(3, sizes.Count);
    AssertEqual("320x240, 640x480, 1280x720", CaptureSnapSize.FormatList(sizes));

    var free = CaptureRegionGeometry.ApplySnap(new System.Drawing.Point(100, 100), new System.Drawing.Point(240, 190), new System.Drawing.Size(800, 600), sizes, snapEnabled: false);
    AssertEqual(140, free.Width);
    AssertEqual(90, free.Height);

    var snapped = CaptureRegionGeometry.ApplySnap(new System.Drawing.Point(100, 100), new System.Drawing.Point(610, 470), new System.Drawing.Size(800, 600), sizes, snapEnabled: true);
    AssertEqual(640, snapped.Width);
    AssertEqual(480, snapped.Height);
    AssertEqual(100, snapped.Left);
    AssertEqual(100, snapped.Top);

    var reversed = CaptureRegionGeometry.ApplySnap(new System.Drawing.Point(700, 500), new System.Drawing.Point(580, 400), new System.Drawing.Size(800, 600), [new CaptureSnapSize(320, 240)], snapEnabled: true);
    AssertEqual(380, reversed.Left);
    AssertEqual(260, reversed.Top);
    AssertEqual(320, reversed.Width);
    AssertEqual(240, reversed.Height);
    return Task.CompletedTask;
}

static Task LocalMirrorFilenameHelpers()
{
    AssertEqual("visual-studio-code", LocalMirrorFilename.NormalizedPrefix(" Visual Studio Code "));
    AssertEqual("region", LocalMirrorFilename.NormalizedPrefix("region"));
    AssertEqual(null, LocalMirrorFilename.NormalizedPrefix(" -- "));
    AssertEqual("visual-studio-code-abcdef12.png", LocalMirrorFilename.BuildFilename("C:\\tmp\\image.PNG", "Visual Studio Code", "region", "abcdef123456"));
    AssertEqual("region-abcdef12.jpg", LocalMirrorFilename.BuildFilename("C:\\tmp\\image.JPG", " -- ", "region", "abcdef123456"));
    AssertEqual("abcdef12.png", LocalMirrorFilename.BuildFilename("C:\\tmp\\image", null, "region", "abcdef123456"));
    return Task.CompletedTask;
}
static Task EditorToolCatalogIncludesTextVariants()
{
    AssertEqual(true, EditorToolCatalog.ParityTools.Contains(EditorTool.Text));
    AssertEqual(true, EditorToolCatalog.ParityTools.Contains(EditorTool.TextOutline));
    AssertEqual(true, EditorToolCatalog.ParityTools.Contains(EditorTool.TextBackground));
    AssertEqual(true, EditorToolCatalog.ParityTools.Contains(EditorTool.SpeechBalloon));
    return Task.CompletedTask;
}
static async Task HotKeyPreferencesNormalize()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var store = new RuntimePreferencesStore(paths);
    await store.LoadAsync();

    var defaults = store.Current.HotKeys ?? throw new InvalidOperationException("Missing hotkey defaults.");
    AssertEqual("G", defaults.CaptureRegionUpload.Key);
    AssertEqual(true, defaults.CaptureRegionUpload.Control);
    AssertEqual("7", defaults.UploadClipboard.Key);
    AssertEqual(true, defaults.UploadClipboard.Control);
    AssertEqual(true, defaults.UploadClipboard.Shift);

    await store.SaveAsync(store.Current with
    {
        HotKeys = new HotKeyBindings(
            new HotKeyShortcut("?"),
            new HotKeyShortcut("z", Shift: true),
            new HotKeyShortcut("p"),
            new HotKeyShortcut("9", Alt: true))
    });

    AssertEqual("G", store.Current.HotKeys!.CaptureRegionUpload.Key);
    AssertEqual(true, store.Current.HotKeys.CaptureRegionUpload.Control);
    AssertEqual("Z", store.Current.HotKeys.CaptureRegionUploadExpiring.Key);
    AssertEqual(true, store.Current.HotKeys.CaptureRegionUploadExpiring.Shift);
    AssertEqual("P", store.Current.HotKeys.CaptureRegionUploadFrozen.Key);
    AssertEqual(true, store.Current.HotKeys.CaptureRegionUploadFrozen.Control);
    AssertEqual("9", store.Current.HotKeys.UploadClipboard.Key);
    AssertEqual(true, store.Current.HotKeys.UploadClipboard.Alt);
}
static async Task WatchFolderPreferencesSaveAndNormalize()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var store = new RuntimePreferencesStore(paths);
    await store.LoadAsync();

    AssertEqual(false, store.Current.WatchFoldersEnabled);
    AssertEqual(0, store.Current.WatchFolderRules?.Count ?? 0);

    await store.SaveAsync(store.Current with
    {
        WatchFoldersEnabled = true,
        WatchFolderRules =
        [
            new WatchFolderRule("", "  ", FileFilter: "", ExpirySeconds: -3),
            new WatchFolderRule("rule-1", " C:\\Watch ", FileFilter: "  ", ExpirySeconds: 0),
            new WatchFolderRule("rule-2", "D:\\Media", FileFilter: " png, jpg ", Mode: WatchFolderMode.ImageOnly, ExpirySeconds: 120)
        ]
    });

    var reloaded = new RuntimePreferencesStore(paths);
    await reloaded.LoadAsync();

    AssertEqual(true, reloaded.Current.WatchFoldersEnabled);
    AssertEqual(2, reloaded.Current.WatchFolderRules?.Count ?? 0);
    AssertEqual("C:\\Watch", reloaded.Current.WatchFolderRules![0].Path);
    AssertEqual("*", reloaded.Current.WatchFolderRules[0].FileFilter);
    AssertEqual(null, reloaded.Current.WatchFolderRules[0].ExpirySeconds);
    AssertEqual("png, jpg", reloaded.Current.WatchFolderRules[1].FileFilter);
    AssertEqual(WatchFolderMode.ImageOnly, reloaded.Current.WatchFolderRules[1].Mode);
    AssertEqual(120, reloaded.Current.WatchFolderRules[1].ExpirySeconds);
}

static Task WatchFolderScannerFiltersAndEnumeration()
{
    AssertEqual(true, WatchFolderScanner.MatchesFilter("a.png", "*"));
    AssertEqual(true, WatchFolderScanner.MatchesFilter("a.png", "*.*"));
    AssertEqual(true, WatchFolderScanner.MatchesFilter("a.JPG", "png, jpg; mp4"));
    AssertEqual(false, WatchFolderScanner.MatchesFilter("a.gif", "png, jpg; mp4"));

    var root = NewTempRoot();
    var visible = Path.Combine(root, "visible.png");
    var nestedDir = Path.Combine(root, "nested");
    Directory.CreateDirectory(nestedDir);
    var nested = Path.Combine(nestedDir, "clip.jpg");
    var dotHidden = Path.Combine(root, ".secret.png");
    var temp = Path.Combine(root, "upload.tmp");
    File.WriteAllText(visible, "a");
    File.WriteAllText(nested, "b");
    File.WriteAllText(dotHidden, "c");
    File.WriteAllText(temp, "d");

    var nonRecursive = WatchFolderScanner.EnumerateCandidateFiles(root, includeSubdirectories: false, "png,jpg");
    AssertEqual(1, nonRecursive.Count);
    AssertEqual(Path.GetFullPath(visible), nonRecursive[0]);

    var recursive = WatchFolderScanner.EnumerateCandidateFiles(root, includeSubdirectories: true, "png,jpg");
    AssertEqual(2, recursive.Count);
    AssertEqual(true, recursive.Contains(Path.GetFullPath(nested)));
    AssertEqual(false, recursive.Contains(Path.GetFullPath(dotHidden)));
    AssertEqual(false, recursive.Contains(Path.GetFullPath(temp)));
    return Task.CompletedTask;
}

static Task WatchFolderScannerBaselineStabilityAndDedupe()
{
    var root = NewTempRoot();
    var existing = Path.Combine(root, "existing.txt");
    File.WriteAllText(existing, "old");
    var scanner = new WatchFolderScanner();
    var rule = new WatchFolderRule("rule-1", root, IncludeSubdirectories: true, FileFilter: "*", Mode: WatchFolderMode.Auto);
    var t0 = DateTimeOffset.Parse("2026-07-07T12:00:00Z");

    AssertEqual(0, scanner.Scan([rule], t0).Count);
    var fresh = Path.Combine(root, "fresh.txt");
    File.WriteAllText(fresh, "new");
    File.SetLastWriteTimeUtc(fresh, DateTime.Parse("2026-07-07T12:00:02Z").ToUniversalTime());

    AssertEqual(0, scanner.Scan([rule], t0.AddSeconds(2)).Count);
    var ready = scanner.Scan([rule], t0.AddSeconds(4));
    AssertEqual(1, ready.Count);
    AssertEqual(Path.GetFullPath(fresh), ready[0].FilePath);
    AssertEqual(false, ready[0].IsImage);
    AssertEqual(0, scanner.Scan([rule], t0.AddSeconds(6)).Count);

    File.AppendAllText(fresh, " changed");
    File.SetLastWriteTimeUtc(fresh, DateTime.Parse("2026-07-07T12:00:08Z").ToUniversalTime());
    AssertEqual(0, scanner.Scan([rule], t0.AddSeconds(8)).Count);
    AssertEqual(1, scanner.Scan([rule], t0.AddSeconds(10)).Count);
    return Task.CompletedTask;
}

static Task SmartRedactionClassifierFindsSensitivePatterns()
{
    var classifier = new SmartRedactionPatternClassifier();
    var settings = RedactionDetectorSettings.Default with { Ipv6Address = true, MacAddress = true, FilePath = true, UsernameOrHostname = true };
    var cases = new (string Text, RedactionDetectorType Type)[]
    {
        ("Email me at dev@example.com", RedactionDetectorType.Email),
        ("Open https://example.com/private?token=abc", RedactionDetectorType.UrlOrDomain),
        ("Internal site is app.example.dev", RedactionDetectorType.UrlOrDomain),
        ("Server is 192.168.1.44", RedactionDetectorType.Ipv4Address),
        ("IPv6 is 2001:0db8:85a3:0000:0000:8a2e:0370:7334", RedactionDetectorType.Ipv6Address),
        ("Wi-Fi MAC 00:1A:2B:3C:4D:5E", RedactionDetectorType.MacAddress),
        ("Call (212) 555-0198 today", RedactionDetectorType.PhoneNumber),
        ("Card 4111 1111 1111 1111", RedactionDetectorType.CreditCard),
        ("AWS key AKIAIOSFODNN7EXAMPLE", RedactionDetectorType.AwsAccessKey),
        ("GitHub token ghp_abcdefghijklmnopqrstuvwxyzABCDE12345", RedactionDetectorType.GitHubToken),
        ("OpenAI key sk-abcdefghijklmnopqrstuvwxyz", RedactionDetectorType.OpenAiKey),
        ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz", RedactionDetectorType.BearerToken),
        ("JWT eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature", RedactionDetectorType.Jwt),
        ("password = hunter2", RedactionDetectorType.PasswordField),
        ("DATABASE_URL=postgres://secret-host", RedactionDetectorType.EnvironmentVariable),
        ("Set-Cookie: sessionid=abcdef1234567890", RedactionDetectorType.SessionCookie),
        ("Path /Users/example/Documents/Secret/file.txt", RedactionDetectorType.FilePath),
        ("hostname = macbook-pro", RedactionDetectorType.UsernameOrHostname)
    };

    foreach (var (candidate, type) in cases)
    {
        AssertEqual(true, classifier.Matches(candidate, settings).Any(match => match.Type == type));
    }

    AssertEqual(0, classifier.Matches("dev@example.com", settings with { TextOcr = false }).Count);
    return Task.CompletedTask;
}

static Task SmartRedactionClassifierFindsPrivateKeyBlocks()
{
    var classifier = new SmartRedactionPatternClassifier();
    var text = """
-----BEGIN PRIVATE KEY-----
abcdefghijklmnopqrstuvwxyz
-----END PRIVATE KEY-----
""";
    AssertEqual(true, classifier.Matches(text).Any(match => match.Type == RedactionDetectorType.PrivateKey));
    return Task.CompletedTask;
}

static Task SmartRedactionClassifierMatchesOcrSpacedEmail()
{
    var classifier = new SmartRedactionPatternClassifier();
    AssertEqual(true, classifier.Matches("rosscran992 @ gmail . com").Any(match => match.Type == RedactionDetectorType.Email));
    return Task.CompletedTask;
}

static Task SmartRedactionClassifierAvoidsCommonNonMatches()
{
    var classifier = new SmartRedactionPatternClassifier();
    var categories = classifier.Matches("Release 2026-06-27 build 123456 with card-ish 4111 1111 1111 1113").Select(match => match.Type).ToArray();
    AssertEqual(false, categories.Contains(RedactionDetectorType.CreditCard));
    AssertEqual(false, categories.Contains(RedactionDetectorType.ApiKey));
    AssertEqual(false, categories.Contains(RedactionDetectorType.PasswordField));
    return Task.CompletedTask;
}

static Task BarcodeRedactionGeometryUsesTopLeftBounds()
{
    var finding = BarcodeRedactionGeometry.FindingFromPoints(
        "secret payload",
        200,
        100,
        [new BarcodePoint(50, 20), new BarcodePoint(150, 20), new BarcodePoint(150, 60), new BarcodePoint(50, 60)]);

    AssertEqual(RedactionDetectorType.Barcode, finding.Type);
    AssertNear(0.21, finding.X, 0.0001);
    AssertNear(0.168, finding.Y, 0.0001);
    AssertNear(0.58, finding.Width, 0.0001);
    AssertNear(0.464, finding.Height, 0.0001);
    AssertEqual(string.Empty, finding.Preview);
    return Task.CompletedTask;
}
static async Task WindowsSmartRedactionDetectorCombinesFaces()
{
    var root = NewTempRoot();
    var path = Path.Combine(root, "face-source.png");
    WriteSolidPng(path, 200, 100);
    var detector = new WindowsSmartRedactionDetector(new FixedFaceDetectionBackend([
        new FaceDetectionBox(50, 20, 40, 30, 0.87)
    ]));

    var findings = await detector.DetectAsync(path, CancellationToken.None);

    AssertEqual(1, findings.Count);
    var face = findings[0];
    AssertEqual(RedactionDetectorType.Face, face.Type);
    AssertNear(0.25, face.X, 0.0001);
    AssertNear(0.20, face.Y, 0.0001);
    AssertNear(0.20, face.Width, 0.0001);
    AssertNear(0.30, face.Height, 0.0001);
    AssertNear(0.87, face.Confidence, 0.0001);
    AssertEqual(string.Empty, face.Preview);
}
static async Task WindowsSmartRedactionDetectorHonorsSettings()
{
    var root = NewTempRoot();
    var path = Path.Combine(root, "face-source.png");
    WriteSolidPng(path, 200, 100);
    var settings = new SmartRedactionDetectorPreferences(Face: true, Barcode: false, MinimumConfidence: 0.5);
    var detector = new WindowsSmartRedactionDetector(
        new FixedFaceDetectionBackend([
            new FaceDetectionBox(50, 20, 40, 30, 0.49),
            new FaceDetectionBox(100, 40, 20, 20, 0.75)
        ]),
        () => settings);

    var findings = await detector.DetectAsync(path, CancellationToken.None);

    AssertEqual(1, findings.Count);
    AssertEqual(RedactionDetectorType.Face, findings[0].Type);
    AssertNear(0.75, findings[0].Confidence, 0.0001);

    settings = settings with { Face = false };
    findings = await detector.DetectAsync(path, CancellationToken.None);
    AssertEqual(0, findings.Count);
}
static Task RedactionRendererAppliesNormalizedFindingsToPixels()
{
    const int width = 10;
    const int height = 10;
    var pixels = Enumerable.Repeat((byte)255, width * height * 4).ToArray();
    var finding = new RedactionFinding(RedactionDetectorType.Barcode, 1, 0.2, 0.3, 0.4, 0.2, string.Empty);

    var bounds = RedactionImageRenderer.PixelBounds(finding, width, height);
    var applied = RedactionImageRenderer.ApplyToBgra32(pixels, width, height, [finding], SmartRedactionRenderMode.BlackBox);

    AssertEqual(1, applied);
    for (var y = 0; y < height; y++)
    {
        for (var x = 0; x < width; x++)
        {
            var offset = ((y * width) + x) * 4;
            var inside = x >= bounds.X && x < bounds.X + bounds.Width && y >= bounds.Y && y < bounds.Y + bounds.Height;
            AssertEqual((byte)(inside ? 0 : 255), pixels[offset]);
            AssertEqual((byte)(inside ? 0 : 255), pixels[offset + 1]);
            AssertEqual((byte)(inside ? 0 : 255), pixels[offset + 2]);
            AssertEqual((byte)255, pixels[offset + 3]);
        }
    }

    return Task.CompletedTask;
}
static async Task UploadRedactionRendersNormalizedFindingsToPng()
{
    const int width = 8;
    const int height = 8;
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var source = Path.Combine(paths.TempRoot, "coordinate-fixture.png");
    WriteTwoTonePng(source, width, height);

    var detector = new FixedSmartRedactionDetector([
        new RedactionFinding(RedactionDetectorType.Barcode, 1, 0, 0.5, 1, 0.5, string.Empty)
    ]);
    var service = new WindowsUploadRedactionService(paths, detector);

    var result = await service.PrepareImageAsync(source, UploadRedactionPolicy.AutoRedact, SmartRedactionRenderMode.BlackBox);

    AssertEqual(UploadRedactionResultKind.Redacted, result.Kind);
    AssertEqual(true, File.Exists(result.FilePath));
    var rendered = LoadPbgraPixels(result.FilePath!, out var renderedWidth, out var renderedHeight);
    AssertEqual(width, renderedWidth);
    AssertEqual(height, renderedHeight);

    for (var y = 0; y < renderedHeight; y++)
    {
        for (var x = 0; x < renderedWidth; x++)
        {
            var offset = ((y * renderedWidth) + x) * 4;
            if (y < height / 2)
            {
                AssertEqual((byte)0, rendered[offset]);
                AssertEqual((byte)0, rendered[offset + 1]);
                AssertEqual((byte)255, rendered[offset + 2]);
                AssertEqual((byte)255, rendered[offset + 3]);
            }
            else
            {
                AssertEqual((byte)0, rendered[offset]);
                AssertEqual((byte)0, rendered[offset + 1]);
                AssertEqual((byte)0, rendered[offset + 2]);
                AssertEqual((byte)255, rendered[offset + 3]);
            }
        }
    }
}

static void WriteTwoTonePng(string path, int width, int height)
{
    var stride = width * 4;
    var pixels = new byte[stride * height];
    for (var y = 0; y < height; y++)
    {
        for (var x = 0; x < width; x++)
        {
            var offset = ((y * width) + x) * 4;
            if (y < height / 2)
            {
                pixels[offset] = 0;
                pixels[offset + 1] = 0;
                pixels[offset + 2] = 255;
                pixels[offset + 3] = 255;
            }
            else
            {
                pixels[offset] = 255;
                pixels[offset + 1] = 0;
                pixels[offset + 2] = 0;
                pixels[offset + 3] = 255;
            }
        }
    }

    var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
    var encoder = new PngBitmapEncoder();
    encoder.Frames.Add(BitmapFrame.Create(bitmap));
    using var stream = File.Create(path);
    encoder.Save(stream);
}

static byte[] LoadPbgraPixels(string path, out int width, out int height)
{
    using var stream = File.OpenRead(path);
    var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
    var frame = decoder.Frames[0];
    BitmapSource source = frame.Format == PixelFormats.Pbgra32
        ? frame
        : new FormatConvertedBitmap(frame, PixelFormats.Pbgra32, null, 0);
    width = source.PixelWidth;
    height = source.PixelHeight;
    var stride = width * 4;
    var pixels = new byte[stride * height];
    source.CopyPixels(pixels, stride, 0);
    return pixels;
}
static Task SmartRedactionLuhnValidation()
{
    AssertEqual(true, SmartRedactionPatternClassifier.IsLikelyCreditCard("4111 1111 1111 1111"));
    AssertEqual(true, SmartRedactionPatternClassifier.IsLikelyCreditCard("5555-5555-5555-4444"));
    AssertEqual(false, SmartRedactionPatternClassifier.IsLikelyCreditCard("4111 1111 1111 1113"));
    AssertEqual(false, SmartRedactionPatternClassifier.IsLikelyCreditCard("123456"));
    return Task.CompletedTask;
}


static async Task HashUtilitiesComputeTextAndFile()
{
    var expected = new HashDigest(
        "5eb63bbbe01eeed093cb22bb8f5acdc3",
        "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed",
        "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9");

    var textDigest = HashUtilities.ComputeText("hello world");
    AssertEqual(expected, textDigest);
    AssertEqual("Matches MD5", textDigest.MatchExpected(expected.Md5.ToUpperInvariant()));
    AssertEqual("Matches SHA-1", textDigest.MatchExpected(expected.Sha1));
    AssertEqual("Matches SHA-256", textDigest.MatchExpected("  " + expected.Sha256 + "  "));
    AssertEqual("No match", textDigest.MatchExpected("abc123"));
    AssertEqual(null, textDigest.MatchExpected("   "));

    var root = NewTempRoot();
    var file = Path.Combine(root, "hello.txt");
    Directory.CreateDirectory(root);
    await File.WriteAllTextAsync(file, "hello world");

    var fileDigest = await HashUtilities.ComputeFileAsync(file);
    AssertEqual(expected, fileDigest);
}
static Task TempFileGuardRestrictsDeletionRoots()
{
    var root = NewTempRoot();
    var paths = new TestStoragePaths(root);
    paths.EnsureCreated();
    var guard = new TempFileGuard(paths);
    var safeTemp = Path.Combine(paths.TempRoot, "redacted.png");
    var safeLocal = Path.Combine(paths.LocalRoot, "Images", "capture.png");
    var outside = Path.Combine(root, "outside", "capture.png");

    AssertEqual(true, guard.IsSafeToDelete(safeTemp));
    AssertEqual(true, guard.IsSafeToDelete(safeLocal));
    AssertEqual(false, guard.IsSafeToDelete(outside));

    var outsideRoot = Path.Combine(root, "outside-target");
    Directory.CreateDirectory(outsideRoot);
    var linkedRoot = Path.Combine(paths.TempRoot, "linked-outside");
    try
    {
        Directory.CreateSymbolicLink(linkedRoot, outsideRoot);
        AssertEqual(false, guard.IsSafeToDelete(Path.Combine(linkedRoot, "capture.png")));
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
    {
        // Some Windows developer-policy and CI environments disallow symlink creation.
    }

    return Task.CompletedTask;
}

static Task ClipboardDispatchPrioritizesImageFileAndUrl()
{
    var image = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(true, "C:/tmp/image.png", [new ClipboardFileItem("C:/tmp/file.txt", false)], "https://example.test/a"),
        new ClipboardUploadRules());
    AssertEqual(ClipboardDispatchActionKind.UploadImage, image.Kind);
    AssertEqual(UploadSourceKind.ClipboardImage, image.SourceKind);
    AssertEqual("C:/tmp/image.png", image.Value);

    var file = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [new ClipboardFileItem("C:/tmp/file.txt", false)], "https://example.test/a"),
        new ClipboardUploadRules());
    AssertEqual(ClipboardDispatchActionKind.UploadFile, file.Kind);
    AssertEqual(UploadSourceKind.ClipboardFile, file.SourceKind);
    AssertEqual("C:/tmp/file.txt", file.Value);
    return Task.CompletedTask;
}

static Task ClipboardDispatchFoldersAndUrlRules()
{
    var folder = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [new ClipboardFileItem("C:/tmp/folder", true)], null),
        new ClipboardUploadRules(AutoIndexFolder: true));
    AssertEqual(ClipboardDispatchActionKind.IndexFolder, folder.Kind);
    AssertEqual(UploadSourceKind.ClipboardFolder, folder.SourceKind);

    var disabledFolder = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [new ClipboardFileItem("C:/tmp/folder", true)], null),
        new ClipboardUploadRules(AutoIndexFolder: false));
    AssertEqual(ClipboardDispatchActionKind.Unsupported, disabledFolder.Kind);

    var shorten = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [], " https://example.test/a "),
        new ClipboardUploadRules(ShortenUrl: true, UploadUrlContents: true));
    AssertEqual(ClipboardDispatchActionKind.ShortenUrl, shorten.Kind);
    AssertEqual(UploadSourceKind.ClipboardRemoteUrl, shorten.SourceKind);
    AssertEqual("https://example.test/a", shorten.Value);

    var remote = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [], "https://example.test/a"),
        new ClipboardUploadRules(ShortenUrl: false, UploadUrlContents: true));
    AssertEqual(ClipboardDispatchActionKind.UploadRemoteUrl, remote.Kind);

    var copyOnly = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [], "https://example.test/a"),
        new ClipboardUploadRules(ShortenUrl: false, UploadUrlContents: false, ShareUrlAfterUpload: true, UploadTextContents: true));
    AssertEqual(ClipboardDispatchActionKind.CopyUrlOnly, copyOnly.Kind);

    var unsupportedUrl = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [], "https://example.test/a"),
        new ClipboardUploadRules(ShortenUrl: false, UploadUrlContents: false, ShareUrlAfterUpload: false, UploadTextContents: true));
    AssertEqual(ClipboardDispatchActionKind.Unsupported, unsupportedUrl.Kind);

    var text = ClipboardUploadDispatcher.Resolve(
        new ClipboardSnapshot(false, null, [], " hello world "),
        new ClipboardUploadRules(UploadTextContents: true));
    AssertEqual(ClipboardDispatchActionKind.UploadText, text.Kind);
    AssertEqual(UploadSourceKind.ClipboardText, text.SourceKind);
    AssertEqual("hello world", text.Value);
    return Task.CompletedTask;
}

static Task PostUploadPlannerHandlesClipboardAndOpenTasks()
{
    var normal = new PasteTargetInfo("Slack", "slack", "general");
    var copyImage = PostUploadPlanner.PlanAfterUpload(
        "https://cdn.example/capture.png",
        "C:/tmp/capture.png",
        new AfterUploadTaskOptions(CopyImage: true, CopyUrl: true, OpenUrl: true),
        normal);
    AssertEqual(2, copyImage.Count);
    AssertEqual(PostUploadActionKind.CopyImage, copyImage[0].Kind);
    AssertEqual("C:/tmp/capture.png", copyImage[0].Value);
    AssertEqual(PostUploadActionKind.OpenUrl, copyImage[1].Kind);

    var copyFallback = PostUploadPlanner.PlanAfterUpload(
        "https://cdn.example/capture.png",
        "C:/tmp/capture.png",
        new AfterUploadTaskOptions(CopyImage: true, CopyUrl: true),
        normal,
        imageCopyWouldSucceed: false);
    AssertEqual(1, copyFallback.Count);
    AssertEqual(PostUploadActionKind.CopyText, copyFallback[0].Kind);
    AssertEqual("https://cdn.example/capture.png", copyFallback[0].Value);
    return Task.CompletedTask;
}

static Task PostUploadPlannerHandlesCaptureEditorAndDiscord()
{
    var discord = new PasteTargetInfo("Discord", "Discord.exe", "chat");
    AssertEqual(true, PasteTargetPolicy.ShouldPasteUrlInsteadOfImage(discord));
    AssertEqual(true, PasteTargetPolicy.ShouldPasteUrlInsteadOfImage(new PasteTargetInfo("Chrome", "chrome", "Discord | general")));
    AssertEqual(false, PasteTargetPolicy.ShouldPasteUrlInsteadOfImage(new PasteTargetInfo("Safari", "safari", "Docs")));

    var capture = PostUploadPlanner.PlanAfterCapture(
        "record-1",
        "https://cdn.example/capture.png",
        "C:/tmp/capture.png",
        new AfterCaptureTaskOptions(CopyImageAndUrl: true, CopyUrl: true, OpenEditor: true),
        discord);
    AssertEqual(2, capture.Count);
    AssertEqual(PostUploadActionKind.CopyText, capture[0].Kind);
    AssertEqual(PostUploadActionKind.OpenEditor, capture[1].Kind);
    AssertEqual("record-1", capture[1].Value);

    var nonCapture = PostUploadPlanner.Plan(
        NewRecord("record-2") with { SourceKind = UploadSourceKind.File },
        "https://cdn.example/file.png",
        "C:/tmp/file.png",
        new AfterUploadTaskOptions(CopyImage: false, CopyUrl: true, OpenUrl: false),
        new AfterCaptureTaskOptions(OpenEditor: true),
        new PasteTargetInfo("Explorer", "explorer"));
    AssertEqual(1, nonCapture.Count);
    AssertEqual(PostUploadActionKind.CopyText, nonCapture[0].Kind);
    return Task.CompletedTask;
}

static Task PostUploadExecutorRoutesActions()
{
    var clipboard = new FakeClipboardService();
    var shell = new FakeShellLauncher();
    var editor = new FakeEditorLauncher();
    var executor = new PostUploadActionExecutor(clipboard, shell, editor);

    var steps = executor.Execute([
        new PostUploadAction(PostUploadActionKind.CopyText, "https://cdn.example/a.png"),
        new PostUploadAction(PostUploadActionKind.CopyImage, "C:/tmp/a.png"),
        new PostUploadAction(PostUploadActionKind.OpenUrl, "https://cdn.example/a.png"),
        new PostUploadAction(PostUploadActionKind.OpenEditor, "record-1")
    ]);

    AssertEqual(4, steps.Count);
    AssertEqual(true, steps.All(step => step.Succeeded));
    AssertEqual("https://cdn.example/a.png", clipboard.LastText);
    AssertEqual("C:/tmp/a.png", clipboard.LastImagePath);
    AssertEqual("https://cdn.example/a.png", shell.LastUrl);
    AssertEqual("record-1", editor.LastRecordId);
    return Task.CompletedTask;
}

static Task UploadHistoryActionsPreferShortenedUrls()
{
    var record = NewRecord("record-1");
    AssertEqual("https://example.test/capture.png", UploadHistoryActions.PreferredUrl(record));

    var failed = record with { Status = UploadStatus.Failed, ErrorMessage = "previous failure" };
    var shortened = UploadHistoryActions.WithShortenedUrl(failed, "https://short.example/a");
    AssertEqual("https://short.example/a", shortened.ShortenedUrl);
    AssertEqual("https://short.example/a", UploadHistoryActions.PreferredUrl(shortened));
    AssertEqual("https://example.test/capture.png", failed.RemoteUrl);
    AssertEqual(UploadStatus.Failed, shortened.Status);
    AssertEqual("previous failure", shortened.ErrorMessage);
    return Task.CompletedTask;
}

static Task UploadHistoryActionsIdentifyEditableImages()
{
    var image = NewRecord("image") with
    {
        LocalFilePath = "C:/tmp/capture.png",
        RecordKind = UploadRecordKind.Image
    };
    var file = image with
    {
        Id = "file",
        RecordKind = UploadRecordKind.File
    };
    var legacyImage = image with
    {
        Id = "legacy-image",
        RecordKind = UploadRecordKind.Unknown,
        LocalFilePath = "C:/tmp/legacy.jpg"
    };
    var legacyFile = image with
    {
        Id = "legacy-file",
        RecordKind = UploadRecordKind.Unknown,
        LocalFilePath = "C:/tmp/archive.zip"
    };

    AssertEqual(true, UploadHistoryActions.CanEditImage(image));
    AssertEqual(false, UploadHistoryActions.CanEditImage(file));
    AssertEqual(true, UploadHistoryActions.CanEditImage(legacyImage));
    AssertEqual(false, UploadHistoryActions.CanEditImage(legacyFile));
    AssertEqual(false, UploadHistoryActions.CanEditImage(image with { LocalFilePath = null }));
    return Task.CompletedTask;
}
static Task ZiplineEndpointNormalizes()
{
    AssertEqual("https://host.example/api/upload", ZiplineUploadUtilities.EndpointUrl("https://host.example").ToString());
    AssertEqual("https://host.example/base/api/upload", ZiplineUploadUtilities.EndpointUrl("https://host.example/base/api/upload?x=1#frag").ToString());
    AssertThrows(() => ZiplineUploadUtilities.EndpointUrl("http://host.example"));
    return Task.CompletedTask;
}

static Task ZiplineResponseParsing()
{
    var nested = ZiplineUploadUtilities.ParseUploadResponse("""
        { "url": "https://fallback.example/a", "files": [{ "link": "https://cdn.example/file.png", "deletes_at": "2026-07-07T12:30:00Z" }] }
        """);
    AssertEqual("https://cdn.example/file.png", nested.Url);
    AssertEqual(DateTimeOffset.Parse("2026-07-07T12:30:00+00:00"), nested.DeletesAt);

    var top = ZiplineUploadUtilities.ParseUploadResponse("""{ "url": "https://cdn.example/top.png", "deletesAt": "2026-07-07T12:30:00.000Z" }""");
    AssertEqual("https://cdn.example/top.png", top.Url);
    AssertEqual(DateTimeOffset.Parse("2026-07-07T12:30:00+00:00"), top.DeletesAt);
    AssertThrows(() => ZiplineUploadUtilities.ParseUploadResponse("[]"));
    return Task.CompletedTask;
}

static Task ZiplineFilenameSanitization()
{
    AssertEqual("report.pdf", ZiplineUploadUtilities.MultipartSafeFilename("report.pdf"));
    AssertEqual("a_b.png", ZiplineUploadUtilities.MultipartSafeFilename("a\"b.png"));
    AssertEqual("evil__Content-Type: text/html__.png", ZiplineUploadUtilities.MultipartSafeFilename("evil\r\nContent-Type: text/html\r\n.png"));
    AssertEqual("back_slash.png", ZiplineUploadUtilities.MultipartSafeFilename("back\\slash.png"));
    AssertEqual("file.bin", ZiplineUploadUtilities.MultipartSafeFilename("\"\r\n"));

    var headers = ZiplineUploadUtilities.FilenameHeaders("a8f3k9q2m0z7x1bc.png");
    AssertEqual("a8f3k9q2m0z7x1bc", headers.FileNameWithoutExtension);
    AssertEqual("png", headers.FileExtension);
    return Task.CompletedTask;
}

static Task ZiplineValidationStatusClassification()
{
    foreach (var statusCode in new[] { 200, 204, 401, 403, 405 })
    {
        var result = ZiplineUploadUtilities.EndpointValidationResult(UploadBackend.ZiplineV4, statusCode);
        AssertEqual(true, result.IsValid);
        AssertEqual("Zipline endpoint is reachable.", result.Message);
    }

    var notFound = ZiplineUploadUtilities.EndpointValidationResult(UploadBackend.ZiplineV4, 404);
    AssertEqual(true, notFound.IsValid);
    AssertEqual("Zipline endpoint responded (HTTP 404). Assuming reachable.", notFound.Message);

    var bad = ZiplineUploadUtilities.EndpointValidationResult(UploadBackend.ZiplineV4, 500);
    AssertEqual(false, bad.IsValid);
    AssertEqual("Zipline probe returned HTTP 500.", bad.Message);
    return Task.CompletedTask;
}

static Task S3KeyAndUrlHelpers()
{
    AssertEqual("hello_world.png", S3UploadUtilities.SafeFilename("dir/hello world.png"));
    AssertEqual("obs-studio", S3UploadUtilities.SanitizeContext("   OBS / Studio   "));
    AssertEqual("uploads/2026-07-07/obs-studio-abcdef123456-shot.png", S3UploadUtilities.MakeObjectKey(
        DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
        "shot.png",
        " /uploads/ ",
        "OBS Studio",
        "ABCDEF123456"));

    var endpoint = S3UploadUtilities.ParseEndpoint("https://r2.example.test:9443/base/");
    var cfg = new S3DestinationConfig("https://r2.example.test:9443/base/", "auto", " bucket ", "uploads", UsePathStyle: true, null, false, TimeSpan.FromMinutes(30));
    var url = S3UploadUtilities.ObjectUrl("folder/hello world+1.png", endpoint, cfg);
    AssertEqual("https://r2.example.test:9443/base/bucket/folder/hello%20world%2B1.png", url.AbsoluteUri);
    AssertEqual("r2.example.test:9443", S3UploadUtilities.HostHeader(endpoint, cfg));

    var virtualCfg = cfg with { UsePathStyle = false, Bucket = "bucket" };
    AssertEqual("bucket.r2.example.test:9443", S3UploadUtilities.HostHeader(endpoint, virtualCfg));
    AssertEqual(60, S3UploadUtilities.ClampSignedGetExpirySeconds(1));
    AssertEqual(604800, S3UploadUtilities.ClampSignedGetExpirySeconds(9999999));
    return Task.CompletedTask;
}

static Task S3CanonicalQueryAndSigning()
{
    AssertEqual("a%20b%2Bc%2F~", S3UploadUtilities.AwsPercentEncode("a b+c/~"));
    AssertEqual("A=1&X=0&X=2&space=a%20b", S3UploadUtilities.CanonicalQueryString([
        new KeyValuePair<string, string?>("X", "2"),
        new KeyValuePair<string, string?>("space", "a b"),
        new KeyValuePair<string, string?>("A", "1"),
        new KeyValuePair<string, string?>("X", "0")
    ]));

    var endpoint = S3UploadUtilities.ParseEndpoint("https://s3.example.test:9000/api");
    var cfg = new S3DestinationConfig("https://s3.example.test:9000/api", "us-east-1", "bucket", "", UsePathStyle: false, null, false, TimeSpan.FromMinutes(30));
    var signed = S3UploadUtilities.SignRequest(
        "PUT",
        "2026-07-07/context-abcdef-file.txt",
        [],
        S3UploadUtilities.Sha256Hex("payload"),
        "text/plain; charset=utf-8",
        endpoint,
        cfg,
        new S3Credentials("AKID", "SECRET", "TOKEN"),
        DateTimeOffset.Parse("2026-07-07T12:34:56Z"));

    AssertContains(signed.CanonicalRequest, "PUT\n/api/2026-07-07/context-abcdef-file.txt\n\ncontent-type:text/plain; charset=utf-8\nhost:bucket.s3.example.test:9000\nx-amz-content-sha256:");
    AssertContains(signed.CanonicalRequest, "x-amz-security-token:TOKEN\n");
    AssertEqual("content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token", signed.SignedHeaders);
    AssertContains(signed.Authorization, "Credential=AKID/20260707/us-east-1/s3/aws4_request");

    var get = S3UploadUtilities.SignedGetUrl("file.txt", 1, endpoint, cfg, new S3Credentials("AKID", "SECRET"), DateTimeOffset.Parse("2026-07-07T12:34:56Z"));
    AssertEqual(60, get.ExpiresSeconds);
    AssertContains(get.Url.ToString(), "X-Amz-Expires=60");
    AssertContains(get.Url.ToString(), "X-Amz-Signature=");
    return Task.CompletedTask;
}

static Task UrlShortenerHelpers()
{
    var tiny = URLShortenerUtilities.BuildRequest("https://example.test/a b?x=1&y=2", new ShortenerRequest(ShortenerProvider.TinyUrl));
    AssertEqual("https://tinyurl.com/api-create.php?url=https%3A%2F%2Fexample.test%2Fa%20b%3Fx%3D1%26y%3D2", tiny.Url.AbsoluteUri);

    var custom = URLShortenerUtilities.BuildRequest("https://example.test/a?x=1&y=2", new ShortenerRequest(ShortenerProvider.CustomGetTemplate, "https://short.example/make?u={url}"));
    AssertEqual("https://short.example/make?u=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1%26y%3D2", custom.Url.AbsoluteUri);
    AssertEqual("https://short.example/x", URLShortenerUtilities.ParseTinyUrlResponse(200, " https://short.example/x\n"));
    AssertEqual("https://short.example/json", URLShortenerUtilities.ParseCustomResponse(200, """{ "shortUrl": "https://short.example/json" }"""));
    AssertEqual("https://short.example/plain", URLShortenerUtilities.ParseCustomResponse(200, "https://short.example/plain"));
    AssertThrows(() => URLShortenerUtilities.BuildRequest("ftp://example.test/file", new ShortenerRequest(ShortenerProvider.TinyUrl)));
    return Task.CompletedTask;
}

static Task CloudflareAllowlistHelpers()
{
    AssertEqual("203.0.113.10", CloudflareAllowlistClient.PublicIpFromCloudflareTrace("fl=1\nip=203.0.113.10\nts=1"));
    AssertEqual(true, CloudflareAllowlistClient.IsValidIpAddress("203.0.113.10"));
    AssertEqual(true, CloudflareAllowlistClient.IsValidIpAddress("2001:db8::1"));
    AssertEqual(false, CloudflareAllowlistClient.IsValidIpAddress("not-an-ip"));
    AssertEqual(true, CloudflareAllowlistClient.LooksLikeCloudflareId("0123456789abcdef0123456789ABCDEF"));
    AssertEqual(false, CloudflareAllowlistClient.LooksLikeCloudflareId("crafty"));
    AssertEqual("up|ethernet,wifi", CloudflareAllowlistClient.NetworkPathSignature("up", ["wifi", "ethernet"]));
    AssertEqual(false, CloudflareAllowlistClient.ShouldRefreshAfterPathChange(null, "up|wifi", isSatisfied: true));
    AssertEqual(false, CloudflareAllowlistClient.ShouldRefreshAfterPathChange("up|wifi", "down|wifi", isSatisfied: false));
    AssertEqual(false, CloudflareAllowlistClient.ShouldRefreshAfterPathChange("up|wifi", "up|wifi", isSatisfied: true));
    AssertEqual(true, CloudflareAllowlistClient.ShouldRefreshAfterPathChange("up|wifi", "up|ethernet", isSatisfied: true));

    var items = CloudflareAllowlistClient.ManagedItems(
        [
            new CloudflareListItem("1", "198.51.100.1", "keep"),
            new CloudflareListItem("2", "203.0.113.9", "craftycannon-device:this-device old"),
            new CloudflareListItem("3", "bad", "drop"),
            new CloudflareListItem("4", "2001:db8::10", "other")
        ],
        "203.0.113.10",
        "craftycannon-device:this-device",
        "Test PC",
        DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    AssertEqual(3, items.Count);
    AssertEqual(true, items.Any(item => item.Ip == "198.51.100.1" && item.Comment == "keep"));
    AssertEqual(true, items.Any(item => item.Ip == "2001:db8::10" && item.Comment == "other"));
    AssertEqual(true, items.Any(item => item.Ip == "203.0.113.10" && item.Comment.StartsWith("craftycannon-device:this-device Test PC updated", StringComparison.Ordinal)));
    AssertEqual(false, items.Any(item => item.Ip == "203.0.113.9"));
    return Task.CompletedTask;
}

static async Task CloudflareAllowlistClientUpdatesList()
{
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "success": true, "result": [{ "id": "list-1", "name": "crafty", "kind": "ip" }] }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("ip=203.0.113.10\n"), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "success": true, "result": [{ "id": "item-1", "ip": "198.51.100.1", "comment": "keep" }], "result_info": { "cursors": {} } }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "success": true, "result": { "operation_id": "op-1" } }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "success": true, "result": { "id": "op-1", "status": "completed" } }"""), new Dictionary<string, string>()));
    var client = new CloudflareAllowlistClient(transport, new Uri("https://api.example/client/v4/"), new Uri("https://trace.example/trace"));

    var result = await client.UpdateAsync(
        new CloudflareAllowlistConfig(true, "acct", "crafty", "Test PC", 15),
        "token-123",
        "craftycannon-device:device-1",
        DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    AssertEqual("203.0.113.10", result.IpAddress);
    AssertEqual("op-1", result.OperationId);
    AssertEqual(5, transport.Requests.Count);
    AssertEqual("https://api.example/client/v4/accounts/acct/rules/lists", transport.Requests[0].Url.AbsoluteUri);
    AssertEqual("https://trace.example/trace", transport.Requests[1].Url.AbsoluteUri);
    AssertEqual(HttpMethod.Put, transport.Requests[3].Method);
    AssertEqual("Bearer token-123", transport.Requests[0].Headers["Authorization"]);
    var body = Encoding.UTF8.GetString(transport.Requests[3].Content!.Bytes);
    AssertContains(body, "198.51.100.1");
    AssertContains(body, "203.0.113.10");
    AssertContains(body, "craftycannon-device:device-1 Test PC updated");
}
static Task UrlRewriteHelper()
{
    AssertEqual("https://cdn.example/test.png", URLRewriteService.Apply("https://origin.example/test.png", true, "origin\\.example", "cdn.example"));
    AssertEqual("https://origin.example/test.png", URLRewriteService.Apply("https://origin.example/test.png", true, "(", "broken"));
    AssertEqual("https://origin.example/test.png", URLRewriteService.Apply("https://origin.example/test.png", false, "origin", "cdn"));
    return Task.CompletedTask;
}

static async Task UploadPayloadPreparerMaterializesText()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var preparer = new UploadPayloadPreparer(paths, new FakeTransport());

    var payload = await preparer.PrepareTextAsync("  hello world  ", UploadSourceKind.ClipboardText);

    AssertEqual(UploadPayloadKind.Text, payload.Kind);
    AssertEqual(UploadSourceKind.ClipboardText, payload.SourceKind);
    AssertEqual(true, payload.TemporarySourceFile);
    AssertEqual(null, payload.UploadContext);
    AssertEqual("text/plain", payload.MimeType);
    AssertEqual("hello world", await File.ReadAllTextAsync(payload.FilePath));
    AssertContains(payload.FilePath, Path.Combine("Temp", "TextUploads"));
    AssertThrows(() => preparer.PrepareTextAsync("  ").GetAwaiter().GetResult());
}

static async Task UploadPayloadPreparerDownloadsRemoteUrl()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("image-bytes"), new Dictionary<string, string>
    {
        ["Content-Type"] = "image/png; charset=binary",
        ["Content-Disposition"] = "attachment; filename=\"shot.png\"",
        ["Content-Length"] = "11"
    }));
    var preparer = new UploadPayloadPreparer(paths, transport);

    var payload = await preparer.PrepareRemoteUrlAsync("https://example.test/download", UploadSourceKind.ManualRemoteUrl);

    AssertEqual(UploadPayloadKind.RemoteImage, payload.Kind);
    AssertEqual(UploadSourceKind.ManualRemoteUrl, payload.SourceKind);
    AssertEqual(true, payload.TemporarySourceFile);
    AssertEqual("remote-url", payload.UploadContext);
    AssertEqual("image/png", payload.MimeType);
    AssertContains(payload.FilePath, Path.Combine("Temp", "RemoteDownloads"));
    AssertContains(Path.GetFileName(payload.FilePath), "shot-");
    AssertEqual("image-bytes", await File.ReadAllTextAsync(payload.FilePath));
    AssertEqual(HttpMethod.Get, transport.Requests[0].Method);
    AssertEqual("https://example.test/download", transport.Requests[0].Url.ToString());
}

static async Task UploadPayloadPreparerRejectsUnsafeRemoteResponses()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var badStatus = new FakeTransport();
    badStatus.Enqueue(new TransportResponse(404, Encoding.UTF8.GetBytes("missing"), new Dictionary<string, string>()));
    var preparer = new UploadPayloadPreparer(paths, badStatus, maxRemoteResponseBytes: 4);
    await AssertThrowsAsync(() => preparer.PrepareRemoteUrlAsync("https://example.test/missing"));
    AssertThrows(() => preparer.PrepareRemoteUrlAsync("file:///C:/tmp/a.txt").GetAwaiter().GetResult());

    var empty = new FakeTransport();
    empty.Enqueue(new TransportResponse(200, [], new Dictionary<string, string>()));
    await AssertThrowsAsync(() => new UploadPayloadPreparer(paths, empty).PrepareRemoteUrlAsync("https://example.test/empty"));

    var tooLargeHeader = new FakeTransport();
    tooLargeHeader.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("1234"), new Dictionary<string, string> { ["Content-Length"] = "5" }));
    await AssertThrowsAsync(() => new UploadPayloadPreparer(paths, tooLargeHeader, maxRemoteResponseBytes: 4).PrepareRemoteUrlAsync("https://example.test/large"));

    var tooLargeBody = new FakeTransport();
    tooLargeBody.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("12345"), new Dictionary<string, string>()));
    await AssertThrowsAsync(() => new UploadPayloadPreparer(paths, tooLargeBody, maxRemoteResponseBytes: 4).PrepareRemoteUrlAsync("https://example.test/large"));
}

static async Task UploadPayloadPreparerCreatesFolderIndex()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var root = Path.Combine(paths.LocalRoot, "Folder Source");
    var nested = Path.Combine(root, "nested");
    Directory.CreateDirectory(nested);
    await File.WriteAllTextAsync(Path.Combine(root, "a.txt"), "abc");
    await File.WriteAllTextAsync(Path.Combine(root, ".secret"), "hidden");
    await File.WriteAllTextAsync(Path.Combine(nested, "b.txt"), "hello");
    var preparer = new UploadPayloadPreparer(paths, new FakeTransport());

    var lines = UploadPayloadPreparer.BuildFolderIndexLines(root, includeSubdirectories: false, DateTimeOffset.Parse("2026-07-07T12:00:00Z"));
    AssertEqual("Folder index", lines[0]);
    AssertEqual("Root: " + Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), lines[1]);
    AssertEqual("Generated: 2026-07-07T12:00:00Z", lines[2]);
    AssertEqual("", lines[3]);
    AssertEqual(true, lines.Contains("- a.txt (3 bytes)"));
    AssertEqual(false, lines.Any(line => line.Contains(".secret", StringComparison.Ordinal)));
    AssertEqual(false, lines.Any(line => line.Contains("nested", StringComparison.Ordinal)));

    var recursive = UploadPayloadPreparer.BuildFolderIndexLines(root, includeSubdirectories: true, DateTimeOffset.Parse("2026-07-07T12:00:00Z"));
    AssertEqual(true, recursive.Contains("- nested/b.txt (5 bytes)"));

    var payload = await preparer.PrepareFolderIndexAsync(root, includeSubdirectories: true, generatedAt: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));
    AssertEqual(UploadPayloadKind.FolderIndex, payload.Kind);
    AssertEqual(UploadSourceKind.ClipboardFolder, payload.SourceKind);
    AssertEqual(false, payload.TemporarySourceFile);
    AssertEqual(null, payload.UploadContext);
    AssertEqual("text/plain", payload.MimeType);
    AssertContains(Path.GetFileName(payload.FilePath), "Folder-Source-index-");
    var indexText = await File.ReadAllTextAsync(payload.FilePath);
    AssertContains(indexText, "Folder index");
    AssertContains(indexText, "- nested/b.txt (5 bytes)");

    var empty = Path.Combine(paths.LocalRoot, "Empty");
    Directory.CreateDirectory(empty);
    var emptyLines = UploadPayloadPreparer.BuildFolderIndexLines(empty, includeSubdirectories: true, DateTimeOffset.Parse("2026-07-07T12:00:00Z"));
    AssertEqual("(no files found)", emptyLines[4]);
}

static async Task UploadPayloadPreparerCreatesFolderBatch()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var root = Path.Combine(paths.LocalRoot, "Batch");
    var nested = Path.Combine(root, "nested");
    Directory.CreateDirectory(nested);
    var image = Path.Combine(root, "b.png");
    var file = Path.Combine(root, "a.txt");
    var nestedFile = Path.Combine(nested, "c.txt");
    await File.WriteAllTextAsync(image, "png");
    await File.WriteAllTextAsync(file, "txt");
    await File.WriteAllTextAsync(nestedFile, "nested");
    await File.WriteAllTextAsync(Path.Combine(root, ".hidden"), "hidden");
    var preparer = new UploadPayloadPreparer(paths, new FakeTransport());

    var topOnly = preparer.PrepareFolderBatch(root, includeSubdirectories: false, UploadSourceKind.Folder, batchId: "batch-1");
    AssertEqual("batch-1", topOnly.BatchId);
    AssertEqual(2, topOnly.Payloads.Count);
    AssertEqual(file, topOnly.Payloads[0].FilePath);
    AssertEqual(UploadPayloadKind.File, topOnly.Payloads[0].Kind);
    AssertEqual("folder-batch", topOnly.Payloads[0].UploadContext);
    AssertEqual(image, topOnly.Payloads[1].FilePath);
    AssertEqual(UploadPayloadKind.Image, topOnly.Payloads[1].Kind);
    AssertEqual(false, topOnly.Payloads.Any(payload => payload.FilePath.Contains(".hidden", StringComparison.Ordinal)));

    var recursive = preparer.PrepareFolderBatch(root, includeSubdirectories: true, UploadSourceKind.Folder, batchId: "batch-2");
    AssertEqual(3, recursive.Payloads.Count);
    AssertEqual(true, recursive.Payloads.Any(payload => payload.FilePath == nestedFile));
    AssertEqual(true, recursive.Payloads.All(payload => payload.SourceKind == UploadSourceKind.Folder));
}

static async Task UploadWorkflowUploadsClipboardText()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/text.txt" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var clipboard = new FakeClipboardService();
    var workflow = NewWorkflow(paths, transport, history, clipboard);

    var outcome = await workflow.ExecuteClipboardAsync(
        new ClipboardSnapshot(false, null, [], "  hello workflow  "),
        new ClipboardUploadRules(UploadTextContents: true),
        NewWorkflowOptions(DefaultFileExpirySeconds: 120, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z")));

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(1, outcome.Records.Count);
    AssertEqual(UploadStatus.Uploaded, outcome.Records[0].Status);
    AssertEqual(UploadSourceKind.ClipboardText, outcome.Records[0].SourceKind);
    AssertEqual("https://cdn.example/text.txt", outcome.Url);
    AssertEqual("https://cdn.example/text.txt", clipboard.LastText);
    AssertEqual(false, File.Exists(outcome.Records[0].LocalFilePath!));
    AssertEqual("date=2026-07-07T12:02:00.000Z", transport.Requests[0].Headers["x-zipline-deletes-at"]);
    AssertContains(Encoding.UTF8.GetString(transport.Requests[0].Content!.Bytes), "hello workflow");
}

static async Task UploadWorkflowCopiesAndShortensUrls()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("https://short.example/a\n"), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var clipboard = new FakeClipboardService();
    var workflow = NewWorkflow(paths, transport, history, clipboard);

    var copy = await workflow.ExecuteClipboardAsync(
        new ClipboardSnapshot(false, null, [], "https://example.test/a"),
        new ClipboardUploadRules(UploadUrlContents: false, ShareUrlAfterUpload: true),
        NewWorkflowOptions());
    AssertEqual(UploadWorkflowOutcomeKind.CopiedUrl, copy.Kind);
    AssertEqual("https://example.test/a", clipboard.LastText);
    AssertEqual(0, history.Records.Count);

    var shorten = await workflow.ExecuteClipboardAsync(
        new ClipboardSnapshot(false, null, [], "https://example.test/a"),
        new ClipboardUploadRules(ShortenUrl: true),
        NewWorkflowOptions(Shortener: new ShortenerRequest(ShortenerProvider.TinyUrl)));
    AssertEqual(UploadWorkflowOutcomeKind.ShortenedUrl, shorten.Kind);
    AssertEqual("https://short.example/a", shorten.Url);
    AssertEqual("https://short.example/a", clipboard.LastText);
    AssertContains(transport.Requests[0].Url.AbsoluteUri, "tinyurl.com/api-create.php");
}

static async Task UploadWorkflowRewritesUploadedUrls()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "capture.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://origin.example/capture.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var clipboard = new FakeClipboardService();
    var workflow = NewWorkflow(paths, transport, history, clipboard);

    var outcome = await workflow.UploadLocalFileAsync(
        file,
        NewWorkflowOptions(Rewrite: new UrlRewriteOptions(true, "origin\\.example", "cdn.example")));

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual("https://cdn.example/capture.png", outcome.Url);
    AssertEqual("https://cdn.example/capture.png", outcome.Records[0].RemoteUrl);
    AssertEqual("https://cdn.example/capture.png", clipboard.LastText);
}
static async Task UploadWorkflowUploadsFolderBatch()
{
    var paths = new TestStoragePaths(NewTempRoot());
    var root = Path.Combine(paths.LocalRoot, "BatchWorkflow");
    Directory.CreateDirectory(root);
    var first = Path.Combine(root, "a.txt");
    var second = Path.Combine(root, "b.png");
    await File.WriteAllTextAsync(first, "file-a");
    await File.WriteAllTextAsync(second, "file-b");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/a.txt" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/b.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var clipboard = new FakeClipboardService();
    var workflow = NewWorkflow(paths, transport, history, clipboard);

    var outcome = await workflow.UploadFolderBatchAsync(
        root,
        includeSubdirectories: false,
        NewWorkflowOptions(DefaultFileExpirySeconds: 90, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z")));

    AssertEqual(UploadWorkflowOutcomeKind.UploadedBatch, outcome.Kind);
    AssertEqual(2, outcome.Records.Count);
    AssertEqual(true, outcome.Records.All(record => record.Status == UploadStatus.Uploaded));
    AssertEqual(true, outcome.Records.All(record => record.BatchId == outcome.Records[0].BatchId));
    AssertEqual(UploadSourceKind.ManualFolderBatch, outcome.Records[0].SourceKind);
    AssertEqual(UploadSourceKind.ManualFolderBatch, outcome.Records[1].SourceKind);
    AssertEqual("https://cdn.example/b.png", clipboard.LastText);
    AssertEqual("date=2026-07-07T12:01:30.000Z", transport.Requests[0].Headers["x-zipline-deletes-at"]);
    AssertEqual(false, transport.Requests[1].Headers.ContainsKey("x-zipline-deletes-at"));
}

static async Task UploadWorkflowRoutesByContentKindAndExtension()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var imageFile = Path.Combine(paths.LocalRoot, "capture.png");
    var gifFile = Path.Combine(paths.LocalRoot, "anim.gif");
    var fallbackFile = Path.Combine(paths.LocalRoot, "fallback.bin");
    await File.WriteAllTextAsync(imageFile, "png");
    await File.WriteAllTextAsync(gifFile, "gif");
    await File.WriteAllTextAsync(fallbackFile, "bin");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/image.png" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/text.txt" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/gif.gif" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/fallback.bin" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var active = new UploadRouteProfile(NewZiplineProfile("active"), new ProfileSecrets(ZiplineApiKey: "active-token"));
    var image = new UploadRouteProfile(NewZiplineProfile("image"), new ProfileSecrets(ZiplineApiKey: "image-token"));
    var text = new UploadRouteProfile(NewZiplineProfile("text"), new ProfileSecrets(ZiplineApiKey: "text-token"));
    var gif = new UploadRouteProfile(NewZiplineProfile("gif"), new ProfileSecrets(ZiplineApiKey: "gif-token"));
    var options = NewWorkflowOptions(
        RoutedProfiles: [active, image, text, gif],
        UploaderFilters: [new UploaderFilterRule("gif-rule", [" .GIF "], "gif")],
        DestinationRouting: new DestinationRoutingConfig(ImageProfileId: "image", TextProfileId: "text", FileProfileId: "missing"));

    var imageOutcome = await workflow.UploadLocalFileAsync(imageFile, options);
    var textOutcome = await workflow.UploadTextAsync("route text", options);
    var gifOutcome = await workflow.UploadLocalFileAsync(gifFile, options);
    var fallbackOutcome = await workflow.UploadLocalFileAsync(fallbackFile, options);

    AssertEqual("Primary image", imageOutcome.Records[0].ProfileName);
    AssertEqual("Primary text", textOutcome.Records[0].ProfileName);
    AssertEqual("Primary gif", gifOutcome.Records[0].ProfileName);
    AssertEqual("Primary active", fallbackOutcome.Records[0].ProfileName);
    AssertEqual("image-token", transport.Requests[0].Headers["Authorization"].Replace("Bearer ", string.Empty));
    AssertEqual("text-token", transport.Requests[1].Headers["Authorization"].Replace("Bearer ", string.Empty));
    AssertEqual("gif-token", transport.Requests[2].Headers["Authorization"].Replace("Bearer ", string.Empty));
    AssertEqual("active-token", transport.Requests[3].Headers["Authorization"].Replace("Bearer ", string.Empty));
}

static async Task UploadWorkflowPreservesRoutedSecondaryMirror()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "capture.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/capture.png" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, [], new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var mirrorProfile = NewS3Profile("mirror");
    var imageProfile = NewZiplineProfile("image") with { SecondaryS3ProfileId = mirrorProfile.Id };
    var options = NewWorkflowOptions(
        Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
        RoutedProfiles:
        [
            new UploadRouteProfile(NewZiplineProfile("active"), new ProfileSecrets(ZiplineApiKey: "active-token")),
            new UploadRouteProfile(imageProfile, new ProfileSecrets(ZiplineApiKey: "image-token")),
            new UploadRouteProfile(mirrorProfile, new ProfileSecrets(S3AccessKey: "AKID", S3SecretKey: "SECRET"))
        ],
        DestinationRouting: new DestinationRoutingConfig(ImageProfileId: "image"));

    var outcome = await workflow.UploadLocalFileAsync(file, options);

    AssertEqual(UploadStatus.Uploaded, outcome.Records[0].Status);
    AssertEqual("Primary image", outcome.Records[0].ProfileName);
    AssertEqual(SecondaryUploadStatus.Uploaded, outcome.Records[0].SecondaryStatus);
    AssertContains(outcome.Records[0].SecondaryUrl ?? string.Empty, "https://mirror-cdn.example/mirror/");
    AssertEqual(2, transport.Requests.Count);
}
static async Task UploadWorkflowUploadsManualCommands()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "manual.txt");
    var folder = Path.Combine(paths.LocalRoot, "IndexMe");
    Directory.CreateDirectory(folder);
    await File.WriteAllTextAsync(file, "manual-file");
    await File.WriteAllTextAsync(Path.Combine(folder, "entry.txt"), "entry");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/manual.txt" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/text.txt" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("remote-bytes"), new Dictionary<string, string> { ["Content-Type"] = "text/plain" }));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/remote.txt" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/index.txt" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(DefaultFileExpirySeconds: 60, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    var local = await workflow.UploadLocalFileAsync(file, options);
    var textUpload = await workflow.UploadTextAsync("manual text", options);
    var remote = await workflow.UploadRemoteUrlAsync("https://example.test/remote", options);
    var index = await workflow.UploadFolderIndexAsync(folder, options);

    AssertEqual(UploadSourceKind.ManualFile, local.Records[0].SourceKind);
    AssertEqual(UploadSourceKind.ManualText, textUpload.Records[0].SourceKind);
    AssertEqual(UploadSourceKind.ManualRemoteUrl, remote.Records[0].SourceKind);
    AssertEqual(UploadSourceKind.ManualFolderIndex, index.Records[0].SourceKind);
    AssertEqual("https://cdn.example/index.txt", index.Url);
    AssertEqual(true, File.Exists(index.Records[0].LocalFilePath!));
    AssertEqual(5, transport.Requests.Count);
    AssertEqual(HttpMethod.Get, transport.Requests[2].Method);
}


static async Task UploadWorkflowBlocksImageWhenRedactionRequired()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "sensitive.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(RedactionPolicy: UploadRedactionPolicy.AskBeforeUpload);

    var outcome = await workflow.UploadLocalFileAsync(file, options);

    AssertEqual(UploadWorkflowOutcomeKind.Unsupported, outcome.Kind);
    AssertContains(outcome.Message ?? string.Empty, "Redaction check is required");
    AssertEqual(0, history.Records.Count);
    AssertEqual(0, transport.Requests.Count);
}

static async Task UploadWorkflowAutoRedactsImage()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var original = Path.Combine(paths.LocalRoot, "sensitive.png");
    var redacted = Path.Combine(paths.ImagesDirectory, "redacted.png");
    await File.WriteAllTextAsync(original, "original-sensitive-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/redacted.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var redaction = new FakeUploadRedactionService(redacted, "redacted-safe-bytes");
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService(), uploadRedactionService: redaction);
    var options = NewWorkflowOptions(RedactionPolicy: UploadRedactionPolicy.AutoRedact, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    var outcome = await workflow.UploadLocalFileAsync(original, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(1, redaction.Calls);
    AssertEqual(SmartRedactionRenderMode.Pixelate, redaction.RenderMode);
    AssertEqual(redacted, outcome.Records[0].LocalFilePath);
    AssertEqual(true, outcome.Records[0].IsManagedLocalCopy);
    AssertEqual(true, File.Exists(redacted));
    AssertContains(Encoding.UTF8.GetString(transport.Requests[0].Content!.Bytes), "redacted-safe-bytes");
    AssertDoesNotContain(Encoding.UTF8.GetString(transport.Requests[0].Content!.Bytes), "original-sensitive-bytes");
}
static void WriteSolidPng(string path, int width, int height)
{
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    var stride = width * 4;
    var pixels = new byte[stride * height];
    for (var i = 0; i < pixels.Length; i += 4)
    {
        pixels[i] = 255;
        pixels[i + 1] = 255;
        pixels[i + 2] = 255;
        pixels[i + 3] = 255;
    }

    var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
    var encoder = new PngBitmapEncoder();
    encoder.Frames.Add(BitmapFrame.Create(bitmap));
    using var stream = File.Create(path);
    encoder.Save(stream);
}
static async Task UploadWorkflowPreprocessesImageAfterRedaction()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var original = Path.Combine(paths.LocalRoot, "sensitive.png");
    var redacted = Path.Combine(paths.TempRoot, "redacted.png");
    var preprocessed = Path.Combine(paths.TempRoot, "prepared.jpg");
    await File.WriteAllTextAsync(original, "original-sensitive-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/prepared.jpg" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var redaction = new FakeUploadRedactionService(redacted, "redacted-safe-bytes");
    var preprocessor = new FakeImageUploadPreprocessor(preprocessed, "prepared-jpeg-bytes", "image/jpeg");
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService(), uploadRedactionService: redaction, imageUploadPreprocessor: preprocessor);
    var options = NewWorkflowOptions(
        RedactionPolicy: UploadRedactionPolicy.AutoRedact,
        StripImageMetadataBeforeUpload: true,
        ImageUploadFormat: ImageUploadFormat.Jpeg,
        Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    var outcome = await workflow.UploadLocalFileAsync(original, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(1, redaction.Calls);
    AssertEqual(1, preprocessor.Calls);
    AssertEqual(redacted, preprocessor.LastImagePath);
    AssertEqual(true, preprocessor.LastStripMetadata);
    AssertEqual(ImageUploadFormat.Jpeg, preprocessor.LastTargetFormat);
    AssertEqual(preprocessed, outcome.Records[0].LocalFilePath);
    AssertEqual("prepared.jpg", outcome.Records[0].FileName);
    var body = Encoding.UTF8.GetString(transport.Requests[0].Content!.Bytes);
    AssertContains(body, "prepared-jpeg-bytes");
    AssertDoesNotContain(body, "redacted-safe-bytes");
}
static Task UploadFilenameGeneratorPatterns()
{
    var now = DateTimeOffset.Parse("2026-07-07T08:09:10Z");
    var pattern = new UploadFileNamingOptions(
        UseNamePattern: true,
        Pattern: "{date}_{time}_{datetime}_{name}_{inc}_{rand}",
        AutoIncrement: 7,
        ReplaceProblematicCharacters: true);
    var filename = UploadFilenameGenerator.GenerateRemoteFilename("C:/tmp/My Bad:Name.png", pattern, now, "abcdef1234567890");
    AssertEqual("2026-07-07_08-09-10_2026-07-07_08-09-10_My-Bad-Name_7_abcdef.png", filename);

    var random = UploadFilenameGenerator.GenerateRemoteFilename("C:/tmp/source.tiff", new UploadFileNamingOptions(UseRandom16Name: true), now, "ABCDEF1234567890zz");
    AssertEqual("abcdef1234567890.tiff", random);

    AssertEqual("upload", UploadFilenameGenerator.SanitizeFilenameComponent(" /?: ", aggressive: true));
    return Task.CompletedTask;
}

static async Task UploadWorkflowAppliesGeneratedRemoteFilenames()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "original name.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/generated.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(
        Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
        FileNaming: new UploadFileNamingOptions(UseNamePattern: true, Pattern: "{date}-{name}-{rand}", ReplaceProblematicCharacters: true),
        Rewrite: null) with { RandomToken = "abc123zzzzzzzzzz" };

    var outcome = await workflow.UploadLocalFileAsync(file, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual("2026-07-07-original-name-abc123.png", outcome.Records[0].FileName);
    AssertEqual("2026-07-07-original-name-abc123", transport.Requests[0].Headers["x-zipline-filename"]);
}
static async Task UploadWorkflowUploadsExpiringManualFile()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "expiring.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/expiring.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(DefaultFileExpirySeconds: 0, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    var outcome = await workflow.UploadExpiringLocalFileAsync(file, 300, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(UploadSourceKind.ManualFile, outcome.Records[0].SourceKind);
    AssertEqual(DateTimeOffset.Parse("2026-07-07T12:05:00Z"), outcome.Records[0].ExpiresAt);
    AssertEqual("date=2026-07-07T12:05:00.000Z", transport.Requests[0].Headers["x-zipline-deletes-at"]);
}

static async Task UploadWorkflowReuploadsExistingRecordInPlace()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "reupload.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes(@"{ ""url"": ""https://cdn.example/reuploaded.png"" }"), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(DefaultFileExpirySeconds: 0, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));
    var existing = NewRecord("same-record") with
    {
        FileName = "reupload.png",
        LocalFilePath = file,
        RemoteUrl = "https://cdn.example/old.png",
        Status = UploadStatus.Uploaded,
        SourceKind = UploadSourceKind.Capture,
        RecordKind = UploadRecordKind.Image,
        OperationKind = UploadOperationKind.ImageUpload
    };
    await history.UpsertAsync(existing);

    var outcome = await workflow.ReuploadHistoryRecordAsync(existing, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(1, history.Records.Count);
    AssertEqual("same-record", outcome.Records[0].Id);
    AssertEqual("same-record", history.Records[0].Id);
    AssertEqual(UploadSourceKind.Reupload, history.Records[0].SourceKind);
    AssertEqual(UploadRecordKind.Image, history.Records[0].RecordKind);
    AssertEqual(UploadOperationKind.ImageUpload, history.Records[0].OperationKind);
    AssertEqual("https://cdn.example/reuploaded.png", history.Records[0].RemoteUrl);
    AssertEqual(true, history.Snapshots.Skip(1).All(record => record.Id == "same-record"));

    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes(@"{ ""url"": ""https://cdn.example/reuploaded-file.png"" }"), new Dictionary<string, string>()));
    var fileRecord = history.Records[0] with
    {
        RecordKind = UploadRecordKind.File,
        OperationKind = UploadOperationKind.FileUpload
    };
    var fileOutcome = await workflow.ReuploadHistoryRecordAsync(fileRecord, options, expiresSeconds: 300);

    AssertEqual("same-record", fileOutcome.Records[0].Id);
    AssertEqual(1, history.Records.Count);
    AssertEqual(UploadRecordKind.File, history.Records[0].RecordKind);
    AssertEqual(UploadOperationKind.FileUpload, history.Records[0].OperationKind);
    AssertEqual(DateTimeOffset.Parse("2026-07-07T12:05:00Z"), history.Records[0].ExpiresAt);
    AssertEqual("date=2026-07-07T12:05:00.000Z", transport.Requests[1].Headers["x-zipline-deletes-at"]);
}

static async Task UploadWorkflowRedactsReupload()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var original = Path.Combine(paths.LocalRoot, "reupload.jpg");
    var redacted = Path.Combine(paths.ImagesDirectory, "redacted.png");
    await File.WriteAllTextAsync(original, "original-sensitive-bytes");
    await File.WriteAllTextAsync(redacted + ".ocr.txt", " redacted OCR text ");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes(@"{ ""url"": ""https://cdn.example/reuploaded-redacted.png"" }"), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var redaction = new FakeUploadRedactionService(redacted, "redacted-safe-bytes");
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService(), new OcrIndexingService(history), redaction);
    var jpgProfile = NewZiplineProfile("jpg-route");
    var pngProfile = NewZiplineProfile("png-route");
    var options = NewWorkflowOptions(
        RedactionPolicy: UploadRedactionPolicy.AutoRedact,
        Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
        RoutedProfiles:
        [
            new UploadRouteProfile(NewZiplineProfile("fallback"), new ProfileSecrets(ZiplineApiKey: "fallback-token")),
            new UploadRouteProfile(jpgProfile, new ProfileSecrets(ZiplineApiKey: "jpg-token")),
            new UploadRouteProfile(pngProfile, new ProfileSecrets(ZiplineApiKey: "png-token"))
        ],
        UploaderFilters:
        [
            new UploaderFilterRule("jpg", [".jpg"], "jpg-route"),
            new UploaderFilterRule("png", [".png"], "png-route")
        ]);
    var existing = NewRecord("same-redacted-record") with
    {
        FileName = "reupload.jpg",
        LocalFilePath = original,
        RemoteUrl = "https://cdn.example/old-sensitive.jpg",
        IsManagedLocalCopy = false,
        OcrStatus = OcrIndexStatus.Indexed,
        OcrText = "old sensitive OCR text",
        RecordKind = UploadRecordKind.Image,
        OperationKind = UploadOperationKind.ImageUpload
    };
    await history.UpsertAsync(existing);

    var outcome = await workflow.ReuploadHistoryRecordAsync(existing, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(1, redaction.Calls);
    AssertEqual("same-redacted-record", outcome.Records[0].Id);
    AssertEqual(redacted, outcome.Records[0].LocalFilePath);
    AssertEqual(true, outcome.Records[0].IsManagedLocalCopy);
    AssertEqual("Primary jpg-route", outcome.Records[0].ProfileName);
    AssertEqual(OcrIndexStatus.Indexed, outcome.Records[0].OcrStatus);
    AssertEqual("redacted OCR text", outcome.Records[0].OcrText);
    AssertEqual(true, File.Exists(redacted));
    var body = Encoding.UTF8.GetString(transport.Requests[0].Content!.Bytes);
    AssertContains(body, "redacted-safe-bytes");
    AssertDoesNotContain(body, "original-sensitive-bytes");
    AssertDoesNotContain(outcome.Records[0].OcrText ?? string.Empty, "old sensitive");
}

static async Task UploadWorkflowBlocksReuploadWhenRedactionRequired()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "reupload.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(RedactionPolicy: UploadRedactionPolicy.AskBeforeUpload);
    var existing = NewRecord("blocked-reupload") with
    {
        LocalFilePath = file,
        RemoteUrl = "https://cdn.example/old.png",
        RecordKind = UploadRecordKind.Image,
        OperationKind = UploadOperationKind.ImageUpload
    };
    await history.UpsertAsync(existing);

    var outcome = await workflow.ReuploadHistoryRecordAsync(existing, options);

    AssertEqual(UploadWorkflowOutcomeKind.Unsupported, outcome.Kind);
    AssertContains(outcome.Message ?? string.Empty, "Redaction check is required");
    AssertEqual(0, transport.Requests.Count);
    AssertEqual(1, history.Records.Count);
    AssertEqual("https://cdn.example/old.png", history.Records[0].RemoteUrl);
    AssertEqual(UploadStatus.Uploaded, history.Records[0].Status);
}
static async Task UploadWorkflowUploadsManagedEditorSave()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.ImagesDirectory, "edited.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/edited.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService());
    var options = NewWorkflowOptions(DefaultFileExpirySeconds: 60, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    var original = NewRecord("original") with { LocalFilePath = file, RecordKind = UploadRecordKind.Image };
    await history.UpsertAsync(original);

    var outcome = await workflow.UploadLocalFileAsync(file, options, UploadSourceKind.ManualFile, isManagedLocalCopy: true);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(UploadStatus.Uploaded, outcome.Records[0].Status);
    AssertEqual(2, history.Records.Count);
    AssertEqual("original", history.Records[1].Id);
    AssertEqual(UploadSourceKind.ManualFile, outcome.Records[0].SourceKind);
    AssertEqual(UploadRecordKind.Image, outcome.Records[0].RecordKind);
    AssertEqual(UploadOperationKind.ImageUpload, outcome.Records[0].OperationKind);
    AssertEqual(true, outcome.Records[0].IsManagedLocalCopy);
    AssertEqual(file, outcome.Records[0].LocalFilePath);
    AssertEqual(false, outcome.Records[0].ExpiresAt.HasValue);
}
static async Task OcrIndexingUpdatesImageUploadRecords()
{
    var paths = new TestStoragePaths(NewTempRoot());
    paths.EnsureCreated();
    var file = Path.Combine(paths.LocalRoot, "capture.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    await File.WriteAllTextAsync(file + ".ocr.txt", " visible text from sidecar ");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://cdn.example/capture.png" }"""), new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var workflow = NewWorkflow(paths, transport, history, new FakeClipboardService(), new OcrIndexingService(history));
    var options = NewWorkflowOptions(DefaultFileExpirySeconds: 0, Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"));

    var outcome = await workflow.UploadLocalFileAsync(file, options);

    AssertEqual(UploadWorkflowOutcomeKind.Uploaded, outcome.Kind);
    AssertEqual(OcrIndexStatus.Indexed, outcome.Records[0].OcrStatus);
    AssertEqual("visible text from sidecar", outcome.Records[0].OcrText);
    AssertEqual("Sidecar OCR test recognizer", outcome.Records[0].OcrEngine);
    AssertEqual("pipeline-v1", outcome.Records[0].OcrEngineVersion);
    AssertEqual(0, outcome.Records[0].OcrRetryCount);
    AssertEqual(true, outcome.Records[0].OcrFileSize is > 0);
    AssertEqual(OcrIndexStatus.Pending, history.Snapshots.First(snapshot => snapshot.Status == UploadStatus.Uploading).OcrStatus);
    AssertEqual(true, history.Snapshots.Any(snapshot => snapshot.OcrStatus == OcrIndexStatus.Pending));
    AssertEqual(OcrIndexStatus.Indexed, history.Records[0].OcrStatus);
}

static async Task OcrAdminStatusAndClearCommands()
{
    var history = new MemoryHistoryStore();
    var image = NewRecord("ocr-1") with
    {
        OcrStatus = OcrIndexStatus.Indexed,
        OcrText = "indexed text",
        OcrEngine = "test",
        OcrEngineVersion = "1",
        OcrIndexedAt = DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
        OcrFileSize = 123,
        OcrFileModifiedAt = DateTimeOffset.Parse("2026-07-07T11:00:00Z"),
        OcrRetryCount = 0,
        RecordKind = UploadRecordKind.Image
    };
    var file = NewRecord("ocr-2") with { RecordKind = UploadRecordKind.File, OcrStatus = OcrIndexStatus.Indexed, OcrText = "should stay" };
    await history.UpsertAsync(image);
    await history.UpsertAsync(file);
    var indexer = new OcrIndexingService(history);
    using var status = new StringWriter();

    var handled = await OcrAdminCommands.RunIfNeededAsync(["index-status"], indexer, history, enabled: true, status);

    AssertEqual(true, handled);
    AssertContains(status.ToString(), "OCR index status");
    AssertContains(status.ToString(), "imageRecords: 1");
    AssertContains(status.ToString(), "indexed: 1");
    AssertContains(status.ToString(), "enabled: true");

    using var cleared = new StringWriter();
    await OcrAdminCommands.RunIfNeededAsync(["clear-index"], indexer, history, enabled: true, cleared);
    AssertContains(cleared.ToString(), "OCR index cleared.");
    AssertEqual(OcrIndexStatus.NotQueued, history.Records.First(record => record.Id == "ocr-1").OcrStatus);
    AssertEqual(null, history.Records.First(record => record.Id == "ocr-1").OcrText);
    AssertEqual(OcrIndexStatus.Indexed, history.Records.First(record => record.Id == "ocr-2").OcrStatus);
}
static async Task ZiplineClientUploadsAndValidates()
{
    var root = NewTempRoot();
    var file = Path.Combine(root, "capture.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "files": [{ "url": "https://cdn.example/capture.png" }] }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(401, [], new Dictionary<string, string>()));
    var client = new ZiplineClient(transport);
    var profile = NewZiplineProfile("zipline") with { Endpoint = "https://zip.example/base/api/upload?ignored=1" };

    var result = await client.UploadAsync(new UploadFileRequest(
        file,
        profile,
        new ProfileSecrets(ZiplineApiKey: "token-123"),
        RemoteFilename: "evil\r\nname.png",
        DeletesAt: DateTimeOffset.Parse("2026-07-07T12:30:00Z")));

    AssertEqual("https://cdn.example/capture.png", result.Url);
    var request = transport.Requests[0];
    AssertEqual(HttpMethod.Post, request.Method);
    AssertEqual("https://zip.example/base/api/upload", request.Url.ToString());
    AssertEqual("token-123", request.Headers["Authorization"]);
    AssertEqual("evil__name", request.Headers["x-zipline-filename"]);
    AssertEqual("png", request.Headers["x-zipline-file-extension"]);
    AssertEqual("date=2026-07-07T12:30:00.000Z", request.Headers["x-zipline-deletes-at"]);
    AssertContains(Encoding.UTF8.GetString(request.Content!.Bytes), "filename=\"evil__name.png\"");

    var validation = await client.ValidateAsync(profile);
    AssertEqual(true, validation.IsValid);
    AssertEqual(HttpMethod.Head, transport.Requests[1].Method);
}

static async Task S3ClientUploadsAndProbes()
{
    var root = NewTempRoot();
    var file = Path.Combine(root, "hello world.txt");
    await File.WriteAllTextAsync(file, "payload");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, [], new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(204, [], new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(204, [], new Dictionary<string, string>()));
    var client = new S3Client(transport);
    var cfg = new S3DestinationConfig(
        "https://s3.example.test:9000/api",
        "us-east-1",
        "bucket",
        "uploads",
        UsePathStyle: false,
        PublicBaseUrl: "https://cdn.example/base",
        UseSignedGetUrls: false,
        SignedGetUrlExpiry: TimeSpan.FromMinutes(30));
    var profile = new UploadProfile("s3", "S3", "", UploadBackend.S3Compatible, cfg, null);
    var secrets = new ProfileSecrets(S3AccessKey: "AKID", S3SecretKey: "SECRET", S3SessionToken: "TOKEN");

    var result = await client.UploadAsync(new UploadFileRequest(
        file,
        profile,
        secrets,
        UploadContext: "OBS Studio",
        RandomToken: "ABCDEF123456",
        Now: DateTimeOffset.Parse("2026-07-07T12:34:56Z")));

    AssertEqual("uploads/2026-07-07/obs-studio-abcdef123456-hello_world.txt", result.Key);
    AssertEqual("https://cdn.example/base/uploads/2026-07-07/obs-studio-abcdef123456-hello_world.txt", result.Url);
    var put = transport.Requests[0];
    AssertEqual(HttpMethod.Put, put.Method);
    AssertContains(put.Url.AbsoluteUri, "https://bucket.s3.example.test:9000/api/uploads/2026-07-07/obs-studio-abcdef123456-hello_world.txt");
    AssertContains(put.Headers["Authorization"], "Credential=AKID/20260707/us-east-1/s3/aws4_request");
    AssertEqual("TOKEN", put.Headers["x-amz-security-token"]);

    var validation = await client.ProbeAsync(profile, secrets, DateTimeOffset.Parse("2026-07-07T12:34:56Z"));
    AssertEqual(true, validation.IsValid);
    AssertEqual(HttpMethod.Put, transport.Requests[1].Method);
    AssertEqual(HttpMethod.Delete, transport.Requests[2].Method);
}

static async Task ShortenerClientUsesTransport()
{
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes(" https://short.example/a\n"), new Dictionary<string, string>()));
    var client = new URLShortenerClient(transport);

    var shortened = await client.ShortenAsync("https://example.test/a?x=1", new ShortenerRequest(ShortenerProvider.TinyUrl));

    AssertEqual("https://short.example/a", shortened);
    AssertEqual(HttpMethod.Get, transport.Requests[0].Method);
    AssertContains(transport.Requests[0].Url.AbsoluteUri, "tinyurl.com/api-create.php");
}
static async Task UploadOrchestratorRecordsPrimaryAndMirror()
{
    var root = NewTempRoot();
    var file = Path.Combine(root, "capture.png");
    await File.WriteAllTextAsync(file, "image-bytes");
    var transport = new FakeTransport();
    transport.Enqueue(new TransportResponse(200, Encoding.UTF8.GetBytes("""{ "url": "https://origin.example/capture.png" }"""), new Dictionary<string, string>()));
    transport.Enqueue(new TransportResponse(200, [], new Dictionary<string, string>()));
    var history = new MemoryHistoryStore();
    var orchestrator = new UploadOrchestrator(new ZiplineClient(transport), new S3Client(transport), history);
    var primary = NewZiplineProfile("zipline") with { Endpoint = "https://zip.example" };
    var secondaryCfg = new S3DestinationConfig(
        "https://s3.example.test",
        "us-east-1",
        "bucket",
        "mirror",
        UsePathStyle: true,
        PublicBaseUrl: "https://mirror-origin.example",
        UseSignedGetUrls: false,
        SignedGetUrlExpiry: TimeSpan.FromMinutes(30));
    var secondary = new UploadProfile("mirror", "Mirror", "", UploadBackend.S3Compatible, secondaryCfg, null);

    var record = await orchestrator.UploadAsync(new UploadOrchestrationRequest(
        file,
        primary,
        new ProfileSecrets(ZiplineApiKey: "zip-token"),
        UploadSourceKind.Capture,
        RemoteFilename: "capture.png",
        UploadContext: "capture",
        Rewrite: new UrlRewriteOptions(true, "origin\\.example", "cdn.example"),
        SecondaryProfile: secondary,
        SecondarySecrets: new ProfileSecrets(S3AccessKey: "AKID", S3SecretKey: "SECRET"),
        Now: DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
        RandomToken: "ABCDEF123456"));

    AssertEqual(UploadStatus.Uploaded, record.Status);
    AssertEqual("https://cdn.example/capture.png", record.RemoteUrl);
    AssertEqual(SecondaryUploadStatus.Uploaded, record.SecondaryStatus);
    AssertEqual("https://mirror-cdn.example/mirror/2026-07-07/capture-abcdef123456-capture.png", record.SecondaryUrl);
    AssertEqual("mirror/2026-07-07/capture-abcdef123456-capture.png", record.SecondaryPath);
    AssertEqual(4, history.Snapshots.Count);
    AssertEqual(UploadStatus.Uploading, history.Snapshots[0].Status);
    AssertEqual(SecondaryUploadStatus.Pending, history.Snapshots[2].SecondaryStatus);
    AssertEqual(SecondaryUploadStatus.Uploaded, history.Snapshots[3].SecondaryStatus);
}
static ProfileExportBundle Bundle(UploadProfile profile, string? apiKey = null) => new(1, profile.Id,
[
    new ExportedUploadProfile(
        profile.Id,
        profile.Name,
        profile.Endpoint,
        profile.Backend,
        profile.S3Config,
        profile.SecondaryS3ProfileId,
        ApiKey: apiKey,
        S3AccessKey: null,
        S3SecretKey: null,
        S3SessionToken: null)
], DateTimeOffset.UtcNow);

static UploadProfile NewZiplineProfile(string id) =>
    new(id, "Primary " + id, "https://zipline.example.test", UploadBackend.ZiplineV4, null, null);

static UploadProfile NewS3Profile(string id) =>
    new(
        id,
        "Mirror " + id,
        string.Empty,
        UploadBackend.S3Compatible,
        new S3DestinationConfig("https://s3.example.test", "us-east-1", "bucket", "mirror", true, "https://mirror-cdn.example", false, TimeSpan.FromMinutes(30)),
        null);

static UploadWorkflowOptions NewWorkflowOptions(
    int DefaultFileExpirySeconds = 60,
    DateTimeOffset? Now = null,
    ShortenerRequest? Shortener = null,
    UploadRedactionPolicy RedactionPolicy = UploadRedactionPolicy.Off,
    IReadOnlyList<UploadRouteProfile>? RoutedProfiles = null,
    IReadOnlyList<UploaderFilterRule>? UploaderFilters = null,
    DestinationRoutingConfig? DestinationRouting = null,
    UrlRewriteOptions? Rewrite = null,
    bool StripImageMetadataBeforeUpload = false,
    ImageUploadFormat ImageUploadFormat = ImageUploadFormat.Png,
    UploadFileNamingOptions? FileNaming = null) =>
    new(
        NewZiplineProfile("workflow"),
        new ProfileSecrets(ZiplineApiKey: "zip-token"),
        DefaultFileExpirySeconds,
        new AfterUploadTaskOptions(CopyImage: false, CopyUrl: true, OpenUrl: false),
        new AfterCaptureTaskOptions(CopyImageAndUrl: true, CopyUrl: true, OpenEditor: false),
        new PasteTargetInfo("Tests", "tests"),
        Now: Now,
        Shortener: Shortener,
        Rewrite: Rewrite,
        RedactionPolicy: RedactionPolicy,
        RoutedProfiles: RoutedProfiles,
        UploaderFilters: UploaderFilters,
        DestinationRouting: DestinationRouting,
        StripImageMetadataBeforeUpload: StripImageMetadataBeforeUpload,
        ImageUploadFormat: ImageUploadFormat,
        FileNaming: FileNaming);

static UploadWorkflowService NewWorkflow(
    TestStoragePaths paths,
    FakeTransport transport,
    MemoryHistoryStore history,
    FakeClipboardService clipboard,
    IOcrIndexingService? ocrIndexingService = null,
    IUploadRedactionService? uploadRedactionService = null,
    IImageUploadPreprocessor? imageUploadPreprocessor = null)
{
    var zipline = new ZiplineClient(transport);
    var s3 = new S3Client(transport);
    var orchestrator = new UploadOrchestrator(zipline, s3, history);
    var executor = new PostUploadActionExecutor(clipboard, new FakeShellLauncher(), new FakeEditorLauncher());
    return new UploadWorkflowService(
        new UploadPayloadPreparer(paths, transport),
        orchestrator,
        new URLShortenerClient(transport),
        executor,
        new TempFileGuard(paths),
        ocrIndexingService,
        uploadRedactionService,
        imageUploadPreprocessor);
}

static UploadRecord NewRecord(string id) => new(
    id,
    UploadStatus.Uploaded,
    DateTimeOffset.Parse("2026-07-07T12:00:00Z"),
    "capture.png",
    "C:/tmp/capture.png",
    "https://example.test/capture.png",
    "Primary",
    null,
    SourceKind: UploadSourceKind.Capture,
    IsManagedLocalCopy: true,
    SecondaryStatus: SecondaryUploadStatus.Uploaded,
    SecondaryUrl: "https://mirror.example.test/capture.png",
    OcrStatus: OcrIndexStatus.Indexed,
    OcrText: "visible text");

static string NewTempRoot()
{
    var root = Path.Combine(Path.GetTempPath(), "CraftyCannonTests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    return root;
}

static void AssertThrows(Action action)
{
    try
    {
        action();
    }
    catch
    {
        return;
    }

    throw new InvalidOperationException("Expected action to throw.");
}

static async Task AssertThrowsAsync(Func<Task> action)
{
    try
    {
        await action();
    }
    catch
    {
        return;
    }

    throw new InvalidOperationException("Expected action to throw.");
}

static void AssertNear(double expected, double actual, double tolerance)
{
    if (Math.Abs(expected - actual) > tolerance)
    {
        throw new InvalidOperationException($"Expected {expected} +/- {tolerance}, got {actual}.");
    }
}
static void AssertEqual<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}, got {actual}.");
    }
}

static void AssertContains(string haystack, string needle)
{
    if (!haystack.Contains(needle, StringComparison.Ordinal))
    {
        throw new InvalidOperationException($"Expected text to contain {needle}.");
    }
}

static void AssertDoesNotContain(string haystack, string needle)
{
    if (haystack.Contains(needle, StringComparison.Ordinal))
    {
        throw new InvalidOperationException($"Expected text not to contain {needle}.");
    }
}

sealed class MemoryHistoryStore : IUploadHistoryWriter
{
    private readonly List<UploadRecord> records = [];

    public List<UploadRecord> Snapshots { get; } = [];

    public IReadOnlyList<UploadRecord> Records => records;

    public Task UpsertAsync(UploadRecord record, CancellationToken cancellationToken = default)
    {
        var index = records.FindIndex(existing => existing.Id == record.Id);
        if (index >= 0)
        {
            records[index] = record;
        }
        else
        {
            records.Insert(0, record);
        }

        Snapshots.Add(record);
        return Task.CompletedTask;
    }

    public Task DeleteAsync(string id, CancellationToken cancellationToken = default)
    {
        records.RemoveAll(record => record.Id == id);
        return Task.CompletedTask;
    }
}
sealed class FakeClipboardService : IClipboardService
{
    public string? LastText { get; private set; }

    public string? LastImagePath { get; private set; }

    public ClipboardSnapshot ReadSnapshot() => ClipboardSnapshot.Empty;

    public bool TrySetText(string text)
    {
        LastText = text;
        return true;
    }

    public bool TrySetImage(string imagePath)
    {
        LastImagePath = imagePath;
        return true;
    }
}

sealed class FakeShellLauncher : IShellLauncher
{
    public string? LastUrl { get; private set; }

    public bool TryOpenUrl(string url)
    {
        LastUrl = url;
        return true;
    }
}

sealed class FakeEditorLauncher : IEditorLauncher
{
    public string? LastRecordId { get; private set; }

    public bool TryOpenRecord(string recordId)
    {
        LastRecordId = recordId;
        return true;
    }
}

sealed class FixedFaceDetectionBackend : IFaceDetectionBackend
{
    private readonly IReadOnlyList<FaceDetectionBox> faces;

    public FixedFaceDetectionBackend(IReadOnlyList<FaceDetectionBox> faces)
    {
        this.faces = faces;
    }

    public Task<IReadOnlyList<FaceDetectionBox>> DetectFacesAsync(string imagePath, CancellationToken cancellationToken = default) =>
        Task.FromResult(faces);
}sealed class FixedSmartRedactionDetector : ISmartRedactionDetector
{
    private readonly IReadOnlyList<RedactionFinding> findings;

    public FixedSmartRedactionDetector(IReadOnlyList<RedactionFinding> findings)
    {
        this.findings = findings;
    }

    public Task<IReadOnlyList<RedactionFinding>> DetectAsync(string imagePath, CancellationToken cancellationToken) =>
        Task.FromResult(findings);
}
sealed class FakeUploadRedactionService : IUploadRedactionService
{
    private readonly string redactedPath;
    private readonly string redactedContent;

    public FakeUploadRedactionService(string redactedPath, string redactedContent)
    {
        this.redactedPath = redactedPath;
        this.redactedContent = redactedContent;
    }

    public int Calls { get; private set; }

    public SmartRedactionRenderMode RenderMode { get; private set; }

    public async Task<UploadRedactionResult> PrepareImageAsync(string imagePath, UploadRedactionPolicy policy, SmartRedactionRenderMode renderMode, CancellationToken cancellationToken = default)
    {
        Calls++;
        RenderMode = renderMode;
        Directory.CreateDirectory(Path.GetDirectoryName(redactedPath)!);
        await File.WriteAllTextAsync(redactedPath, redactedContent, cancellationToken);
        return UploadRedactionResult.Redacted(redactedPath, isManagedLocalCopy: true);
    }
}
sealed class FakeImageUploadPreprocessor : IImageUploadPreprocessor
{
    private readonly string preparedPath;
    private readonly string preparedContent;
    private readonly string mimeType;

    public FakeImageUploadPreprocessor(string preparedPath, string preparedContent, string mimeType)
    {
        this.preparedPath = preparedPath;
        this.preparedContent = preparedContent;
        this.mimeType = mimeType;
    }

    public int Calls { get; private set; }

    public string? LastImagePath { get; private set; }

    public bool LastStripMetadata { get; private set; }

    public ImageUploadFormat LastTargetFormat { get; private set; }

    public async Task<ImageUploadPreprocessingResult> PrepareImageAsync(string imagePath, bool stripMetadata, ImageUploadFormat targetFormat, CancellationToken cancellationToken = default)
    {
        Calls++;
        LastImagePath = imagePath;
        LastStripMetadata = stripMetadata;
        LastTargetFormat = targetFormat;
        Directory.CreateDirectory(Path.GetDirectoryName(preparedPath)!);
        await File.WriteAllTextAsync(preparedPath, preparedContent, cancellationToken);
        return ImageUploadPreprocessingResult.Preprocessed(preparedPath, mimeType);
    }
}sealed class FakeTransport : IHttpTransport
{
    private readonly Queue<TransportResponse> responses = [];

    public List<TransportRequest> Requests { get; } = [];

    public void Enqueue(TransportResponse response) => responses.Enqueue(response);

    public Task<TransportResponse> SendAsync(TransportRequest request, CancellationToken cancellationToken = default)
    {
        Requests.Add(request);
        if (responses.Count == 0)
        {
            throw new InvalidOperationException("No fake response queued.");
        }

        return Task.FromResult(responses.Dequeue());
    }
}
sealed class MemorySecretStore : ISecretStore
{
    private readonly Dictionary<(string Service, string Account), string> secrets = [];

    public string? GetSecret(string service, string account) =>
        secrets.TryGetValue((service, account), out var secret) ? secret : null;

    public void SetSecret(string service, string account, string secret) =>
        secrets[(service, account)] = secret;

    public void DeleteSecret(string service, string account) =>
        secrets.Remove((service, account));
}

sealed class TestStoragePaths : AppStoragePaths
{
    public TestStoragePaths(string root)
        : base("CraftyCannonTests")
    {
        RoamingRoot = Path.Combine(root, "Roaming");
        LocalRoot = Path.Combine(root, "Local");
        HistoryPath = Path.Combine(LocalRoot, "upload-history.json");
        ProfilesPath = Path.Combine(RoamingRoot, "profiles.json");
        ProfileBackupPath = Path.Combine(RoamingRoot, "profiles.config.json");
        ImagesDirectory = Path.Combine(LocalRoot, "Images");
        TempRoot = Path.Combine(root, "Temp");
        ScreenshotsFallbackDirectory = Path.Combine(root, "Documents", "images");
    }
}














































