using System.Windows;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using WpfColor = System.Windows.Media.Color;
using WpfSolidColorBrush = System.Windows.Media.SolidColorBrush;
using CraftyCannon.Core;
using CraftyCannon.Capture;
using CraftyCannon.Ocr;
using CraftyCannon.Security;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public partial class App : System.Windows.Application
{
    private const int DefaultFileExpirySeconds = 86_400;

    private System.Windows.Forms.NotifyIcon? trayIcon;
    private readonly Dictionary<string, System.Windows.Forms.ToolStripMenuItem> paletteMenuItems = new(StringComparer.OrdinalIgnoreCase);
    private System.Windows.Forms.ToolStripMenuItem? copyUrlAfterUploadMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? copyImageAfterUploadMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? openUrlAfterUploadMenuItem;
    private System.Windows.Forms.ToolStripMenuItem? showCursorMenuItem;
    private readonly Dictionary<int, System.Windows.Forms.ToolStripMenuItem> captureDelayMenuItems = new();
    private MainWindow? mainWindow;
    private MainWindowViewModel? viewModel;
    private AppStoragePaths? paths;
    private IClipboardService? clipboard;
    private JsonProfileStore? profileStore;
    private RuntimePreferencesStore? preferencesStore;
    private JsonUploadHistoryStore? historyStore;
    private UploadWorkflowService? uploadWorkflow;
    private WindowsWatchFolderManager? watchFolderManager;
    private WindowsCloudflareAllowlistManager? cloudflareAllowlistManager;
    private GlobalHotKeyManager? hotKeyManager;
    private IScreenCaptureService? screenCapture;
    private IFileRevealLauncher? fileRevealLauncher;
    private IEditorLauncher? editorLauncher;
    private HashCheckerWindow? hashCheckerWindow;
    private DirectoryIndexerWindow? directoryIndexerWindow;
    private QrCodeWindow? qrCodeWindow;
    private ColorPickerWindow? colorPickerWindow;
    private readonly Dictionary<string, PinnedImageWindow> pinnedImageWindows = new();
    private Task? initializationTask;

    private static readonly HashSet<string> HistoryImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff", ".heic", ".heif"
    };

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (RunOcrAdminCommandIfNeeded(e.Args))
        {
            Shutdown();
            return;
        }

        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        paths = new AppStoragePaths();
        paths.EnsureCreated();
        ApplyPaletteResources(RuntimePreferencesStore.Defaults);
        clipboard = new WpfClipboardService(paths);
        viewModel = new MainWindowViewModel { StatusText = "Loading profiles and preferences..." };
        mainWindow = new MainWindow(viewModel);
        ConfigureTrayIcon();
        mainWindow.Show();
        initializationTask = InitializeServicesAsync();
    }

    private static bool RunOcrAdminCommandIfNeeded(string[] arguments)
    {
        if (!OcrAdminCommands.IsSupported(arguments))
        {
            return false;
        }

        var adminPaths = new AppStoragePaths();
        adminPaths.EnsureCreated();
        var preferences = new RuntimePreferencesStore(adminPaths);
        var history = new JsonUploadHistoryStore(adminPaths);
        Task.WhenAll(preferences.LoadAsync(), history.LoadAsync()).GetAwaiter().GetResult();
        var indexer = new OcrIndexingService(history, CreateOcrTextRecognizer(), enabledProvider: () => preferences.Current.EnableOcrIndexing);
        OcrAdminCommands.RunIfNeededAsync(
            arguments,
            indexer,
            history,
            preferences.Current.EnableOcrIndexing,
            Console.Out).GetAwaiter().GetResult();
        return true;
    }

    private static IOcrTextRecognizer CreateOcrTextRecognizer() => new WindowsOcrTextRecognizer();

    protected override void OnExit(ExitEventArgs e)
    {
        cloudflareAllowlistManager?.Dispose();
        hotKeyManager?.Dispose();
        trayIcon?.Dispose();
        base.OnExit(e);
    }

    private async Task InitializeServicesAsync()
    {
        if (paths is null || clipboard is null)
        {
            return;
        }

        try
        {
            var secrets = new WindowsCredentialStore();
            profileStore = new JsonProfileStore(paths, secrets);
            preferencesStore = new RuntimePreferencesStore(paths);
            historyStore = new JsonUploadHistoryStore(paths);
            await Task.WhenAll(
                profileStore.LoadAsync(),
                preferencesStore.LoadAsync(),
                historyStore.LoadAsync()).ConfigureAwait(false);
            await Current.Dispatcher.InvokeAsync(() => ApplyPaletteResources(preferencesStore.Current));

            var transport = new HttpClientTransport();
            await RunOnboardingIfNeededAsync(transport).ConfigureAwait(false);
            var orchestrator = new UploadOrchestrator(new ZiplineClient(transport), new S3Client(transport), historyStore);
            screenCapture = new WindowsScreenCaptureService();
            fileRevealLauncher = new WindowsFileRevealLauncher();
            var smartRedactionDetector = new WindowsSmartRedactionDetector(settingsProvider: () => preferencesStore?.Current.SmartRedactionDetectors?.Normalized ?? SmartRedactionDetectorPreferences.Default);
            editorLauncher = new WindowsHistoryEditorLauncher(
                historyStore,
                paths.TempRoot,
                () => mainWindow,
                SaveEditorExportFromWindowAsync,
                screenCapture,
                smartRedactionDetector: smartRedactionDetector,
                redactionRenderModeProvider: () => preferencesStore?.Current.SmartRedactionRenderMode ?? RuntimePreferencesStore.Defaults.SmartRedactionRenderMode,
                notify: NotifyToolAction);
            var ocrIndexing = new OcrIndexingService(historyStore, CreateOcrTextRecognizer(), enabledProvider: () => preferencesStore?.Current.EnableOcrIndexing == true);
            uploadWorkflow = new UploadWorkflowService(
                new UploadPayloadPreparer(paths, transport),
                orchestrator,
                new URLShortenerClient(transport),
                new PostUploadActionExecutor(clipboard, new WindowsShellLauncher(), editorLauncher),
                new TempFileGuard(paths),
                ocrIndexing,
                new WindowsUploadRedactionService(paths, smartRedactionDetector),
                new WindowsImageUploadPreprocessor(paths));
            watchFolderManager = new WindowsWatchFolderManager(
                preferencesStore,
                () => BuildWorkflowOptions(showBlockingAlert: false),
                () => uploadWorkflow,
                SetStatus,
                outcome => NotifyUploadOutcome(outcome, showBlockingAlert: false),
                NotifyUploadFailure,
                RefreshHistoryView);
            watchFolderManager.ApplyCurrentPreferences();
            cloudflareAllowlistManager = new WindowsCloudflareAllowlistManager(
                paths,
                preferencesStore,
                secrets,
                new CloudflareAllowlistClient(transport),
                SetStatus);
            cloudflareAllowlistManager.ApplyCurrentPreferences();
            hotKeyManager = new GlobalHotKeyManager(action => Current.Dispatcher.Invoke(() => _ = ExecuteHotKeyActionAsync(action)));
            hotKeyManager.ApplyBindings(preferencesStore.Current.HotKeys ?? HotKeyBindings.Defaults);
            Current.Dispatcher.Invoke(RefreshTrayPreferenceMenuState);

            SetStatus(profileStore.ActiveProfile == UploadProfile.Unconfigured
                ? "No upload profile configured. Add a profile in Preferences before uploading."
                : $"Ready. Active profile: {profileStore.ActiveProfile.Name}");
            RefreshHistoryView();
        }
        catch (Exception ex)
        {
            SetStatus("Startup failed: " + ex.Message);
        }
    }

    private void ConfigureTrayIcon()
    {
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Open the GUI", null, (_, _) => ShowMainWindow());
        menu.Items.Add("Open History Workspace", null, (_, _) => _ = OpenHistoryWorkspaceFromWindowAsync());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("Capture Region + Upload", null, (_, _) => _ = CaptureRegionFromWindowAsync());
        menu.Items.Add("Capture Region + Expiring Upload", null, (_, _) => _ = CaptureRegionExpiringFromWindowAsync());
        menu.Items.Add("Capture Frozen Region + Upload", null, (_, _) => _ = CaptureFrozenRegionFromWindowAsync());
        menu.Items.Add("Capture Window + Upload", null, (_, _) => _ = CaptureWindowFromWindowAsync());
        menu.Items.Add("Capture Full Screen + Upload", null, (_, _) => _ = CaptureFullScreenFromWindowAsync());
        menu.Items.Add("Capture Top Taskbar + Upload", null, (_, _) => _ = CaptureTopTaskbarFromWindowAsync());
        menu.Items.Add("Record Screen (Max 30s) + Upload", null, (_, _) => _ = CaptureScreenRecordingFromWindowAsync());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(BuildCaptureOptionsMenu());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("Upload Clipboard Image", null, (_, _) => _ = UploadClipboardFromWindowAsync());
        menu.Items.Add("Upload Image File...", null, (_, _) => _ = UploadFileFromWindowAsync());
        menu.Items.Add("Upload File (Expiring Link)...", null, (_, _) => _ = UploadExpiringFileFromWindowAsync());
        menu.Items.Add("Upload from URL...", null, (_, _) => _ = UploadRemoteUrlFromWindowAsync());
        menu.Items.Add("Upload Text...", null, (_, _) => _ = UploadTextFromWindowAsync());
        menu.Items.Add("Upload Folder...", null, (_, _) => _ = UploadFolderBatchFromWindowAsync());
        menu.Items.Add("Shorten URL...", null, (_, _) => _ = ShortenUrlFromWindowAsync());
        menu.Items.Add("Watch Folders...", null, (_, _) => _ = OpenWatchFoldersFromWindowAsync());
        menu.Items.Add("Index Folder...", null, (_, _) => _ = UploadFolderIndexFromWindowAsync());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(BuildToolsMenu());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(BuildAppearanceMenu());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(BuildAfterUploadTasksMenu());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("Preferences...", null, (_, _) => _ = OpenPreferencesFromWindowAsync());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Shutdown());

        trayIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "CraftyCannon",
            Visible = true,
            ContextMenuStrip = menu
        };
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();
        RefreshTrayPreferenceMenuState();
    }

    private System.Windows.Forms.ToolStripMenuItem BuildCaptureOptionsMenu()
    {
        captureDelayMenuItems.Clear();
        var captureOptions = new System.Windows.Forms.ToolStripMenuItem("Capture Options");
        showCursorMenuItem = new System.Windows.Forms.ToolStripMenuItem("Show Cursor");
        showCursorMenuItem.Click += (_, _) => _ = ToggleCaptureIncludeCursorAsync();
        captureOptions.DropDownItems.Add(showCursorMenuItem);

        var delayMenu = new System.Windows.Forms.ToolStripMenuItem("Screenshot Delay");
        for (var seconds = 0; seconds <= 5; seconds++)
        {
            var capturedSeconds = seconds;
            var item = new System.Windows.Forms.ToolStripMenuItem(seconds == 1 ? "1 sec" : $"{seconds} sec") { Tag = seconds };
            item.Click += (_, _) => _ = SetCaptureDelaySecondsAsync(capturedSeconds);
            captureDelayMenuItems[seconds] = item;
            delayMenu.DropDownItems.Add(item);
        }

        captureOptions.DropDownItems.Add(delayMenu);
        return captureOptions;
    }
    private System.Windows.Forms.ToolStripMenuItem BuildToolsMenu()
    {
        var tools = new System.Windows.Forms.ToolStripMenuItem("Tools");
        tools.DropDownItems.Add("Color Picker...", null, (_, _) => OpenColorPickerFromWindow());
        tools.DropDownItems.Add("QR Code...", null, (_, _) => OpenQrCodeFromWindow());
        tools.DropDownItems.Add("Hash Checker...", null, (_, _) => OpenHashCheckerFromWindow());
        tools.DropDownItems.Add("Directory Indexer...", null, (_, _) => OpenDirectoryIndexerFromWindow());
        tools.DropDownItems.Add(new System.Windows.Forms.ToolStripSeparator());
        tools.DropDownItems.Add("Pin Clipboard Image", null, (_, _) => PinClipboardImageFromWindow());
        tools.DropDownItems.Add("Pin Image File...", null, (_, _) => PinImageFileFromWindow());
        tools.DropDownItems.Add(new System.Windows.Forms.ToolStripSeparator());
        tools.DropDownItems.Add("Open Latest Image In Editor", null, (_, _) => _ = OpenLatestImageInEditorFromWindowAsync());
        return tools;
    }

    private System.Windows.Forms.ToolStripMenuItem BuildAppearanceMenu()
    {
        paletteMenuItems.Clear();
        var appearance = new System.Windows.Forms.ToolStripMenuItem("Appearance");
        var palette = new System.Windows.Forms.ToolStripMenuItem("Palette");
        foreach (var (id, label) in PaletteChoices())
        {
            var item = new System.Windows.Forms.ToolStripMenuItem(label) { Tag = id };
            item.Click += (_, _) => _ = SetActivePaletteAsync(id);
            paletteMenuItems[id] = item;
            palette.DropDownItems.Add(item);
        }

        appearance.DropDownItems.Add(palette);
        return appearance;
    }

    private System.Windows.Forms.ToolStripMenuItem BuildAfterUploadTasksMenu()
    {
        var afterUpload = new System.Windows.Forms.ToolStripMenuItem("After Upload Tasks");
        copyUrlAfterUploadMenuItem = new System.Windows.Forms.ToolStripMenuItem("Copy URL to clipboard");
        copyUrlAfterUploadMenuItem.Click += (_, _) => _ = ToggleCopyUrlAfterUploadAsync();
        copyImageAfterUploadMenuItem = new System.Windows.Forms.ToolStripMenuItem("Copy image to clipboard");
        copyImageAfterUploadMenuItem.Click += (_, _) => _ = ToggleCopyImageAfterUploadAsync();
        openUrlAfterUploadMenuItem = new System.Windows.Forms.ToolStripMenuItem("Open URL");
        openUrlAfterUploadMenuItem.Click += (_, _) => _ = ToggleOpenUrlAfterUploadAsync();
        afterUpload.DropDownItems.Add(copyUrlAfterUploadMenuItem);
        afterUpload.DropDownItems.Add(copyImageAfterUploadMenuItem);
        afterUpload.DropDownItems.Add(openUrlAfterUploadMenuItem);
        return afterUpload;
    }

    private static void ApplyPaletteResources(RuntimePreferencesSnapshot preferences)
    {
        var palette = UiPaletteCatalog.Resolve(preferences.ActivePaletteId, preferences.CustomPalette).Data;
        SetBrush("CraftyWindowBackgroundBrush", Blend(palette.WindowGradientA, White, 0.90));
        SetBrush("CraftyRailBackgroundBrush", Blend(palette.RailPanelAccent, Black, 0.46));
        SetBrush("CraftyRailTextBrush", White);
        SetBrush("CraftyContextBackgroundBrush", Blend(palette.ContextPanelAccent, White, 0.92));
        SetBrush("CraftyPanelBackgroundBrush", Blend(palette.WindowGradientC, White, 0.97));
        SetBrush("CraftyPanelMutedBackgroundBrush", Blend(palette.WindowGradientB, White, 0.88));
        SetBrush("CraftyBorderBrush", Blend(palette.SettingsAccent, White, 0.45));
        SetBrush("CraftyPrimaryTextBrush", Blend(palette.RailPanelAccent, Black, 0.68));
        SetBrush("CraftySecondaryTextBrush", Blend(palette.SettingsAccent, Black, 0.36));
        SetBrush("CraftyAccentBrush", palette.CaptureAccent);
        SetBrush("CraftyButtonBackgroundBrush", palette.CaptureAccent);
        SetBrush("CraftyButtonBorderBrush", Blend(palette.CaptureAccent, Black, 0.20));
        SetBrush("CraftyButtonTextBrush", White);
    }

    private static RgbaColor White => RgbaColor.Rgb255(255, 255, 255);

    private static RgbaColor Black => RgbaColor.Rgb255(0, 0, 0);

    private static void SetBrush(string key, RgbaColor color)
    {
        Current.Resources[key] = new WpfSolidColorBrush(ToWpfColor(color.Normalized));
    }

    private static WpfColor ToWpfColor(RgbaColor color) => WpfColor.FromArgb(
        ToByte(color.Alpha),
        ToByte(color.Red),
        ToByte(color.Green),
        ToByte(color.Blue));

    private static byte ToByte(double value) => (byte)Math.Round(Math.Clamp(value, 0, 1) * 255, MidpointRounding.AwayFromZero);

    private static RgbaColor Blend(RgbaColor source, RgbaColor target, double targetAmount)
    {
        var from = source.Normalized;
        var to = target.Normalized;
        var amount = Math.Clamp(targetAmount, 0, 1);
        return new RgbaColor(
            from.Red + ((to.Red - from.Red) * amount),
            from.Green + ((to.Green - from.Green) * amount),
            from.Blue + ((to.Blue - from.Blue) * amount),
            from.Alpha + ((to.Alpha - from.Alpha) * amount));
    }
    private static (string Id, string Label)[] PaletteChoices() =>
    [
        ("classic", "Classic"),
        ("nord", "Nord"),
        ("gruvbox", "Gruvbox"),
        ("mono", "Mono"),
        ("megaDark", "Mega Dark"),
        ("oledBlack", "OLED Black"),
        ("rainbow", "Rainbow"),
        ("custom", "Custom")
    ];

    private async Task ToggleCaptureIncludeCursorAsync() =>
        await SaveRuntimePreferencesFromTrayAsync(prefs => prefs with { CaptureIncludeCursor = !prefs.CaptureIncludeCursor }).ConfigureAwait(false);

    private async Task SetCaptureDelaySecondsAsync(int seconds) =>
        await SaveRuntimePreferencesFromTrayAsync(prefs => prefs with { CaptureDelaySeconds = Math.Clamp(seconds, 0, 5) }).ConfigureAwait(false);

    private async Task ToggleCopyUrlAfterUploadAsync() =>
        await SaveRuntimePreferencesFromTrayAsync(prefs => prefs with { CopyUrlAfterUpload = !prefs.CopyUrlAfterUpload }).ConfigureAwait(false);

    private async Task ToggleCopyImageAfterUploadAsync() =>
        await SaveRuntimePreferencesFromTrayAsync(prefs => prefs with { CopyImageAfterUpload = !prefs.CopyImageAfterUpload }).ConfigureAwait(false);

    private async Task ToggleOpenUrlAfterUploadAsync() =>
        await SaveRuntimePreferencesFromTrayAsync(prefs => prefs with { OpenUrlAfterUpload = !prefs.OpenUrlAfterUpload }).ConfigureAwait(false);

    private async Task SetActivePaletteAsync(string paletteId) =>
        await SaveRuntimePreferencesFromTrayAsync(prefs => prefs with { ActivePaletteId = paletteId }).ConfigureAwait(false);

    private async Task SaveRuntimePreferencesFromTrayAsync(Func<RuntimePreferencesSnapshot, RuntimePreferencesSnapshot> update)
    {
        if (preferencesStore is null)
        {
            return;
        }

        try
        {
            await preferencesStore.SaveAsync(update(preferencesStore.Current)).ConfigureAwait(false);
            Current.Dispatcher.Invoke(() =>
            {
                ApplyPaletteResources(preferencesStore.Current);
                RefreshTrayPreferenceMenuState();
            });
        }
        catch (Exception ex)
        {
            SetStatus("Could not update tray preference: " + ex.Message);
        }
    }

    private void RefreshTrayPreferenceMenuState()
    {
        var prefs = preferencesStore?.Current ?? RuntimePreferencesStore.Defaults;
        if (showCursorMenuItem is not null)
        {
            showCursorMenuItem.Checked = prefs.CaptureIncludeCursor;
        }

        foreach (var (seconds, item) in captureDelayMenuItems)
        {
            item.Checked = seconds == prefs.CaptureDelaySeconds;
        }

        if (copyUrlAfterUploadMenuItem is not null)
        {
            copyUrlAfterUploadMenuItem.Checked = prefs.CopyUrlAfterUpload;
        }

        if (copyImageAfterUploadMenuItem is not null)
        {
            copyImageAfterUploadMenuItem.Checked = prefs.CopyImageAfterUpload;
        }

        if (openUrlAfterUploadMenuItem is not null)
        {
            openUrlAfterUploadMenuItem.Checked = prefs.OpenUrlAfterUpload;
        }

        foreach (var (id, item) in paletteMenuItems)
        {
            item.Checked = string.Equals(id, prefs.ActivePaletteId, StringComparison.OrdinalIgnoreCase);
        }
    }
    private void ShowMainWindow()
    {
        Current.Dispatcher.Invoke(() =>
        {
            mainWindow ??= new MainWindow(viewModel ??= new MainWindowViewModel());
            mainWindow.Show();
            mainWindow.Activate();
        });
    }






    public async Task OpenWatchFoldersFromWindowAsync()
    {
        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (preferencesStore is null)
        {
            SetStatus("Preferences are not ready.");
            return;
        }

        Current.Dispatcher.Invoke(() =>
        {
            var window = new WatchFoldersWindow(preferencesStore, () => watchFolderManager?.ApplyCurrentPreferences())
            {
                Owner = mainWindow
            };
            window.ShowDialog();
        });
    }
    public void PinClipboardImageFromWindow()
    {
        ShowMainWindow();
        Current.Dispatcher.Invoke(() =>
        {
            if (!System.Windows.Clipboard.ContainsImage())
            {
                SetStatus("Pin failed: Clipboard has no image.");
                NotifyUser("Pin failed", "Clipboard has no image.", System.Windows.Forms.ToolTipIcon.Warning);
                return;
            }

            var image = System.Windows.Clipboard.GetImage();
            if (image is null)
            {
                SetStatus("Pin failed: Clipboard has no image.");
                NotifyUser("Pin failed", "Clipboard has no image.", System.Windows.Forms.ToolTipIcon.Warning);
                return;
            }

            PinImage(image, "Pinned");
        });
    }

    public void PinImageFileFromWindow()
    {
        ShowMainWindow();
        Current.Dispatcher.Invoke(() =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Title = "Choose Image",
                CheckFileExists = true,
                Multiselect = false,
                Filter = "Image files|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.tif;*.tiff;*.webp|All files|*.*"
            };

            if (dialog.ShowDialog(mainWindow) != true)
            {
                return;
            }

            try
            {
                var image = LoadPinnedImage(dialog.FileName);
                PinImage(image, Path.GetFileName(dialog.FileName));
            }
            catch
            {
                SetStatus("Pin failed: Failed to load image.");
                NotifyUser("Pin failed", "Failed to load image.", System.Windows.Forms.ToolTipIcon.Warning);
            }
        });
    }

    private void PinImage(System.Windows.Media.Imaging.BitmapSource image, string title)
    {
        if (image.CanFreeze && !image.IsFrozen)
        {
            image.Freeze();
        }

        var window = new PinnedImageWindow(image, title) { Owner = mainWindow };
        pinnedImageWindows[window.Id] = window;
        window.Closed += (_, _) => pinnedImageWindows.Remove(window.Id);
        window.Show();
        window.Activate();
    }

    private static System.Windows.Media.Imaging.BitmapSource LoadPinnedImage(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        var decoder = System.Windows.Media.Imaging.BitmapDecoder.Create(
            stream,
            System.Windows.Media.Imaging.BitmapCreateOptions.PreservePixelFormat,
            System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
        var frame = decoder.Frames.First();
        var converted = new System.Windows.Media.Imaging.FormatConvertedBitmap(
            frame,
            System.Windows.Media.PixelFormats.Bgra32,
            null,
            0);
        converted.Freeze();
        return converted;
    }
    public void OpenColorPickerFromWindow()
    {
        ShowMainWindow();
        Current.Dispatcher.Invoke(() =>
        {
            colorPickerWindow ??= new ColorPickerWindow(NotifyToolAction) { Owner = mainWindow };
            colorPickerWindow.Show();
            colorPickerWindow.Activate();
        });
    }
    public void OpenQrCodeFromWindow()
    {
        ShowMainWindow();
        Current.Dispatcher.Invoke(() =>
        {
            qrCodeWindow ??= new QrCodeWindow(NotifyToolAction) { Owner = mainWindow };
            qrCodeWindow.Show();
            qrCodeWindow.Activate();
        });
    }

    public void OpenHashCheckerFromWindow()
    {
        ShowMainWindow();
        Current.Dispatcher.Invoke(() =>
        {
            hashCheckerWindow ??= new HashCheckerWindow(NotifyToolAction) { Owner = mainWindow };
            hashCheckerWindow.Show();
            hashCheckerWindow.Activate();
        });
    }

    public void OpenDirectoryIndexerFromWindow()
    {
        ShowMainWindow();
        Current.Dispatcher.Invoke(() =>
        {
            paths ??= new AppStoragePaths();
            fileRevealLauncher ??= new WindowsFileRevealLauncher();
            directoryIndexerWindow ??= new DirectoryIndexerWindow(paths, fileRevealLauncher, NotifyToolAction) { Owner = mainWindow };
            directoryIndexerWindow.Show();
            directoryIndexerWindow.Activate();
        });
    }

    public async Task OpenHistoryWorkspaceFromWindowAsync()
    {
        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        RefreshHistoryView();
        Current.Dispatcher.Invoke(() => viewModel?.SelectHistoryWorkspace());
    }

    public void CopySelectedHistoryUrlFromWindow()
    {
        var url = viewModel?.SelectedHistoryRow?.PreferredUrl;
        if (clipboard is not null && !string.IsNullOrWhiteSpace(url) && clipboard.TrySetText(url))
        {
            SetStatus("History URL copied: " + url);
        }
        else
        {
            SetStatus("No history URL is available to copy.");
        }
    }

    public void OpenSelectedHistoryUrlFromWindow()
    {
        var url = viewModel?.SelectedHistoryRow?.PreferredUrl;
        if (!string.IsNullOrWhiteSpace(url) && new WindowsShellLauncher().TryOpenUrl(url))
        {
            SetStatus("Opened history URL: " + url);
        }
        else
        {
            SetStatus("No valid history URL is available to open.");
        }
    }

    public async Task ShortenSelectedHistoryUrlFromWindowAsync()
    {
        if (uploadWorkflow is null || preferencesStore is null || historyStore is null || viewModel?.SelectedHistoryRow?.Record is not { } record)
        {
            SetStatus("No history URL is selected.");
            return;
        }

        if (string.IsNullOrWhiteSpace(record.RemoteUrl))
        {
            SetStatus("Selected history record has no original URL to shorten.");
            return;
        }

        var shortener = BuildShortenerRequest(preferencesStore.Current);
        if (shortener is null)
        {
            SetStatus("Custom shortener template must contain {url}.");
            return;
        }

        try
        {
            SetStatus("Shortening selected history URL...");
            var options = new UploadWorkflowOptions(
                UploadProfile.Unconfigured,
                new ProfileSecrets(),
                DefaultFileExpirySeconds: 0,
                new AfterUploadTaskOptions(CopyImage: false, CopyUrl: true, OpenUrl: false),
                new AfterCaptureTaskOptions(),
                new PasteTargetInfo("Windows", "CraftyCannon"),
                Shortener: shortener);
            var outcome = await uploadWorkflow.ShortenUrlAsync(record.RemoteUrl, options).ConfigureAwait(false);
            await historyStore.UpsertAsync(UploadHistoryActions.WithShortenedUrl(record, outcome.Url!)).ConfigureAwait(false);
            RefreshHistoryView();
            SetStatus(DescribeOutcome(outcome));
        }
        catch (Exception ex)
        {
            RefreshHistoryView();
            SetStatus("History URL shortening failed: " + ex.Message);
        }
    }

    public async Task ReuploadSelectedHistoryFileFromWindowAsync()
    {
        if (uploadWorkflow is null || historyStore is null || viewModel?.SelectedHistoryRow?.Record is not { } record)
        {
            SetStatus("No history file is selected to re-upload.");
            return;
        }

        if (string.IsNullOrWhiteSpace(record.LocalFilePath))
        {
            SetStatus("No local file available to re-upload.");
            return;
        }

        var options = BuildWorkflowOptions();
        if (options is null)
        {
            return;
        }

        var activeRecord = UploadHistoryActions.WithReuploadStarted(record);
        await historyStore.UpsertAsync(activeRecord).ConfigureAwait(false);
        RefreshHistoryView();

        var shouldPromptForExpiry = IsHistoryFileRecord(activeRecord);
        int? expiresSeconds = null;
        if (shouldPromptForExpiry)
        {
            expiresSeconds = PromptExpirySeconds();
            if (expiresSeconds is null)
            {
                await historyStore.UpsertAsync(UploadHistoryActions.WithFailedReupload(activeRecord, "cancelled")).ConfigureAwait(false);
                RefreshHistoryView();
                SetStatus("Reupload cancelled.");
                return;
            }
        }

        try
        {
            SetStatus("Reuploading history file...");
            var outcome = await uploadWorkflow.ReuploadHistoryRecordAsync(activeRecord, options, expiresSeconds).ConfigureAwait(false);
            SetStatus(DescribeOutcome(outcome));
            RefreshHistoryView();
        }
        catch (Exception ex)
        {
            await historyStore.UpsertAsync(UploadHistoryActions.WithFailedReupload(activeRecord, ex.Message)).ConfigureAwait(false);
            RefreshHistoryView();
            SetStatus("Reupload failed: " + ex.Message);
        }
    }
    public async Task<bool> SaveEditorExportFromWindowAsync(string exportedPath)
    {
        if (paths is null || uploadWorkflow is null)
        {
            SetStatus("Upload services are not ready.");
            return false;
        }

        if (string.IsNullOrWhiteSpace(exportedPath) || !File.Exists(exportedPath))
        {
            SetStatus("Edited image export is missing.");
            return false;
        }

        var options = BuildWorkflowOptions();
        if (options is null)
        {
            return false;
        }

        var imageDayDirectory = Path.Combine(paths.ImagesDirectory, DateTime.Now.ToString("yyyy-MM-dd"));
        Directory.CreateDirectory(imageDayDirectory);
        var managedPath = Path.Combine(imageDayDirectory, $"edited-{Guid.NewGuid():N}.png");
        File.Copy(exportedPath, managedPath, overwrite: false);

        try
        {
            SetStatus("Uploading edited image...");
            var outcome = await uploadWorkflow.UploadLocalFileAsync(
                managedPath,
                options,
                UploadSourceKind.ManualFile,
                isManagedLocalCopy: true).ConfigureAwait(false);
            RefreshHistoryView();
            SetStatus(DescribeOutcome(outcome));
            return outcome.Records.FirstOrDefault()?.Status == UploadStatus.Uploaded;
        }
        catch (Exception ex)
        {
            SetStatus("Edited image upload failed: " + ex.Message);
            RefreshHistoryView();
            return false;
        }
        finally
        {
            var guard = new TempFileGuard(paths);
            if (guard.IsSafeToDelete(exportedPath) && File.Exists(exportedPath))
            {
                File.Delete(exportedPath);
            }
        }
    }
    public async Task OpenSelectedHistoryInEditorFromWindowAsync()
    {
        if (viewModel?.SelectedHistoryRow?.Record is not { } record)
        {
            SetStatus("No editable history image is selected.");
            return;
        }

        await OpenHistoryRecordInEditorAsync(record, "Selected history record is not an editable local image.").ConfigureAwait(false);
    }

    public async Task OpenLatestImageInEditorFromWindowAsync()
    {
        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (historyStore is null)
        {
            SetStatus("Upload history is not ready.");
            return;
        }

        var record = historyStore.Records
            .OrderByDescending(candidate => candidate.CreatedAt)
            .ThenByDescending(candidate => candidate.Id)
            .FirstOrDefault(UploadHistoryActions.CanEditImage);
        if (record is null)
        {
            SetStatus("No editable local image is available in history.");
            return;
        }

        await OpenHistoryRecordInEditorAsync(record, "Latest history image is no longer available locally.").ConfigureAwait(false);
    }

    private async Task OpenHistoryRecordInEditorAsync(UploadRecord record, string unavailableStatus)
    {
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (editorLauncher is null || !UploadHistoryActions.CanEditImage(record) || !editorLauncher.TryOpenRecord(record.Id))
        {
            SetStatus(unavailableStatus);
            return;
        }

        SetStatus("Opened editor: " + record.FileName);
    }
    public void RevealSelectedHistoryFileFromWindow()
    {
        var path = viewModel?.SelectedHistoryRow?.Record.LocalFilePath;
        if (!string.IsNullOrWhiteSpace(path) && fileRevealLauncher?.TryRevealFile(path) == true)
        {
            SetStatus("Revealed local file: " + path);
        }
        else
        {
            SetStatus("No local file is available to reveal.");
        }
    }

    public async Task DeleteSelectedManagedHistoryFileFromWindowAsync()
    {
        if (historyStore is null || paths is null || viewModel?.SelectedHistoryRow?.Record is not { } record)
        {
            SetStatus("No managed local file is selected.");
            return;
        }

        if (!record.IsManagedLocalCopy || string.IsNullOrWhiteSpace(record.LocalFilePath) || !File.Exists(record.LocalFilePath))
        {
            SetStatus("Selected history record does not have a managed local copy.");
            return;
        }

        var guard = new TempFileGuard(paths);
        if (!guard.IsSafeToDelete(record.LocalFilePath))
        {
            SetStatus("Refusing to delete a local file outside app-managed locations.");
            return;
        }

        File.Delete(record.LocalFilePath);
        await historyStore.UpsertAsync(record with { LocalFilePath = null, IsManagedLocalCopy = false }).ConfigureAwait(false);
        RefreshHistoryView();
        SetStatus("Deleted managed local copy.");
    }

    private async Task RunOnboardingIfNeededAsync(IHttpTransport transport)
    {
        if (profileStore is null || preferencesStore is null)
        {
            return;
        }

        if (profileStore.HasConfiguredProfiles())
        {
            if (preferencesStore.Current.OnboardingState != OnboardingState.Completed)
            {
                await preferencesStore.SaveAsync(preferencesStore.Current with { OnboardingState = OnboardingState.Completed }).ConfigureAwait(false);
            }

            return;
        }

        if (preferencesStore.Current.OnboardingState != OnboardingState.Pending)
        {
            return;
        }

        OnboardingResult? result = null;
        await Current.Dispatcher.InvokeAsync(() =>
        {
            ShowMainWindow();
            var window = new OnboardingWindow(profile => new ZiplineClient(transport).ValidateAsync(profile))
            {
                Owner = mainWindow
            };
            if (window.ShowDialog() == true)
            {
                result = window.Result;
            }
        });

        if (result is not null)
        {
            await profileStore.ReplaceProfilesAsync([result.Profile], result.Profile.Id).ConfigureAwait(false);
            profileStore.SaveSecrets(result.Profile.Id, result.Secrets);
            await preferencesStore.SaveAsync(preferencesStore.Current with { OnboardingState = OnboardingState.Completed }).ConfigureAwait(false);
            SetStatus($"Ready. Active profile: {result.Profile.Name}");
            return;
        }

        await Current.Dispatcher.InvokeAsync(ShowPreferencesDialog);
        if (profileStore.HasConfiguredProfiles())
        {
            await preferencesStore.SaveAsync(preferencesStore.Current with { OnboardingState = OnboardingState.Completed }).ConfigureAwait(false);
        }
    }

    private void ShowPreferencesDialog()
    {
        if (profileStore is null || preferencesStore is null)
        {
            SetStatus("Preferences are not ready.");
            return;
        }

        var window = new PreferencesWindow(profileStore, preferencesStore, cloudflareAllowlistManager)
        {
            Owner = mainWindow
        };
        var saved = window.ShowDialog() == true;
        if (saved)
        {
            SetStatus(profileStore.ActiveProfile == UploadProfile.Unconfigured
                ? "No upload profile configured. Add a profile in Preferences before uploading."
                : $"Ready. Active profile: {profileStore.ActiveProfile.Name}");
            hotKeyManager?.ApplyBindings(preferencesStore.Current.HotKeys ?? HotKeyBindings.Defaults);
            ApplyPaletteResources(preferencesStore.Current);
            cloudflareAllowlistManager?.ApplyCurrentPreferences();
            watchFolderManager?.ApplyCurrentPreferences();
            RefreshTrayPreferenceMenuState();
        }
    }
    public async Task OpenPreferencesFromWindowAsync()
    {
        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (profileStore is null || preferencesStore is null)
        {
            SetStatus("Preferences are not ready.");
            return;
        }

        await Current.Dispatcher.InvokeAsync(ShowPreferencesDialog);
    }
    public async Task CaptureRegionFromWindowAsync()
    {
        await ExecuteCaptureUploadAsync("Capturing region...", CaptureMode.Region);
    }

    public async Task CaptureRegionExpiringFromWindowAsync()
    {
        var expirySeconds = PromptExpirySeconds();
        if (expirySeconds is null)
        {
            return;
        }

        await ExecuteCaptureUploadAsync("Capturing expiring region...", CaptureMode.Region, expirySeconds);
    }

    public async Task CaptureFrozenRegionFromWindowAsync()
    {
        await ExecuteCaptureUploadAsync("Capturing frozen region...", CaptureMode.FrozenRegion);
    }


    public async Task CaptureWindowFromWindowAsync()
    {
        await ExecuteCaptureUploadAsync("Capturing window...", CaptureMode.Window);
    }

    public async Task CaptureTopTaskbarFromWindowAsync()
    {
        await ExecuteCaptureUploadAsync("Capturing top taskbar...", CaptureMode.TopTaskbar);
    }

    private Task ExecuteHotKeyActionAsync(GlobalHotKeyAction action) => action switch
    {
        GlobalHotKeyAction.CaptureRegionUpload => CaptureRegionFromWindowAsync(),
        GlobalHotKeyAction.CaptureRegionUploadExpiring => CaptureRegionExpiringFromWindowAsync(),
        GlobalHotKeyAction.CaptureRegionUploadFrozen => CaptureFrozenRegionFromWindowAsync(),
        GlobalHotKeyAction.UploadClipboard => UploadClipboardFromWindowAsync(),
        _ => Task.CompletedTask
    };


    private async Task ExecuteCaptureUploadAsync(string progressStatus, CaptureMode mode, int? expirySeconds = null)
    {
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (screenCapture is null || uploadWorkflow is null)
        {
            SetStatus("Capture services are not ready.");
            return;
        }

        var options = BuildWorkflowOptions();
        if (options is null)
        {
            return;
        }

        try
        {
            SetStatus(progressStatus);
            var request = BuildCaptureRequest(mode);
            var result = await screenCapture.CaptureAsync(request, CancellationToken.None).ConfigureAwait(false);
            var effectiveMode = request.Mode;
            var capturePreferences = preferencesStore?.Current ?? RuntimePreferencesStore.Defaults;
            if (effectiveMode != CaptureMode.ScreenRecording && capturePreferences.CaptureMirrorToScreenshotsFolder)
            {
                MirrorCaptureToScreenshotsFolder(result, capturePreferences, LocalMirrorPrefixFor(effectiveMode), CaptureContextFor(effectiveMode));
            }

            UploadWorkflowOutcome outcome;
            if (effectiveMode == CaptureMode.ScreenRecording)
            {
                outcome = await uploadWorkflow.UploadLocalFileAsync(result.FilePath, options, UploadSourceKind.ManualFile).ConfigureAwait(false);
            }
            else if (expirySeconds is int seconds)
            {
                outcome = await uploadWorkflow.UploadPayloadAsync(
                    new PreparedUploadPayload(result.FilePath, UploadPayloadKind.File, UploadSourceKind.Capture, UploadContext: "manual-file", TemporarySourceFile: true),
                    options with { DefaultFileExpirySeconds = seconds }).ConfigureAwait(false);
            }
            else
            {
                outcome = await uploadWorkflow.UploadPayloadAsync(
                    new PreparedUploadPayload(result.FilePath, UploadPayloadKind.Image, UploadSourceKind.Capture, UploadContext: CaptureContextFor(effectiveMode), TemporarySourceFile: true),
                    options).ConfigureAwait(false);
            }

            SetStatus(DescribeOutcome(outcome));
            NotifyUploadOutcome(outcome);
            RefreshHistoryView();
        }
        catch (OperationCanceledException)
        {
            SetStatus("Capture cancelled.");
            RefreshHistoryView();
        }
        catch (Exception ex)
        {
            var isRecording = mode == CaptureMode.ScreenRecording;
            SetStatus((isRecording ? "Recording failed: " : "Capture failed: ") + ex.Message);
            NotifyUploadFailure(isRecording ? "Recording failed" : "Capture failed", ex);
            ShowBlockingAlert((isRecording ? "Recording failed: " : "Screen capture failed: ") + ex.Message, isRecording ? "Recording failed" : "Screen capture failed", MessageBoxImage.Error);
            RefreshHistoryView();
        }
    }


    private void MirrorCaptureToScreenshotsFolder(CaptureResult result, RuntimePreferencesSnapshot preferences, string? preferredPrefix, string fallbackPrefix)
    {
        if (paths is null || string.IsNullOrWhiteSpace(result.FilePath) || !File.Exists(result.FilePath))
        {
            return;
        }

        var destinationRoot = ResolveScreenshotsDirectory(preferences);
        var dateDirectory = Path.Combine(destinationRoot, DateTime.Now.ToString("yyyy-MM-dd"));
        Directory.CreateDirectory(dateDirectory);


        var destination = Path.Combine(dateDirectory, LocalMirrorFilename.BuildFilename(result.FilePath, preferredPrefix, fallbackPrefix));
        File.Copy(result.FilePath, destination, overwrite: false);
    }

    private string ResolveScreenshotsDirectory(RuntimePreferencesSnapshot preferences)
    {
        if (paths is null)
        {
            throw new InvalidOperationException("App storage paths are not ready.");
        }

        if (!string.IsNullOrWhiteSpace(preferences.CaptureScreenshotsFolder))
        {
            try
            {
                var custom = AppStoragePaths.NormalizeUserDirectory(preferences.CaptureScreenshotsFolder);
                Directory.CreateDirectory(custom);
                return custom;
            }
            catch
            {
                // Match macOS behavior: custom folder failures fall back to Documents/images.
            }
        }

        Directory.CreateDirectory(paths.ScreenshotsFallbackDirectory);
        return paths.ScreenshotsFallbackDirectory;
    }

    private static string LocalMirrorPrefixFor(CaptureMode mode)
    {
        var foreground = ForegroundWindowTitle();
        if (LocalMirrorFilename.NormalizedPrefix(foreground) is not null)
        {
            return foreground!;
        }

        return CaptureContextFor(mode);
    }

    private static string? ForegroundWindowTitle()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == nint.Zero)
        {
            return null;
        }

        var length = GetWindowTextLength(hwnd);
        if (length <= 0)
        {
            return null;
        }

        var builder = new StringBuilder(length + 1);
        _ = GetWindowText(hwnd, builder, builder.Capacity);
        var title = builder.ToString().Trim();
        if (title.Length == 0 || title.Contains("CraftyCannon", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return title;
    }

    private CaptureRequest BuildCaptureRequest(CaptureMode requestedMode)
    {
        var prefs = preferencesStore?.Current ?? RuntimePreferencesStore.Defaults;
        var mode = requestedMode;
        ScreenRect? fixedRegion = null;
        if (prefs.CaptureFixedRegionEnabled && (requestedMode == CaptureMode.Region || requestedMode == CaptureMode.ScreenRecording))
        {
            if (requestedMode == CaptureMode.Region)
            {
                mode = CaptureMode.FixedRegion;
            }

            fixedRegion = new ScreenRect(
                prefs.CaptureFixedRegionX,
                prefs.CaptureFixedRegionY,
                prefs.CaptureFixedRegionWidth,
                prefs.CaptureFixedRegionHeight);
        }

        return new CaptureRequest(
            mode,
            fixedRegion,
            TimeSpan.FromSeconds(Math.Clamp(prefs.CaptureDelaySeconds, 0, 5)),
            prefs.CaptureIncludeCursor,
            RecordingDuration: requestedMode == CaptureMode.ScreenRecording ? TimeSpan.FromSeconds(30) : null,
            RecordingOutputDirectory: requestedMode == CaptureMode.ScreenRecording ? ResolveScreenshotsDirectory(prefs) : null,
            ShowOverlayInfo: prefs.CaptureShowInfoOverlay,
            SnapSizes: prefs.CaptureSnapSizes);
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(nint hWnd);
    private static string CaptureContextFor(CaptureMode mode) => mode switch
    {
        CaptureMode.Region => "region",
        CaptureMode.FrozenRegion => "region",
        CaptureMode.FixedRegion => "region",
        CaptureMode.Window => "window",
        CaptureMode.FullScreen => "fullscreen",
        CaptureMode.TopTaskbar => "top-taskbar",
        CaptureMode.ScreenRecording => "screen-recording",
        _ => "capture"
    };

    public async Task CaptureFullScreenFromWindowAsync()
    {
        await ExecuteCaptureUploadAsync("Capturing full screen...", CaptureMode.FullScreen);
    }

    public async Task CaptureScreenRecordingFromWindowAsync()
    {
        await ExecuteCaptureUploadAsync("Recording screen for up to 30 seconds...", CaptureMode.ScreenRecording);
    }

    public async Task UploadClipboardFromWindowAsync()
    {
        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (clipboard is null || uploadWorkflow is null || profileStore is null || preferencesStore is null)
        {
            SetStatus("Upload services are not ready.");
            return;
        }

        var options = BuildWorkflowOptions();
        if (options is null)
        {
            return;
        }

        try
        {
            SetStatus("Uploading clipboard...");
            var snapshot = clipboard.ReadSnapshot();
            var rules = preferencesStore.Current.ClipboardRules ?? new ClipboardUploadRules();
            var outcome = await uploadWorkflow.ExecuteClipboardAsync(snapshot, rules, options).ConfigureAwait(false);
            SetStatus(DescribeOutcome(outcome));
            NotifyUploadOutcome(outcome);
            RefreshHistoryView();
        }
        catch (Exception ex)
        {
            SetStatus("Clipboard upload failed: " + ex.Message);
            NotifyUploadFailure("Clipboard upload failed", ex);
            RefreshHistoryView();
        }
    }

    public async Task UploadFileFromWindowAsync()
    {
        var filePath = Current.Dispatcher.Invoke(() =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Title = "Upload file"
            };
            return dialog.ShowDialog(mainWindow) == true ? dialog.FileName : null;
        });
        if (filePath is null)
        {
            return;
        }

        await ExecuteManualUploadAsync("Uploading file...", options => uploadWorkflow!.UploadLocalFileAsync(filePath, options));
    }

    public async Task UploadExpiringFileFromWindowAsync()
    {
        var filePath = Current.Dispatcher.Invoke(() =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Title = "Upload File (Expiring Link)..."
            };
            return dialog.ShowDialog(mainWindow) == true ? dialog.FileName : null;
        });
        if (filePath is null)
        {
            return;
        }

        var expirySeconds = PromptExpirySeconds();
        if (expirySeconds is null)
        {
            return;
        }

        await ExecuteManualUploadAsync("Uploading expiring file...", options => uploadWorkflow!.UploadExpiringLocalFileAsync(filePath, expirySeconds.Value, options));
    }

    public async Task UploadRemoteUrlFromWindowAsync()
    {
        var url = Prompt("Upload URL", "Enter an HTTP or HTTPS URL to upload.");
        if (string.IsNullOrWhiteSpace(url))
        {
            return;
        }

        await ExecuteManualUploadAsync("Uploading remote URL...", options => uploadWorkflow!.UploadRemoteUrlAsync(url, options));
    }

    public async Task ShortenUrlFromWindowAsync()
    {
        var url = Prompt("Shorten URL", "Enter an HTTP or HTTPS URL to shorten.");
        if (string.IsNullOrWhiteSpace(url))
        {
            return;
        }

        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (uploadWorkflow is null || preferencesStore is null || historyStore is null)
        {
            SetStatus("Shortener services are not ready.");
            return;
        }

        var shortener = BuildShortenerRequest(preferencesStore.Current);
        if (shortener is null)
        {
            SetStatus("Custom shortener template must contain {url}.");
            return;
        }

        var trimmedUrl = url.Trim();
        var record = new UploadRecord(
            Guid.NewGuid().ToString("N"),
            UploadStatus.Uploading,
            DateTimeOffset.UtcNow,
            "URL shortener",
            null,
            trimmedUrl,
            "URL shortener",
            null,
            SourceKind: UploadSourceKind.UrlShorten);
        await historyStore.UpsertAsync(record).ConfigureAwait(false);

        try
        {
            SetStatus("Shortening URL...");
            var options = new UploadWorkflowOptions(
                UploadProfile.Unconfigured,
                new ProfileSecrets(),
                DefaultFileExpirySeconds: 0,
                new AfterUploadTaskOptions(CopyImage: false, CopyUrl: true, OpenUrl: false),
                new AfterCaptureTaskOptions(),
                new PasteTargetInfo("Windows", "CraftyCannon"),
                Shortener: shortener);
            var outcome = await uploadWorkflow.ShortenUrlAsync(trimmedUrl, options).ConfigureAwait(false);
            await historyStore.UpsertAsync(record with
            {
                Status = UploadStatus.Uploaded,
                ShortenedUrl = outcome.Url,
                ErrorMessage = null
            }).ConfigureAwait(false);
            SetStatus(DescribeOutcome(outcome));
            RefreshHistoryView();
        }
        catch (Exception ex)
        {
            await historyStore.UpsertAsync(record with { Status = UploadStatus.Failed, ErrorMessage = ex.Message }).ConfigureAwait(false);
            SetStatus("URL shortening failed: " + ex.Message);
            RefreshHistoryView();
        }
    }

    public async Task UploadTextFromWindowAsync()
    {
        var text = Prompt("Upload Text", "Enter text to upload.", multiLine: true);
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        await ExecuteManualUploadAsync("Uploading text...", options => uploadWorkflow!.UploadTextAsync(text, options));
    }

    public async Task UploadFolderBatchFromWindowAsync()
    {
        var folder = SelectFolder("Upload folder");
        if (folder is null)
        {
            return;
        }

        await ExecuteManualUploadAsync("Uploading folder...", options => uploadWorkflow!.UploadFolderBatchAsync(folder, includeSubdirectories: true, options));
    }

    public async Task UploadFolderIndexFromWindowAsync()
    {
        var folder = SelectFolder("Create and upload folder index");
        if (folder is null)
        {
            return;
        }

        await ExecuteManualUploadAsync("Uploading folder index...", options => uploadWorkflow!.UploadFolderIndexAsync(folder, options));
    }

    private async Task ExecuteManualUploadAsync(string progressStatus, Func<UploadWorkflowOptions, Task<UploadWorkflowOutcome>> action)
    {
        ShowMainWindow();
        if (initializationTask is not null)
        {
            await initializationTask.ConfigureAwait(false);
        }

        if (uploadWorkflow is null)
        {
            SetStatus("Upload services are not ready.");
            return;
        }

        var options = BuildWorkflowOptions();
        if (options is null)
        {
            return;
        }

        try
        {
            SetStatus(progressStatus);
            var outcome = await action(options).ConfigureAwait(false);
            SetStatus(DescribeOutcome(outcome));
            NotifyUploadOutcome(outcome);
            RefreshHistoryView();
        }
        catch (OperationCanceledException)
        {
            SetStatus(progressStatus.StartsWith("Capturing", StringComparison.OrdinalIgnoreCase) ? "Capture cancelled." : "Upload cancelled.");
            RefreshHistoryView();
        }
        catch (Exception ex)
        {
            SetStatus("Upload failed: " + ex.Message);
            NotifyUploadFailure("Upload failed", ex);
            if (progressStatus.StartsWith("Capturing", StringComparison.OrdinalIgnoreCase))
            {
                ShowBlockingAlert("Screen capture failed: " + ex.Message, "Screen capture failed", MessageBoxImage.Error);
            }
            RefreshHistoryView();
        }
    }

    private string? Prompt(string title, string prompt, bool multiLine = false) =>
        Current.Dispatcher.Invoke(() =>
        {
            var window = new PromptWindow(title, prompt, multiLine)
            {
                Owner = mainWindow
            };
            return window.ShowDialog() == true ? window.Value : null;
        });

    private int? PromptExpirySeconds() =>
        Current.Dispatcher.Invoke((Func<int?>)(() =>
        {
            var window = new ExpiryPromptWindow
            {
                Owner = mainWindow
            };
            return window.ShowDialog() == true ? window.ExpirySeconds : null;
        }));

    private string? SelectFolder(string description) =>
        Current.Dispatcher.Invoke(() =>
        {
            using var dialog = new System.Windows.Forms.FolderBrowserDialog
            {
                Description = description,
                UseDescriptionForTitle = true
            };
            return dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK ? dialog.SelectedPath : null;
        });
    private UploadWorkflowOptions? BuildWorkflowOptions(bool showBlockingAlert = true)
    {
        if (profileStore is null || preferencesStore is null)
        {
            var message = "Profiles are not loaded yet.";
            SetStatus(message);
            if (showBlockingAlert)
            {
                ShowBlockingAlert(message);
            }
            return null;
        }

        var profile = profileStore.ActiveProfile;
        if (profile == UploadProfile.Unconfigured)
        {
            var message = "No upload profile configured. Add a profile in Preferences before uploading.";
            SetStatus(message);
            if (showBlockingAlert)
            {
                ShowProfileConfigurationAlert(message);
            }
            return null;
        }

        var secrets = profileStore.GetSecrets(profile.Id);
        var profileValidation = ValidateProfileShape(profile);
        if (profileValidation is not null)
        {
            SetStatus(profileValidation);
            if (showBlockingAlert)
            {
                ShowProfileConfigurationAlert(profileValidation);
            }
            return null;
        }

        if (!HasRequiredSecrets(profile, secrets))
        {
            var message = $"Missing credentials for profile: {profile.Name}";
            SetStatus(message);
            if (showBlockingAlert)
            {
                ShowProfileConfigurationAlert(message);
            }
            return null;
        }

        var secondaryProfile = profile.SecondaryS3ProfileId is null
            ? null
            : profileStore.Profiles.FirstOrDefault(candidate => candidate.Id == profile.SecondaryS3ProfileId);
        var secondarySecrets = secondaryProfile is null ? null : profileStore.GetSecrets(secondaryProfile.Id);
        if (secondaryProfile is not null &&
            (ValidateProfileShape(secondaryProfile) is not null || !HasRequiredSecrets(secondaryProfile, secondarySecrets!)))
        {
            secondaryProfile = null;
            secondarySecrets = null;
        }

        var prefs = preferencesStore.Current;
        return new UploadWorkflowOptions(
            profile,
            secrets,
            prefs.DefaultFileExpirySeconds,
            new AfterUploadTaskOptions(prefs.CopyImageAfterUpload, prefs.CopyUrlAfterUpload, prefs.OpenUrlAfterUpload),
            new AfterCaptureTaskOptions(prefs.AfterCaptureCopyImageAndUrl, prefs.AfterCaptureCopyUrl, prefs.OpenEditorAfterCapture),
            new PasteTargetInfo("Windows", "CraftyCannon"),
            SecondaryProfile: secondaryProfile,
            SecondarySecrets: secondarySecrets,
            Shortener: BuildShortenerRequest(prefs),
            Rewrite: BuildUrlRewriteOptions(prefs),
            RedactionPolicy: prefs.RedactionPolicy,
            EnableOcrIndexing: prefs.EnableOcrIndexing,
            RoutedProfiles: BuildRoutedProfiles(profileStore),
            UploaderFilters: prefs.UploaderFilters ?? [],
            DestinationRouting: prefs.DestinationRouting ?? new DestinationRoutingConfig(),
            SmartRedactionRenderMode: prefs.SmartRedactionRenderMode,
            StripImageMetadataBeforeUpload: prefs.StripImageMetadataBeforeUpload,
            ImageUploadFormat: prefs.ImageUploadFormat,
            FileNaming: BuildFileNamingOptions(prefs));
    }



    private static UploadFileNamingOptions BuildFileNamingOptions(RuntimePreferencesSnapshot preferences) => new(
        preferences.FileUploadUseNamePattern,
        preferences.FileUploadUseRandom16Name,
        preferences.FileNamePattern,
        preferences.FileNameAutoIncrement,
        preferences.FileUploadReplaceProblematicCharacters);
    private static IReadOnlyList<UploadRouteProfile> BuildRoutedProfiles(JsonProfileStore store) =>
        store.Profiles
            .Where(profile => profile != UploadProfile.Unconfigured)
            .Select(profile => new UploadRouteProfile(profile, store.GetSecrets(profile.Id)))
            .Where(route => ValidateProfileShape(route.Profile) is null && HasRequiredSecrets(route.Profile, route.Secrets))
            .ToArray();
    private static bool IsHistoryFileRecord(UploadRecord record) =>
        record.RecordKind == UploadRecordKind.File ||
        (record.RecordKind == UploadRecordKind.Unknown && !LooksLikeImagePath(record.LocalFilePath));

    private static bool LooksLikeImagePath(string? path) =>
        !string.IsNullOrWhiteSpace(path) && HistoryImageExtensions.Contains(Path.GetExtension(path));

    private static UrlRewriteOptions? BuildUrlRewriteOptions(RuntimePreferencesSnapshot preferences) =>
        preferences.UrlRegexReplaceEnabled
            ? new UrlRewriteOptions(true, preferences.UrlRegexPattern ?? string.Empty, preferences.UrlRegexReplacement ?? string.Empty)
            : null;
    private static ShortenerRequest? BuildShortenerRequest(RuntimePreferencesSnapshot preferences)
    {
        if (string.Equals(preferences.ShortenerProvider, "customGetTemplate", StringComparison.OrdinalIgnoreCase))
        {
            var template = preferences.ShortenerCustomGetTemplate.Trim();
            return template.Contains("{url}", StringComparison.Ordinal)
                ? new ShortenerRequest(ShortenerProvider.CustomGetTemplate, template)
                : null;
        }

        return new ShortenerRequest(ShortenerProvider.TinyUrl);
    }

    private static string? ValidateProfileShape(UploadProfile profile) =>
        profile.Backend switch
        {
            UploadBackend.ZiplineV4 when string.IsNullOrWhiteSpace(profile.Endpoint) => $"Profile {profile.Name} is missing a Zipline endpoint.",
            UploadBackend.ZiplineV4 when !Uri.TryCreate(profile.Endpoint.Trim(), UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps => $"Profile {profile.Name} must use a valid HTTPS Zipline endpoint.",
            UploadBackend.S3Compatible when profile.S3Config is null => $"Profile {profile.Name} is missing S3 configuration.",
            UploadBackend.S3Compatible when string.IsNullOrWhiteSpace(profile.S3Config.Endpoint) => $"Profile {profile.Name} is missing an S3 endpoint.",
            UploadBackend.S3Compatible when string.IsNullOrWhiteSpace(profile.S3Config.Region) => $"Profile {profile.Name} is missing an S3 region.",
            UploadBackend.S3Compatible when string.IsNullOrWhiteSpace(profile.S3Config.Bucket) => $"Profile {profile.Name} is missing an S3 bucket.",
            _ => null
        };
    private static bool HasRequiredSecrets(UploadProfile profile, ProfileSecrets secrets) =>
        profile.Backend switch
        {
            UploadBackend.ZiplineV4 => !string.IsNullOrWhiteSpace(secrets.ZiplineApiKey),
            UploadBackend.S3Compatible => !string.IsNullOrWhiteSpace(secrets.S3AccessKey) && !string.IsNullOrWhiteSpace(secrets.S3SecretKey),
            _ => false
        };

    private void RefreshHistoryView()
    {
        if (viewModel is null || historyStore is null)
        {
            return;
        }

        Current.Dispatcher.Invoke(() => viewModel.SetHistoryRecords(historyStore.Records));
    }

    private void NotifyUploadOutcome(UploadWorkflowOutcome outcome, bool showBlockingAlert = true)
    {
        if (outcome.Kind == UploadWorkflowOutcomeKind.Unsupported)
        {
            var message = outcome.Message ?? "Upload was blocked.";
            NotifyUser("Upload blocked", message, System.Windows.Forms.ToolTipIcon.Warning);
            if (showBlockingAlert)
            {
                ShowBlockingAlert(message, "Upload blocked", MessageBoxImage.Warning);
            }
            return;
        }

        NotifySecondaryMirrorFailures(outcome);

        if (preferencesStore?.Current.ShowNotificationAfterUpload != true)
        {
            return;
        }

        var body = string.IsNullOrWhiteSpace(outcome.Url)
            ? outcome.Message ?? "Upload completed."
            : outcome.Url;
        var title = outcome.Kind switch
        {
            UploadWorkflowOutcomeKind.ShortenedUrl => "Shortened URL",
            UploadWorkflowOutcomeKind.UploadedBatch => "Folder upload",
            _ => "Uploaded"
        };
        NotifyUser(title, body);
    }

    private void NotifyUploadFailure(string title, Exception ex) =>
        NotifyUser(title, ex.Message, System.Windows.Forms.ToolTipIcon.Error);

    private void NotifySecondaryMirrorFailures(UploadWorkflowOutcome outcome)
    {
        var failed = outcome.Records
            .Where(record => record.SecondaryStatus == SecondaryUploadStatus.Failed)
            .ToArray();
        if (failed.Length == 0)
        {
            return;
        }

        var body = failed.Length == 1
            ? failed[0].SecondaryError ?? "Secondary S3 upload failed."
            : $"{failed.Length} secondary S3 uploads failed.";
        NotifyUser("S3 mirror failed", body, System.Windows.Forms.ToolTipIcon.Warning);
    }

    private void NotifyToolAction(string title, string body) =>
        NotifyUser(title, body);

    private void NotifyUser(string title, string body, System.Windows.Forms.ToolTipIcon icon = System.Windows.Forms.ToolTipIcon.Info)
    {
        var safeTitle = string.IsNullOrWhiteSpace(title) ? "CraftyCannon" : title.Trim();
        var safeBody = string.IsNullOrWhiteSpace(body) ? "No details available." : body.Trim();
        Current.Dispatcher.Invoke(() =>
        {
            trayIcon?.ShowBalloonTip(4000, safeTitle, safeBody, icon);
        });
    }

    private void ShowProfileConfigurationAlert(string message)
    {
        Current.Dispatcher.Invoke(() =>
        {
            var result = System.Windows.MessageBox.Show(
                mainWindow,
                message + "\n\nOpen Preferences now?",
                "CraftyCannon",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (result == MessageBoxResult.Yes)
            {
                _ = OpenPreferencesFromWindowAsync();
            }
        });
    }

    private void ShowBlockingAlert(string message, string title = "CraftyCannon", MessageBoxImage image = MessageBoxImage.Warning)
    {
        Current.Dispatcher.Invoke(() =>
        {
            System.Windows.MessageBox.Show(
                mainWindow,
                string.IsNullOrWhiteSpace(message) ? "The requested action cannot continue." : message,
                title,
                MessageBoxButton.OK,
                image);
        });
    }
    private void SetStatus(string status)
    {
        Current.Dispatcher.Invoke(() =>
        {
            if (viewModel is not null)
            {
                viewModel.StatusText = status;
            }
        });
    }

    private static string DescribeOutcome(UploadWorkflowOutcome outcome) =>
        outcome.Kind switch
        {
            UploadWorkflowOutcomeKind.Uploaded when outcome.Url is not null => "Uploaded: " + outcome.Url,
            UploadWorkflowOutcomeKind.UploadedBatch => outcome.Message ?? $"Uploaded {outcome.Records.Count} file(s).",
            UploadWorkflowOutcomeKind.ShortenedUrl when outcome.Url is not null => "Shortened URL copied: " + outcome.Url,
            UploadWorkflowOutcomeKind.CopiedUrl => "URL copied to clipboard.",
            UploadWorkflowOutcomeKind.Unsupported => outcome.Message ?? "Clipboard content is not supported by the current upload rules.",
            _ => outcome.Message ?? "Upload finished."
        };
}




































