namespace CraftyCannon.Core;

public class AppStoragePaths
{
    public AppStoragePaths(string appName = "CraftyCannon")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(appName);
        RoamingRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), appName);
        LocalRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), appName);
        HistoryPath = Path.Combine(LocalRoot, "upload-history.json");
        ProfilesPath = Path.Combine(RoamingRoot, "profiles.json");
        ProfileBackupPath = Path.Combine(RoamingRoot, "profiles.config.json");
        ImagesDirectory = Path.Combine(LocalRoot, "Images");
        TempRoot = Path.Combine(Path.GetTempPath(), appName);
        ScreenshotsFallbackDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "images");
    }

    public string RoamingRoot { get; protected set; }

    public string LocalRoot { get; protected set; }

    public string HistoryPath { get; protected set; }

    public string ProfilesPath { get; protected set; }

    public string ProfileBackupPath { get; protected set; }

    public string ImagesDirectory { get; protected set; }

    public string TempRoot { get; protected set; }

    public string ScreenshotsFallbackDirectory { get; protected set; }

    public void EnsureCreated()
    {
        Directory.CreateDirectory(RoamingRoot);
        Directory.CreateDirectory(LocalRoot);
        Directory.CreateDirectory(ImagesDirectory);
        Directory.CreateDirectory(TempRoot);
    }

    public static string NormalizeUserDirectory(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var expanded = Environment.ExpandEnvironmentVariables(path.Trim());
        return Path.GetFullPath(expanded);
    }
}
