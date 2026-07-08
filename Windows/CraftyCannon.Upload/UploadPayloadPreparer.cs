using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public enum UploadPayloadKind
{
    File,
    Image,
    Text,
    RemoteFile,
    RemoteImage,
    FolderIndex
}

public sealed record PreparedUploadPayload(
    string FilePath,
    UploadPayloadKind Kind,
    UploadSourceKind SourceKind,
    string? UploadContext = null,
    bool TemporarySourceFile = false,
    string? MimeType = null);

public sealed record PreparedFolderBatch(string BatchId, IReadOnlyList<PreparedUploadPayload> Payloads);

public sealed class UploadPayloadPreparationException : Exception
{
    public UploadPayloadPreparationException(string message) : base(message)
    {
    }
}

public sealed class UploadPayloadPreparer
{
    public const int DefaultMaxRemoteResponseBytes = 150 * 1024 * 1024;

    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif"
    };

    private readonly AppStoragePaths paths;
    private readonly IHttpTransport transport;
    private readonly int maxRemoteResponseBytes;

    public UploadPayloadPreparer(
        AppStoragePaths paths,
        IHttpTransport transport,
        int maxRemoteResponseBytes = DefaultMaxRemoteResponseBytes)
    {
        this.paths = paths;
        this.transport = transport;
        this.maxRemoteResponseBytes = maxRemoteResponseBytes;
    }

    public PreparedUploadPayload PrepareLocalFile(string filePath, UploadSourceKind sourceKind)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        var fullPath = Path.GetFullPath(filePath);
        if (!File.Exists(fullPath))
        {
            throw new UploadPayloadPreparationException("Local file not found.");
        }

        return new PreparedUploadPayload(
            fullPath,
            IsImageFile(fullPath, null) ? UploadPayloadKind.Image : UploadPayloadKind.File,
            sourceKind);
    }

    public async Task<PreparedUploadPayload> PrepareTextAsync(
        string text,
        UploadSourceKind sourceKind = UploadSourceKind.ClipboardText,
        CancellationToken cancellationToken = default)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            throw new UploadPayloadPreparationException("Text is empty.");
        }

        var directory = Path.Combine(paths.TempRoot, "TextUploads");
        Directory.CreateDirectory(directory);
        var filePath = Path.Combine(directory, $"text-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(filePath, trimmed, cancellationToken).ConfigureAwait(false);
        return new PreparedUploadPayload(
            filePath,
            UploadPayloadKind.Text,
            sourceKind,
            UploadContext: null,
            TemporarySourceFile: true,
            MimeType: "text/plain");
    }
    public PreparedFolderBatch PrepareFolderBatch(
        string folderPath,
        bool includeSubdirectories,
        UploadSourceKind sourceKind = UploadSourceKind.Folder,
        string? batchId = null)
    {
        var root = NormalizedDirectory(folderPath);
        var id = string.IsNullOrWhiteSpace(batchId) ? Guid.NewGuid().ToString() : batchId;
        var payloads = CollectFolderFiles(root, includeSubdirectories)
            .Select(file => new PreparedUploadPayload(
                file,
                IsImageFile(file, null) ? UploadPayloadKind.Image : UploadPayloadKind.File,
                sourceKind,
                UploadContext: "folder-batch"))
            .ToArray();
        return new PreparedFolderBatch(id, payloads);
    }

    public async Task<PreparedUploadPayload> PrepareFolderIndexAsync(
        string folderPath,
        bool includeSubdirectories,
        UploadSourceKind sourceKind = UploadSourceKind.ClipboardFolder,
        DateTimeOffset? generatedAt = null,
        CancellationToken cancellationToken = default)
    {
        var root = NormalizedDirectory(folderPath);
        Directory.CreateDirectory(paths.TempRoot);
        var safeName = Path.GetFileName(root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)).Replace(' ', '-');
        if (string.IsNullOrWhiteSpace(safeName))
        {
            safeName = "folder";
        }

        var filePath = Path.Combine(paths.TempRoot, $"{SafeFilenameComponent(safeName)}-index-{Guid.NewGuid().ToString("N")[..8]}.txt");
        var lines = BuildFolderIndexLines(root, includeSubdirectories, generatedAt ?? DateTimeOffset.UtcNow);
        await File.WriteAllTextAsync(filePath, string.Join(Environment.NewLine, lines), cancellationToken).ConfigureAwait(false);
        return new PreparedUploadPayload(
            filePath,
            UploadPayloadKind.FolderIndex,
            sourceKind,
            UploadContext: null,
            TemporarySourceFile: false,
            MimeType: "text/plain");
    }

    public async Task<PreparedUploadPayload> PrepareRemoteUrlAsync(
        string url,
        UploadSourceKind sourceKind = UploadSourceKind.ClipboardRemoteUrl,
        CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri))
        {
            throw new UploadPayloadPreparationException("URL is invalid.");
        }

        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new UploadPayloadPreparationException("Only HTTP and HTTPS URLs are supported.");
        }

        var response = await transport.SendAsync(new TransportRequest(
            HttpMethod.Get,
            uri,
            new Dictionary<string, string>(),
            Timeout: TimeSpan.FromSeconds(20)), cancellationToken).ConfigureAwait(false);

        if (response.StatusCode < 200 || response.StatusCode > 299)
        {
            throw new UploadPayloadPreparationException($"Remote server returned HTTP {response.StatusCode}.");
        }

        if (response.Headers.TryGetValue("Content-Length", out var lengthHeader) &&
            long.TryParse(lengthHeader.Trim(), out var expectedLength) &&
            expectedLength > maxRemoteResponseBytes)
        {
            throw new UploadPayloadPreparationException($"Remote content too large ({expectedLength} bytes).");
        }

        if (response.Body.Length == 0)
        {
            throw new UploadPayloadPreparationException("Remote URL returned no content.");
        }

        if (response.Body.Length > maxRemoteResponseBytes)
        {
            throw new UploadPayloadPreparationException($"Remote content too large ({response.Body.Length} bytes).");
        }

        var mimeType = MimeType(response.Headers);
        var fileName = RemoteFilename(uri, response.Headers, mimeType);
        var directory = Path.Combine(paths.TempRoot, "RemoteDownloads");
        Directory.CreateDirectory(directory);
        var filePath = Path.Combine(directory, $"{Path.GetFileNameWithoutExtension(fileName)}-{Guid.NewGuid():N}{Path.GetExtension(fileName)}");
        await File.WriteAllBytesAsync(filePath, response.Body, cancellationToken).ConfigureAwait(false);

        return new PreparedUploadPayload(
            filePath,
            IsImageFile(filePath, mimeType) ? UploadPayloadKind.RemoteImage : UploadPayloadKind.RemoteFile,
            sourceKind,
            UploadContext: "remote-url",
            TemporarySourceFile: true,
            MimeType: mimeType);
    }

    public static IReadOnlyList<string> BuildFolderIndexLines(string folderPath, bool includeSubdirectories, DateTimeOffset generatedAt)
    {
        var root = NormalizedDirectory(folderPath);
        var lines = new List<string>
        {
            "Folder index",
            $"Root: {root}",
            $"Generated: {generatedAt.UtcDateTime:yyyy-MM-dd'T'HH:mm:ss'Z'}",
            string.Empty
        };

        var files = new List<string>();
        CollectFolderFiles(root, includeSubdirectories, files);
        foreach (var file in files)
        {
            var relative = Path.GetRelativePath(root, file).Replace(Path.DirectorySeparatorChar, '/').Replace(Path.AltDirectorySeparatorChar, '/');
            var size = new FileInfo(file).Length;
            lines.Add($"- {relative} ({size} bytes)");
        }

        if (lines.Count == 4)
        {
            lines.Add("(no files found)");
        }

        return lines;
    }

    public static IReadOnlyList<string> CollectFolderFiles(string folderPath, bool includeSubdirectories)
    {
        var root = NormalizedDirectory(folderPath);
        var files = new List<string>();
        CollectFolderFiles(root, includeSubdirectories, files);
        files.Sort(StringComparer.Ordinal);
        return files;
    }
    public static bool IsImageFile(string filePath, string? mimeType)
    {
        var extension = Path.GetExtension(filePath).TrimStart('.');
        if (ImageExtensions.Contains(extension))
        {
            return true;
        }

        return mimeType?.Trim().StartsWith("image/", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static void CollectFolderFiles(string directory, bool includeSubdirectories, List<string> files)
    {
        foreach (var file in Directory.EnumerateFiles(directory))
        {
            if (!IsHidden(file))
            {
                files.Add(Path.GetFullPath(file));
            }
        }

        if (!includeSubdirectories)
        {
            return;
        }

        foreach (var child in Directory.EnumerateDirectories(directory))
        {
            if (!IsHidden(child))
            {
                CollectFolderFiles(child, includeSubdirectories, files);
            }
        }
    }

    private static string NormalizedDirectory(string folderPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(folderPath);
        var root = Path.GetFullPath(folderPath);
        if (!Directory.Exists(root))
        {
            throw new UploadPayloadPreparationException("Folder not found.");
        }

        return root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static bool IsHidden(string path)
    {
        var name = Path.GetFileName(path);
        if (name.StartsWith(".", StringComparison.Ordinal))
        {
            return true;
        }

        return (File.GetAttributes(path) & FileAttributes.Hidden) == FileAttributes.Hidden;
    }
    private static string? MimeType(IReadOnlyDictionary<string, string> headers)
    {
        if (!headers.TryGetValue("Content-Type", out var raw) || string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        return raw.Split(';', 2)[0].Trim();
    }

    private static string RemoteFilename(Uri uri, IReadOnlyDictionary<string, string> headers, string? mimeType)
    {
        var suggested = ContentDispositionFilename(headers) ?? Uri.UnescapeDataString(Path.GetFileName(uri.LocalPath));
        var safe = SafeFilenameComponent(string.IsNullOrWhiteSpace(suggested) ? "remote-file" : suggested);
        var extension = Path.GetExtension(safe).TrimStart('.');
        if (extension.Length == 0)
        {
            safe = Path.GetFileNameWithoutExtension(safe) + "." + MimeExtension(mimeType);
        }

        return safe;
    }

    private static string? ContentDispositionFilename(IReadOnlyDictionary<string, string> headers)
    {
        if (!headers.TryGetValue("Content-Disposition", out var raw))
        {
            return null;
        }

        foreach (var part in raw.Split(';'))
        {
            var trimmed = part.Trim();
            if (trimmed.StartsWith("filename=", StringComparison.OrdinalIgnoreCase))
            {
                return trimmed["filename=".Length..].Trim().Trim('"');
            }
        }

        return null;
    }

    private static string MimeExtension(string? mimeType) => mimeType?.ToLowerInvariant() switch
    {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "image/bmp" => "bmp",
        "text/plain" => "txt",
        "application/json" => "json",
        "text/html" => "html",
        _ => "bin"
    };

    private static string SafeFilenameComponent(string raw)
    {
        var value = raw.Trim();
        if (value.Length == 0)
        {
            value = "remote-file";
        }

        foreach (var invalid in Path.GetInvalidFileNameChars().Concat(['/', '\\']))
        {
            value = value.Replace(invalid.ToString(), "-");
        }

        return value;
    }
}




