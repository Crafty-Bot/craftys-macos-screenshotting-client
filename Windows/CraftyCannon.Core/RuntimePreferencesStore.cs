using System.Text.Json;

namespace CraftyCannon.Core;

public sealed class RuntimePreferencesStore
{
    private readonly string path;

    public RuntimePreferencesStore(AppStoragePaths paths)
    {
        path = Path.Combine(paths.RoamingRoot, "runtime-preferences.json");
    }

    public RuntimePreferencesSnapshot Current { get; private set; } = Defaults;

    public static RuntimePreferencesSnapshot Defaults { get; } = new(
        UploadRedactionPolicy.AskBeforeUpload,
        CopyUrlAfterUpload: true,
        CopyImageAfterUpload: false,
        OpenUrlAfterUpload: false,
        OpenEditorAfterCapture: false,
        EnableOcrIndexing: true,
        ActivePaletteId: UiPaletteCatalog.ClassicId,
        CustomPalette: UiPaletteCatalog.DefaultCustomSeed(),
        ShortenerProvider: "tinyURL",
        ShortenerCustomGetTemplate: string.Empty,
        UrlRegexReplaceEnabled: false,
        UrlRegexPattern: string.Empty,
        UrlRegexReplacement: string.Empty,
        SmartRedactionRenderMode: SmartRedactionRenderMode.Pixelate,
        ShowNotificationAfterUpload: true,
        CaptureIncludeCursor: false,
        CaptureDelaySeconds: 0,
        CaptureFixedRegionEnabled: false,
        CaptureFixedRegionX: 0,
        CaptureFixedRegionY: 0,
        CaptureFixedRegionWidth: 1280,
        CaptureFixedRegionHeight: 720,
        CaptureShowInfoOverlay: true,
        CaptureSnapSizes: [],
        CaptureMirrorToScreenshotsFolder: false,
        CaptureScreenshotsFolder: string.Empty,
        WatchFoldersEnabled: false,
        WatchFolderRules: [],
        HotKeys: HotKeyBindings.Defaults,
        UploaderFilters: [],
        DestinationRouting: new DestinationRoutingConfig(),
        CloudflareAllowlist: new CloudflareAllowlistConfig(),
        ClipboardRules: new ClipboardUploadRules(),
        AfterCaptureCopyImageAndUrl: false,
        AfterCaptureCopyUrl: true,
        DefaultFileExpirySeconds: 86_400,
        StripImageMetadataBeforeUpload: false,
        ImageUploadFormat: ImageUploadFormat.Png,
        FileUploadUseNamePattern: false,
        FileUploadUseRandom16Name: false,
        FileNamePattern: "{date}-{rand}",
        FileNameAutoIncrement: 1,
        FileUploadReplaceProblematicCharacters: true,
        OnboardingState: OnboardingState.Pending,
        SmartRedactionDetectors: SmartRedactionDetectorPreferences.Default);

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(path))
        {
            Current = Defaults;
            return;
        }

        await using var stream = File.OpenRead(path);
        Current = Normalize(await JsonSerializer.DeserializeAsync<RuntimePreferencesSnapshot>(stream, JsonOptions.Default, cancellationToken)
            .ConfigureAwait(false) ?? Defaults);
    }

    public async Task SaveAsync(RuntimePreferencesSnapshot preferences, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var normalized = Normalize(preferences);
        await using var stream = File.Create(path);
        await JsonSerializer.SerializeAsync(stream, normalized, JsonOptions.Default, cancellationToken).ConfigureAwait(false);
        Current = normalized;
    }

    private static RuntimePreferencesSnapshot Normalize(RuntimePreferencesSnapshot preferences)
    {
        var provider = string.Equals(preferences.ShortenerProvider, "customGetTemplate", StringComparison.OrdinalIgnoreCase)
            ? "customGetTemplate"
            : "tinyURL";
        return preferences with
        {
            ActivePaletteId = UiPaletteCatalog.NormalizeId(preferences.ActivePaletteId),
            CustomPalette = (preferences.CustomPalette ?? UiPaletteCatalog.DefaultCustomSeed()).Normalized(UiPaletteCatalog.DefaultCustomSeed()),
            ShortenerProvider = provider,
            ShortenerCustomGetTemplate = preferences.ShortenerCustomGetTemplate ?? string.Empty,
            UrlRegexPattern = preferences.UrlRegexPattern ?? string.Empty,
            UrlRegexReplacement = preferences.UrlRegexReplacement ?? string.Empty,
            CaptureDelaySeconds = Math.Clamp(preferences.CaptureDelaySeconds, 0, 5),
            CaptureFixedRegionWidth = Math.Max(1, preferences.CaptureFixedRegionWidth),
            CaptureFixedRegionHeight = Math.Max(1, preferences.CaptureFixedRegionHeight),
            CaptureSnapSizes = CaptureSnapSize.NormalizeList(preferences.CaptureSnapSizes),
            CaptureScreenshotsFolder = NormalizeOptionalDirectory(preferences.CaptureScreenshotsFolder),
            WatchFolderRules = NormalizeWatchFolderRules(preferences.WatchFolderRules),
            HotKeys = (preferences.HotKeys ?? HotKeyBindings.Defaults).Normalized,
            UploaderFilters = NormalizeUploaderFilters(preferences.UploaderFilters),
            DestinationRouting = (preferences.DestinationRouting ?? new DestinationRoutingConfig()).Normalized,
            CloudflareAllowlist = (preferences.CloudflareAllowlist ?? new CloudflareAllowlistConfig()).Normalized,
            ClipboardRules = preferences.ClipboardRules ?? new ClipboardUploadRules(),
            DefaultFileExpirySeconds = Math.Clamp(preferences.DefaultFileExpirySeconds, 60, 5 * 24 * 60 * 60),
            FileNamePattern = string.IsNullOrWhiteSpace(preferences.FileNamePattern) ? Defaults.FileNamePattern : preferences.FileNamePattern.Trim(),
            FileNameAutoIncrement = Math.Max(1, preferences.FileNameAutoIncrement),
            SmartRedactionDetectors = (preferences.SmartRedactionDetectors ?? SmartRedactionDetectorPreferences.Default).Normalized
        };
    }

    private static string NormalizeOptionalDirectory(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return string.Empty;
        }

        try
        {
            return AppStoragePaths.NormalizeUserDirectory(path);
        }
        catch
        {
            return string.Empty;
        }
    }

    private static IReadOnlyList<WatchFolderRule> NormalizeWatchFolderRules(IReadOnlyList<WatchFolderRule>? rules) =>
        rules is null
            ? []
            : rules
                .Where(rule => !string.IsNullOrWhiteSpace(rule.Path))
                .Select(rule => rule with
                {
                    Id = string.IsNullOrWhiteSpace(rule.Id) ? Guid.NewGuid().ToString("N") : rule.Id,
                    Path = rule.Path.Trim(),
                    FileFilter = string.IsNullOrWhiteSpace(rule.FileFilter) ? "*" : rule.FileFilter.Trim(),
                    ExpirySeconds = rule.ExpirySeconds is > 0 ? rule.ExpirySeconds : null
                })
                .ToArray();

    private static IReadOnlyList<UploaderFilterRule> NormalizeUploaderFilters(IReadOnlyList<UploaderFilterRule>? rules) =>
        rules is null
            ? []
            : rules
                .Select(rule => rule.Normalized)
                .Where(rule => rule.Extensions.Count > 0 && !string.IsNullOrWhiteSpace(rule.ProfileId))
                .ToArray();
}








