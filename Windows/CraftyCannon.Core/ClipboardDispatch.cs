namespace CraftyCannon.Core;

public sealed record ClipboardUploadRules(
    bool ShortenUrl = false,
    bool UploadUrlContents = true,
    bool ShareUrlAfterUpload = false,
    bool UploadTextContents = false,
    bool AutoIndexFolder = false);

public sealed record ClipboardFileItem(string Path, bool IsDirectory);

public sealed record ClipboardSnapshot(
    bool HasImage,
    string? ImagePath,
    IReadOnlyList<ClipboardFileItem> Files,
    string? Text)
{
    public static ClipboardSnapshot Empty { get; } = new(false, null, [], null);
}

public enum ClipboardDispatchActionKind
{
    UploadImage,
    UploadFile,
    IndexFolder,
    UploadRemoteUrl,
    UploadText,
    ShortenUrl,
    CopyUrlOnly,
    Unsupported
}

public sealed record ClipboardDispatchResult(
    ClipboardDispatchActionKind Kind,
    UploadSourceKind SourceKind,
    string? Value = null);

public static class ClipboardUploadDispatcher
{
    public static ClipboardDispatchResult Resolve(ClipboardSnapshot snapshot, ClipboardUploadRules rules)
    {
        if (snapshot.HasImage)
        {
            return new ClipboardDispatchResult(
                ClipboardDispatchActionKind.UploadImage,
                UploadSourceKind.ClipboardImage,
                snapshot.ImagePath);
        }

        var file = snapshot.Files.FirstOrDefault();
        if (file is not null)
        {
            if (file.IsDirectory)
            {
                return rules.AutoIndexFolder
                    ? new ClipboardDispatchResult(ClipboardDispatchActionKind.IndexFolder, UploadSourceKind.ClipboardFolder, file.Path)
                    : Unsupported;
            }

            return new ClipboardDispatchResult(ClipboardDispatchActionKind.UploadFile, UploadSourceKind.ClipboardFile, file.Path);
        }

        var text = snapshot.Text?.Trim();
        if (!string.IsNullOrEmpty(text))
        {
            if (IsHttpUrl(text))
            {
                if (rules.ShortenUrl)
                {
                    return new ClipboardDispatchResult(ClipboardDispatchActionKind.ShortenUrl, UploadSourceKind.ClipboardRemoteUrl, text);
                }

                if (rules.UploadUrlContents)
                {
                    return new ClipboardDispatchResult(ClipboardDispatchActionKind.UploadRemoteUrl, UploadSourceKind.ClipboardRemoteUrl, text);
                }

                if (rules.ShareUrlAfterUpload)
                {
                    return new ClipboardDispatchResult(ClipboardDispatchActionKind.CopyUrlOnly, UploadSourceKind.ClipboardRemoteUrl, text);
                }

                return Unsupported;
            }

            if (rules.UploadTextContents)
            {
                return new ClipboardDispatchResult(ClipboardDispatchActionKind.UploadText, UploadSourceKind.ClipboardText, text);
            }
        }

        return Unsupported;
    }

    private static ClipboardDispatchResult Unsupported { get; } = new(
        ClipboardDispatchActionKind.Unsupported,
        UploadSourceKind.Clipboard);

    private static bool IsHttpUrl(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
        (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);
}


