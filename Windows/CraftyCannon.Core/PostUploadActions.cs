namespace CraftyCannon.Core;

public sealed record PasteTargetInfo(string? ApplicationName, string? BundleOrProcessName = null, string? WindowTitle = null);

public static class PasteTargetPolicy
{
    private static readonly HashSet<string> BrowserNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "safari",
        "chrome",
        "google chrome",
        "msedge",
        "edge",
        "arc",
        "brave",
        "firefox"
    };

    public static bool ShouldPasteUrlInsteadOfImage(PasteTargetInfo target)
    {
        var app = Normalize(target.ApplicationName);
        var process = Normalize(target.BundleOrProcessName);
        var title = Normalize(target.WindowTitle);

        if (app.Contains("discord", StringComparison.Ordinal) || process.Contains("discord", StringComparison.Ordinal))
        {
            return true;
        }

        if (IsBrowser(app, process) && title.Contains("discord", StringComparison.Ordinal))
        {
            return true;
        }

        return false;
    }

    private static bool IsBrowser(string app, string process) =>
        BrowserNames.Contains(app) ||
        BrowserNames.Contains(process) ||
        process.Contains("chrome", StringComparison.Ordinal) ||
        process.Contains("firefox", StringComparison.Ordinal) ||
        process.Contains("edge", StringComparison.Ordinal) ||
        process.Contains("brave", StringComparison.Ordinal);

    private static string Normalize(string? value) => value?.Trim().ToLowerInvariant() ?? string.Empty;
}

public sealed record AfterUploadTaskOptions(
    bool CopyImage = false,
    bool CopyUrl = true,
    bool OpenUrl = false);

public sealed record AfterCaptureTaskOptions(
    bool CopyImageAndUrl = true,
    bool CopyUrl = true,
    bool OpenEditor = false);

public enum PostUploadActionKind
{
    CopyImage,
    CopyText,
    OpenUrl,
    OpenEditor
}

public sealed record PostUploadAction(PostUploadActionKind Kind, string Value);

public static class PostUploadPlanner
{
    public static IReadOnlyList<PostUploadAction> Plan(
        UploadRecord record,
        string url,
        string? imagePath,
        AfterUploadTaskOptions afterUpload,
        AfterCaptureTaskOptions afterCapture,
        PasteTargetInfo pasteTarget,
        bool imageCopyWouldSucceed = true)
    {
        return record.SourceKind == UploadSourceKind.Capture
            ? PlanAfterCapture(record.Id, url, imagePath, afterCapture, pasteTarget, imageCopyWouldSucceed)
            : PlanAfterUpload(url, imagePath, afterUpload, pasteTarget, imageCopyWouldSucceed);
    }

    public static IReadOnlyList<PostUploadAction> PlanAfterUpload(
        string url,
        string? imagePath,
        AfterUploadTaskOptions options,
        PasteTargetInfo pasteTarget,
        bool imageCopyWouldSucceed = true)
    {
        var actions = new List<PostUploadAction>();
        if (options.CopyImage || options.CopyUrl)
        {
            if (options.CopyImage)
            {
                if (PasteTargetPolicy.ShouldPasteUrlInsteadOfImage(pasteTarget) || string.IsNullOrWhiteSpace(imagePath) || !imageCopyWouldSucceed)
                {
                    actions.Add(new PostUploadAction(PostUploadActionKind.CopyText, url));
                }
                else
                {
                    actions.Add(new PostUploadAction(PostUploadActionKind.CopyImage, imagePath));
                }
            }
            else if (options.CopyUrl)
            {
                actions.Add(new PostUploadAction(PostUploadActionKind.CopyText, url));
            }
        }

        if (options.OpenUrl)
        {
            actions.Add(new PostUploadAction(PostUploadActionKind.OpenUrl, url));
        }

        return actions;
    }

    public static IReadOnlyList<PostUploadAction> PlanAfterCapture(
        string recordId,
        string url,
        string? imagePath,
        AfterCaptureTaskOptions options,
        PasteTargetInfo pasteTarget,
        bool imageCopyWouldSucceed = true)
    {
        var actions = new List<PostUploadAction>();
        if (options.CopyImageAndUrl && !string.IsNullOrWhiteSpace(imagePath))
        {
            if (PasteTargetPolicy.ShouldPasteUrlInsteadOfImage(pasteTarget))
            {
                actions.Add(new PostUploadAction(PostUploadActionKind.CopyText, url));
            }
            else if (imageCopyWouldSucceed)
            {
                actions.Add(new PostUploadAction(PostUploadActionKind.CopyImage, imagePath));
            }
            else if (options.CopyUrl)
            {
                actions.Add(new PostUploadAction(PostUploadActionKind.CopyText, url));
            }
        }
        else if (options.CopyUrl)
        {
            actions.Add(new PostUploadAction(PostUploadActionKind.CopyText, url));
        }

        if (options.OpenEditor)
        {
            actions.Add(new PostUploadAction(PostUploadActionKind.OpenEditor, recordId));
        }

        return actions;
    }
}

public static class UploadHistoryActions
{
    private static readonly HashSet<string> EditableImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff", ".heic", ".heif"
    };

    public static string? PreferredUrl(UploadRecord record) =>
        !string.IsNullOrWhiteSpace(record.ShortenedUrl) ? record.ShortenedUrl : record.RemoteUrl;

    public static UploadRecord WithShortenedUrl(UploadRecord record, string shortenedUrl) =>
        record with { ShortenedUrl = shortenedUrl };

    public static bool CanEditImage(UploadRecord record) =>
        !string.IsNullOrWhiteSpace(record.LocalFilePath) &&
        record.RecordKind switch
        {
            UploadRecordKind.Image or UploadRecordKind.RemoteImage => true,
            UploadRecordKind.Unknown => EditableImageExtensions.Contains(Path.GetExtension(record.LocalFilePath)),
            _ => false
        };

    public static UploadRecord WithReuploadStarted(UploadRecord record) =>
        record with
        {
            Status = UploadStatus.Uploading,
            ErrorMessage = null,
            SourceKind = UploadSourceKind.Reupload
        };

    public static UploadRecord WithFailedReupload(UploadRecord record, string error) =>
        record with
        {
            Status = UploadStatus.Failed,
            ErrorMessage = error,
            SourceKind = UploadSourceKind.Reupload
        };
}

