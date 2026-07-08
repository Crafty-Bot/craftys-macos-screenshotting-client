namespace CraftyCannon.Core;

public sealed class TempFileGuard
{
    private readonly string tempRoot;
    private readonly string localRoot;

    public TempFileGuard(AppStoragePaths paths)
    {
        tempRoot = NormalizeDirectory(paths.TempRoot);
        localRoot = NormalizeDirectory(paths.LocalRoot);
    }

    public bool IsSafeToDelete(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        try
        {
            var fullPath = Path.GetFullPath(path);
            return IsSafeUnderRoot(fullPath, tempRoot) || IsSafeUnderRoot(fullPath, localRoot);
        }
        catch
        {
            return false;
        }
    }

    public void DeleteFileIfSafe(string path)
    {
        if (!IsSafeToDelete(path))
        {
            throw new InvalidOperationException($"Refusing to delete a path outside CraftyCannon-managed roots: {path}");
        }

        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }

    private static bool IsSafeUnderRoot(string fullPath, string root) =>
        IsUnderRoot(fullPath, root) && !HasReparsePointInExistingPath(fullPath, root);

    private static bool IsUnderRoot(string fullPath, string root) =>
        fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase);

    private static bool HasReparsePointInExistingPath(string fullPath, string root)
    {
        var current = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (HasReparsePoint(current))
        {
            return true;
        }

        var relative = Path.GetRelativePath(root, fullPath);
        if (relative.StartsWith("..", StringComparison.Ordinal) || Path.IsPathRooted(relative))
        {
            return true;
        }

        foreach (var segment in relative.Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, segment);
            if (!File.Exists(current) && !Directory.Exists(current))
            {
                continue;
            }

            if (HasReparsePoint(current))
            {
                return true;
            }
        }

        return false;
    }

    private static bool HasReparsePoint(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch
        {
            return true;
        }
    }

    private static string NormalizeDirectory(string path)
    {
        var fullPath = Path.GetFullPath(path);
        return fullPath.EndsWith(Path.DirectorySeparatorChar)
            ? fullPath
            : fullPath + Path.DirectorySeparatorChar;
    }
}
