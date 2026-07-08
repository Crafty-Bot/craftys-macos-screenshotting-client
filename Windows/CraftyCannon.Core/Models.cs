using System.Text.Json.Serialization;
namespace CraftyCannon.Core;

public enum UploadBackend
{
    ZiplineV4,
    S3Compatible
}

public enum ImageUploadFormat
{
    Png,
    Jpeg,
    Gif,
    Tiff
}
public enum OnboardingState
{
    Pending,
    Completed
}

public enum UploadStatus
{
    Uploading,
    Uploaded,
    Failed,
    Cancelled
}

public enum UploadSourceKind
{
    Capture,
    Clipboard,
    ClipboardImage,
    ClipboardFile,
    ClipboardFolder,
    ClipboardRemoteUrl,
    ClipboardText,
    ManualFile,
    ManualRemoteUrl,
    ManualText,
    ManualFolderBatch,
    ManualFolderIndex,
    UrlShorten,
    File,
    Folder,
    Url,
    Text,
    WatchFolder,
    Reupload,
    EditorSave
}

public enum UploadRecordKind
{
    Unknown,
    Image,
    File,
    Text,
    RemoteFile,
    RemoteImage,
    FolderIndex
}

public enum UploadOperationKind
{
    Unknown,
    ImageUpload,
    FileUpload,
    TextUpload,
    FolderIndexUpload,
    UrlShorten
}

public enum DestinationKind
{
    Image,
    File,
    Text,
    Shortener
}

public enum SecondaryUploadStatus
{
    NotConfigured,
    Pending,
    Uploaded,
    Failed,
    Skipped
}

public enum OcrIndexStatus
{
    NotQueued,
    Pending,
    Indexed,
    Failed,
    LocalImageMissing,
    Disabled,
    Skipped
}


public enum GlobalHotKeyAction
{
    CaptureRegionUpload,
    CaptureRegionUploadExpiring,
    CaptureRegionUploadFrozen,
    UploadClipboard
}

public sealed record HotKeyShortcut(
    string Key,
    bool Control = false,
    bool Shift = false,
    bool Alt = false,
    bool Windows = false)
{
    public static IReadOnlyList<string> AllowedKeys { get; } =
        Enumerable.Range('A', 26)
            .Select(value => ((char)value).ToString())
            .Concat(Enumerable.Range(0, 10).Select(value => value.ToString()))
            .ToArray();

    private static HashSet<string> AllowedKeySet { get; } = new(AllowedKeys, StringComparer.OrdinalIgnoreCase);

    [JsonIgnore]
    public HotKeyShortcut Normalized
    {
        get
        {
            var key = NormalizeKey(Key);
            return Control || Shift || Alt || Windows
                ? this with { Key = key }
                : this with { Key = key, Control = true };
        }
    }

    [JsonIgnore]
    public string DisplayText
    {
        get
        {
            var normalized = Normalized;
            var parts = new List<string>();
            if (normalized.Control) parts.Add("Ctrl");
            if (normalized.Shift) parts.Add("Shift");
            if (normalized.Alt) parts.Add("Alt");
            if (normalized.Windows) parts.Add("Win");
            parts.Add(normalized.Key);
            return string.Join("+", parts);
        }
    }

    public static string NormalizeKey(string? raw)
    {
        var candidate = string.IsNullOrWhiteSpace(raw) ? string.Empty : raw.Trim().ToUpperInvariant()[..1];
        return AllowedKeySet.Contains(candidate) ? candidate : "G";
    }
}

public sealed record HotKeyBindings(
    HotKeyShortcut CaptureRegionUpload,
    HotKeyShortcut CaptureRegionUploadExpiring,
    HotKeyShortcut CaptureRegionUploadFrozen,
    HotKeyShortcut UploadClipboard)
{
    public static HotKeyBindings Defaults { get; } = new(
        new HotKeyShortcut("G", Control: true),
        new HotKeyShortcut("G", Control: true, Shift: true),
        new HotKeyShortcut("P", Control: true, Shift: true),
        new HotKeyShortcut("7", Control: true, Shift: true));

    [JsonIgnore]
    public HotKeyBindings Normalized => new(
        (CaptureRegionUpload ?? Defaults.CaptureRegionUpload).Normalized,
        (CaptureRegionUploadExpiring ?? Defaults.CaptureRegionUploadExpiring).Normalized,
        (CaptureRegionUploadFrozen ?? Defaults.CaptureRegionUploadFrozen).Normalized,
        (UploadClipboard ?? Defaults.UploadClipboard).Normalized);

    public HotKeyShortcut ShortcutFor(GlobalHotKeyAction action) => action switch
    {
        GlobalHotKeyAction.CaptureRegionUpload => CaptureRegionUpload,
        GlobalHotKeyAction.CaptureRegionUploadExpiring => CaptureRegionUploadExpiring,
        GlobalHotKeyAction.CaptureRegionUploadFrozen => CaptureRegionUploadFrozen,
        GlobalHotKeyAction.UploadClipboard => UploadClipboard,
        _ => throw new ArgumentOutOfRangeException(nameof(action))
    };
}

public enum CaptureMode
{
    Region,
    FrozenRegion,
    Window,
    FullScreen,
    TopTaskbar,
    FixedRegion,
    ScreenRecording
}

public enum UploadRedactionPolicy
{
    Off,
    AskBeforeUpload,
    AutoRedact
}

public enum SmartRedactionRenderMode
{
    Pixelate,
    BlackBox
}

public sealed record S3DestinationConfig(
    string Endpoint,
    string Region,
    string Bucket,
    string KeyPrefix,
    bool UsePathStyle,
    string? PublicBaseUrl,
    bool UseSignedGetUrls,
    TimeSpan SignedGetUrlExpiry);

public sealed record UploadProfile(
    string Id,
    string Name,
    string Endpoint,
    UploadBackend Backend,
    S3DestinationConfig? S3Config,
    string? SecondaryS3ProfileId)
{
    public static UploadProfile Unconfigured { get; } = new(
        "unconfigured",
        "Unconfigured",
        string.Empty,
        UploadBackend.ZiplineV4,
        null,
        null);
}

public sealed record UploadRecord(
    string Id,
    UploadStatus Status,
    DateTimeOffset CreatedAt,
    string FileName,
    string? LocalFilePath,
    string? RemoteUrl,
    string? ProfileName,
    string? ErrorMessage,
    UploadSourceKind SourceKind = UploadSourceKind.File,
    string? BatchId = null,
    string? RemotePath = null,
    DateTimeOffset? ExpiresAt = null,
    bool IsManagedLocalCopy = false,
    string? ShortenedUrl = null,
    SecondaryUploadStatus SecondaryStatus = SecondaryUploadStatus.NotConfigured,
    string? SecondaryUrl = null,
    string? SecondaryPath = null,
    string? SecondaryError = null,
    DateTimeOffset? SecondaryCompletedAt = null,
    OcrIndexStatus OcrStatus = OcrIndexStatus.NotQueued,
    string? OcrText = null,
    string? OcrEngine = null,
    string? OcrEngineVersion = null,
    DateTimeOffset? OcrIndexedAt = null,
    long? OcrFileSize = null,
    DateTimeOffset? OcrFileModifiedAt = null,
    string? OcrError = null,
    int? OcrRetryCount = null,
    UploadRecordKind RecordKind = UploadRecordKind.Unknown,
    UploadOperationKind OperationKind = UploadOperationKind.Unknown);

public enum WatchFolderMode
{
    Auto,
    ImageOnly,
    FileOnly
}

public sealed record WatchFolderRule(
    string Id,
    string Path,
    bool IncludeSubdirectories = true,
    string FileFilter = "*",
    WatchFolderMode Mode = WatchFolderMode.Auto,
    int? ExpirySeconds = null,
    bool Enabled = true)
{
    public static WatchFolderRule Create(string path) => new(Guid.NewGuid().ToString("N"), path);
}

public sealed record UploaderFilterRule(
    string Id,
    IReadOnlyList<string> Extensions,
    string ProfileId)
{
    [JsonIgnore]
    public UploaderFilterRule Normalized => new(
        string.IsNullOrWhiteSpace(Id) ? Guid.NewGuid().ToString("N") : Id,
        NormalizeExtensions(Extensions),
        ProfileId?.Trim() ?? string.Empty);

    public bool Matches(string? fileExtension)
    {
        var normalized = NormalizeExtension(fileExtension);
        return !string.IsNullOrWhiteSpace(normalized) && Extensions.Contains(normalized, StringComparer.OrdinalIgnoreCase);
    }

    public static IReadOnlyList<string> NormalizeExtensions(IEnumerable<string>? raw)
    {
        if (raw is null)
        {
            return [];
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>();
        foreach (var item in raw)
        {
            var ext = NormalizeExtension(item);
            if (string.IsNullOrWhiteSpace(ext) || !seen.Add(ext))
            {
                continue;
            }

            result.Add(ext);
        }

        return result;
    }

    private static string NormalizeExtension(string? raw) => (raw ?? string.Empty).Trim(' ', '.').ToLowerInvariant();
}

public sealed record DestinationRoutingConfig(
    string? ImageProfileId = null,
    string? FileProfileId = null,
    string? TextProfileId = null,
    string? ShortenerProfileId = null)
{
    public string? ProfileIdFor(DestinationKind kind) => kind switch
    {
        DestinationKind.Image => ImageProfileId,
        DestinationKind.File => FileProfileId,
        DestinationKind.Text => TextProfileId,
        DestinationKind.Shortener => ShortenerProfileId,
        _ => null
    };

    [JsonIgnore]
    public DestinationRoutingConfig Normalized => new(
        NormalizeId(ImageProfileId),
        NormalizeId(FileProfileId),
        NormalizeId(TextProfileId),
        NormalizeId(ShortenerProfileId));

    private static string? NormalizeId(string? id) => string.IsNullOrWhiteSpace(id) ? null : id.Trim();
}

public sealed record CloudflareAllowlistConfig(
    bool Enabled = false,
    string AccountId = "",
    string ListId = "",
    string DeviceName = "",
    int CheckIntervalMinutes = 15)
{
    [JsonIgnore]
    public CloudflareAllowlistConfig Normalized => new(
        Enabled,
        AccountId?.Trim() ?? string.Empty,
        ListId?.Trim() ?? string.Empty,
        string.IsNullOrWhiteSpace(DeviceName) ? Environment.MachineName : DeviceName.Trim(),
        NormalizeInterval(CheckIntervalMinutes));

    public static int NormalizeInterval(int minutes) => Math.Clamp(minutes, 5, 24 * 60);
}
public readonly record struct CaptureSnapSize(int Width, int Height)
{
    [JsonIgnore]
    public bool IsValid => Width > 0 && Height > 0;

    public static IReadOnlyList<CaptureSnapSize> NormalizeList(IEnumerable<CaptureSnapSize>? values)
    {
        if (values is null)
        {
            return [];
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<CaptureSnapSize>();
        foreach (var value in values)
        {
            if (!value.IsValid)
            {
                continue;
            }

            var key = $"{value.Width}x{value.Height}";
            if (seen.Add(key))
            {
                result.Add(value);
            }
        }

        return result;
    }

    public static IReadOnlyList<CaptureSnapSize> ParseList(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return [];
        }

        var values = new List<CaptureSnapSize>();
        foreach (var part in raw.Split([',', ';', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var pieces = part.ToLowerInvariant().Split('x', 2, StringSplitOptions.TrimEntries);
            if (pieces.Length != 2
                || !int.TryParse(pieces[0], out var width)
                || !int.TryParse(pieces[1], out var height)
                || width <= 0
                || height <= 0)
            {
                continue;
            }

            values.Add(new CaptureSnapSize(width, height));
        }

        return NormalizeList(values);
    }

    public static string FormatList(IEnumerable<CaptureSnapSize>? values) =>
        string.Join(", ", NormalizeList(values).Select(value => $"{value.Width}x{value.Height}"));
}
public sealed record SmartRedactionDetectorPreferences(
    bool Face = true,
    bool Barcode = true,
    double MinimumConfidence = 0.20,
    bool UseFastTextRecognition = false,
    bool AllowSensitiveTextPreviews = false)
{
    public static SmartRedactionDetectorPreferences Default { get; } = new();

    [JsonIgnore]
    public SmartRedactionDetectorPreferences Normalized => this with
    {
        MinimumConfidence = Math.Clamp(double.IsNaN(MinimumConfidence) ? Default.MinimumConfidence : MinimumConfidence, 0, 1)
    };
}
public sealed record RuntimePreferencesSnapshot(
    UploadRedactionPolicy RedactionPolicy,
    bool CopyUrlAfterUpload,
    bool CopyImageAfterUpload,
    bool OpenUrlAfterUpload,
    bool OpenEditorAfterCapture,
    bool EnableOcrIndexing,
    string ActivePaletteId,
    UiPaletteData? CustomPalette,
    string ShortenerProvider,
    string ShortenerCustomGetTemplate,
    bool UrlRegexReplaceEnabled,
    string UrlRegexPattern,
    string UrlRegexReplacement,
    SmartRedactionRenderMode SmartRedactionRenderMode,
    bool ShowNotificationAfterUpload = true,
    bool CaptureIncludeCursor = false,
    int CaptureDelaySeconds = 0,
    bool CaptureFixedRegionEnabled = false,
    int CaptureFixedRegionX = 0,
    int CaptureFixedRegionY = 0,
    int CaptureFixedRegionWidth = 1280,
    int CaptureFixedRegionHeight = 720,
    bool CaptureShowInfoOverlay = true,
    IReadOnlyList<CaptureSnapSize>? CaptureSnapSizes = null,
    bool CaptureMirrorToScreenshotsFolder = false,
    string CaptureScreenshotsFolder = "",
    bool WatchFoldersEnabled = false,
    IReadOnlyList<WatchFolderRule>? WatchFolderRules = null,
    HotKeyBindings? HotKeys = null,
    IReadOnlyList<UploaderFilterRule>? UploaderFilters = null,
    DestinationRoutingConfig? DestinationRouting = null,
    CloudflareAllowlistConfig? CloudflareAllowlist = null,
    ClipboardUploadRules? ClipboardRules = null,
    bool AfterCaptureCopyImageAndUrl = false,
    bool AfterCaptureCopyUrl = true,
    int DefaultFileExpirySeconds = 86400,
    bool StripImageMetadataBeforeUpload = false,
    ImageUploadFormat ImageUploadFormat = ImageUploadFormat.Png,
    bool FileUploadUseNamePattern = false,
    bool FileUploadUseRandom16Name = false,
    string FileNamePattern = "{date}-{rand}",
    int FileNameAutoIncrement = 1,
    bool FileUploadReplaceProblematicCharacters = true,
    OnboardingState OnboardingState = OnboardingState.Pending,
    SmartRedactionDetectorPreferences? SmartRedactionDetectors = null);














