namespace CraftyCannon.Core;

public sealed record WatchFolderCandidate(string RuleId, string FilePath, WatchFolderMode Mode, int? ExpirySeconds, bool IsImage);

public sealed class WatchFolderScanner
{
    public const int MaxKnownSignatures = 25_000;
    public static readonly TimeSpan StabilityDelay = TimeSpan.FromSeconds(1.5);
    public static readonly TimeSpan PendingRetention = TimeSpan.FromSeconds(120);

    private sealed record PendingObservation(string Signature, DateTimeOffset FirstSeenAt);

    private readonly Dictionary<string, string> knownSignatures = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<string> knownSignatureOrder = [];
    private readonly Dictionary<string, PendingObservation> pending = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> primedRules = new(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyList<WatchFolderCandidate> Scan(IEnumerable<WatchFolderRule> rules, DateTimeOffset now)
    {
        var activeRules = rules.Where(rule => rule.Enabled).ToArray();
        var ready = new List<WatchFolderCandidate>();
        foreach (var rule in activeRules)
        {
            if (string.IsNullOrWhiteSpace(rule.Path) || !Directory.Exists(rule.Path))
            {
                continue;
            }

            var root = NormalizePath(rule.Path);
            var isPrimed = primedRules.TryGetValue(rule.Id, out var primedPath) && string.Equals(primedPath, root, StringComparison.OrdinalIgnoreCase);
            foreach (var file in EnumerateCandidateFiles(root, rule.IncludeSubdirectories, rule.FileFilter))
            {
                var signature = SignatureFor(file);
                var observationKey = ObservationKey(rule.Id, file);
                if (!isPrimed)
                {
                    RecordKnown(signature, observationKey);
                    continue;
                }

                if (knownSignatures.TryGetValue(observationKey, out var known) && known == signature)
                {
                    continue;
                }

                if (pending.TryGetValue(observationKey, out var observed) && observed.Signature == signature)
                {
                    if (now - observed.FirstSeenAt >= StabilityDelay)
                    {
                        pending.Remove(observationKey);
                        RecordKnown(signature, observationKey);
                        ready.Add(new WatchFolderCandidate(rule.Id, file, rule.Mode, rule.ExpirySeconds, IsImageFile(file)));
                    }
                }
                else
                {
                    pending[observationKey] = new PendingObservation(signature, now);
                }
            }

            if (!isPrimed)
            {
                primedRules[rule.Id] = root;
            }
        }

        PrunePending(now);
        if (knownSignatures.Count > MaxKnownSignatures)
        {
            PruneKnown(activeRules);
        }

        return ready;
    }

    public void Reset()
    {
        pending.Clear();
        primedRules.Clear();
    }

    public static IReadOnlyList<string> EnumerateCandidateFiles(string folderPath, bool includeSubdirectories, string filter)
    {
        if (!Directory.Exists(folderPath))
        {
            return [];
        }

        var files = new List<string>();
        EnumerateInto(NormalizePath(folderPath), includeSubdirectories, filter, files);
        files.Sort(StringComparer.OrdinalIgnoreCase);
        return files;
    }

    public static bool MatchesFilter(string filePath, string filter)
    {
        var trimmed = (filter ?? string.Empty).Trim();
        if (trimmed.Length == 0 || trimmed == "*" || trimmed == "*.*")
        {
            return true;
        }

        var extension = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
        var parts = trimmed
            .Split([',', ';', ' '], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => part.Trim().Trim('*', '.', ' ').ToLowerInvariant())
            .Where(part => part.Length > 0)
            .ToArray();
        return parts.Length == 0 || parts.Contains(extension, StringComparer.OrdinalIgnoreCase);
    }

    public static bool IsImageFile(string filePath)
    {
        var extension = Path.GetExtension(filePath).TrimStart('.');
        return ImageExtensions.Contains(extension);
    }

    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif"
    };

    private static void EnumerateInto(string folderPath, bool includeSubdirectories, string filter, List<string> files)
    {
        if (IsHiddenOrSystem(folderPath))
        {
            return;
        }

        foreach (var file in Directory.EnumerateFiles(folderPath))
        {
            if (!IsHiddenOrSystem(file) && !IsTransientFile(file) && MatchesFilter(file, filter))
            {
                files.Add(NormalizePath(file));
            }
        }

        if (!includeSubdirectories)
        {
            return;
        }

        foreach (var directory in Directory.EnumerateDirectories(folderPath))
        {
            if (!IsHiddenOrSystem(directory))
            {
                EnumerateInto(directory, includeSubdirectories, filter, files);
            }
        }
    }

    private void PrunePending(DateTimeOffset now)
    {
        foreach (var key in pending.Where(entry => now - entry.Value.FirstSeenAt >= PendingRetention).Select(entry => entry.Key).ToArray())
        {
            pending.Remove(key);
        }
    }

    private void PruneKnown(IReadOnlyList<WatchFolderRule> activeRules)
    {
        var active = activeRules.ToDictionary(rule => rule.Id, rule => NormalizePath(rule.Path), StringComparer.OrdinalIgnoreCase);
        foreach (var key in knownSignatures.Keys.ToArray())
        {
            var separator = key.IndexOf('|');
            if (separator <= 0 || !active.TryGetValue(key[..separator], out var root) || !IsUnderRoot(key[(separator + 1)..], root))
            {
                knownSignatures.Remove(key);
            }
        }

        knownSignatureOrder.RemoveAll(key => !knownSignatures.ContainsKey(key));
        if (knownSignatures.Count <= MaxKnownSignatures)
        {
            return;
        }

        var removeCount = Math.Min(knownSignatures.Count / 2, knownSignatureOrder.Count);
        foreach (var key in knownSignatureOrder.Take(removeCount).ToArray())
        {
            knownSignatures.Remove(key);
        }
        knownSignatureOrder.RemoveRange(0, removeCount);
    }

    private void RecordKnown(string signature, string observationKey)
    {
        if (!knownSignatures.ContainsKey(observationKey))
        {
            knownSignatureOrder.Add(observationKey);
        }

        knownSignatures[observationKey] = signature;
    }

    private static string ObservationKey(string ruleId, string filePath) => ruleId + "|" + NormalizePath(filePath);

    private static string SignatureFor(string filePath)
    {
        var info = new FileInfo(filePath);
        return info.Length + ":" + new DateTimeOffset(info.LastWriteTimeUtc).ToUnixTimeSeconds();
    }

    private static string NormalizePath(string path) => Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

    private static bool IsUnderRoot(string filePath, string root)
    {
        var full = NormalizePath(filePath);
        var normalizedRoot = NormalizePath(root);
        return string.Equals(full, normalizedRoot, StringComparison.OrdinalIgnoreCase) ||
            full.StartsWith(normalizedRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
            full.StartsWith(normalizedRoot + Path.AltDirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsHiddenOrSystem(string path)
    {
        var name = Path.GetFileName(path);
        if (name.StartsWith(".", StringComparison.Ordinal))
        {
            return true;
        }

        var attributes = File.GetAttributes(path);
        return (attributes & (FileAttributes.Hidden | FileAttributes.System)) != 0;
    }

    private static bool IsTransientFile(string path)
    {
        var name = Path.GetFileName(path);
        if (name.StartsWith("~$", StringComparison.Ordinal))
        {
            return true;
        }

        var extension = Path.GetExtension(path);
        return extension.Equals(".tmp", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".temp", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".partial", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".crdownload", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".download", StringComparison.OrdinalIgnoreCase);
    }
}