using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using CraftyCannon.Core;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public partial class PreferencesWindow : Window
{
    private readonly JsonProfileStore store;
    private readonly RuntimePreferencesStore preferencesStore;
    private readonly WindowsCloudflareAllowlistManager? cloudflareManager;
    private readonly ObservableCollection<ProfileDraft> drafts = [];
    private readonly ObservableCollection<UploaderFilterRow> uploaderFilterRows = [];
    private bool isLoading;
    private string? activeProfileId;
    private RuntimePreferencesSnapshot runtimeDraft = RuntimePreferencesStore.Defaults;
    private readonly Dictionary<string, System.Windows.Controls.TextBox> customPaletteBoxes = new(StringComparer.Ordinal);

    private static readonly (string Key, string Label)[] CustomPaletteFields =
    [
        ("windowGradientA", "Window gradient A"),
        ("windowGradientB", "Window gradient B"),
        ("windowGradientC", "Window gradient C"),
        ("windowRadialSpot", "Window radial spot"),
        ("railPanelAccent", "Rail panel accent"),
        ("contextPanelAccent", "Context panel accent"),
        ("captureAccent", "Capture accent"),
        ("uploadAccent", "Upload accent"),
        ("workflowsAccent", "Workflows accent"),
        ("toolsAccent", "Tools accent"),
        ("afterCaptureAccent", "After capture accent"),
        ("afterUploadAccent", "After upload accent"),
        ("destinationsAccent", "Destinations accent"),
        ("settingsAccent", "Settings accent"),
        ("historyAccent", "History accent")
    ];

    public PreferencesWindow(JsonProfileStore store, RuntimePreferencesStore preferencesStore, WindowsCloudflareAllowlistManager? cloudflareManager = null)
    {
        InitializeComponent();
        this.store = store;
        this.preferencesStore = preferencesStore;
        this.cloudflareManager = cloudflareManager;
        runtimeDraft = preferencesStore.Current;
        BuildCustomPaletteEditor();
        LoadHotKeyKeyItems();
        LoadRuntimePreferences();
        LoadDrafts();
    }

    private void LoadDrafts()
    {
        drafts.Clear();
        activeProfileId = store.ActiveProfileId;
        foreach (var profile in store.Profiles)
        {
            drafts.Add(ProfileDraft.From(profile, store.GetSecrets(profile.Id), profile.Id == activeProfileId));
        }

        ProfilesList.ItemsSource = drafts;
        ProfilesList.SelectedIndex = drafts.Count > 0 ? 0 : -1;
        RefreshSecondaryProfiles();
        LoadSelectedDraft();
        RefreshRoutingProfilePickers();
        LoadUploaderFilters();
    }

    private void ProfilesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isLoading)
        {
            return;
        }

        SaveSelectedFields();
        LoadSelectedDraft();
    }

    private void BackendBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isLoading)
        {
            return;
        }

        UpdateBackendVisibility(SelectedBackend());
    }

    private void ShortenerProviderBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isLoading)
        {
            return;
        }

        UpdateShortenerVisibility(SelectedShortenerProvider());
    }

    private void UrlRegexReplaceEnabledBox_Changed(object sender, RoutedEventArgs e)
    {
        if (!isLoading)
        {
            SaveRuntimePreferences();
        }

        UpdateUrlRegexEnabledState();
    }

    private void AddZipline_Click(object sender, RoutedEventArgs e)
    {
        SaveSelectedFields();
        var draft = ProfileDraft.New(UploadBackend.ZiplineV4, "Zipline");
        drafts.Add(draft);
        activeProfileId ??= draft.Id;
        RefreshDisplayNames();
        RefreshSecondaryProfiles();
        RefreshRoutingProfilePickers();
        ProfilesList.SelectedItem = draft;
    }

    private void AddS3_Click(object sender, RoutedEventArgs e)
    {
        SaveSelectedFields();
        var draft = ProfileDraft.New(UploadBackend.S3Compatible, "S3");
        drafts.Add(draft);
        activeProfileId ??= draft.Id;
        RefreshDisplayNames();
        RefreshSecondaryProfiles();
        RefreshRoutingProfilePickers();
        ProfilesList.SelectedItem = draft;
    }

    private void DeleteProfile_Click(object sender, RoutedEventArgs e)
    {
        if (ProfilesList.SelectedItem is not ProfileDraft draft)
        {
            return;
        }

        drafts.Remove(draft);
        foreach (var existing in drafts.Where(existing => existing.SecondaryS3ProfileId == draft.Id))
        {
            existing.SecondaryS3ProfileId = null;
        }

        if (activeProfileId == draft.Id)
        {
            activeProfileId = drafts.FirstOrDefault()?.Id;
        }

        RefreshDisplayNames();
        RefreshSecondaryProfiles();
        PruneUploaderFiltersForExistingProfiles();
        RefreshRoutingProfilePickers();
        ProfilesList.SelectedIndex = drafts.Count > 0 ? 0 : -1;
        LoadSelectedDraft();
    }

    private void SetActive_Click(object sender, RoutedEventArgs e)
    {
        SaveSelectedFields();
        if (ProfilesList.SelectedItem is ProfileDraft draft)
        {
            activeProfileId = draft.Id;
            RefreshDisplayNames();
            ProfilesList.Items.Refresh();
        }
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        SaveSelectedFields();
        SaveRuntimePreferences();
        var error = ValidateAll();
        if (error is not null)
        {
            ValidationText.Text = error;
            return;
        }

        try
        {
            var profiles = drafts.Select(draft => draft.ToProfile()).ToArray();
            await store.ReplaceProfilesAsync(profiles, activeProfileId);
            foreach (var draft in drafts)
            {
                store.SaveSecrets(draft.Id, draft.ToSecrets());
            }

            SaveCloudflareTokenIfProvided();
            await preferencesStore.SaveAsync(runtimeDraft);

            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            ValidationText.Text = "Could not save profiles: " + ex.Message;
        }
    }

    private async void Validate_Click(object sender, RoutedEventArgs e)
    {
        SaveSelectedFields();
        if (ProfilesList.SelectedItem is not ProfileDraft draft)
        {
            ValidationText.Text = "Select a profile to validate.";
            return;
        }

        var error = ValidateDraft(draft);
        if (error is not null)
        {
            ValidationText.Text = error;
            return;
        }

        ValidationText.Text = "Validating...";
        try
        {
            var profile = draft.ToProfile();
            var secrets = draft.ToSecrets();
            EndpointValidationResult result;
            var transport = new HttpClientTransport();
            if (profile.Backend == UploadBackend.ZiplineV4)
            {
                result = await new ZiplineClient(transport).ValidateAsync(profile);
            }
            else
            {
                result = await new S3Client(transport).ProbeAsync(profile, secrets);
            }

            ValidationText.Text = result.Message;
        }
        catch (Exception ex)
        {
            ValidationText.Text = "Validation failed: " + ex.Message;
        }
    }
    private void LoadSelectedDraft()
    {
        isLoading = true;
        try
        {
            ValidationText.Text = string.Empty;
            if (ProfilesList.SelectedItem is not ProfileDraft draft)
            {
                SetEditorEnabled(false);
                return;
            }

            SetEditorEnabled(true);
            NameBox.Text = draft.Name;
            BackendBox.SelectedIndex = draft.Backend == UploadBackend.ZiplineV4 ? 0 : 1;
            EndpointBox.Text = draft.Endpoint;
            ZiplineTokenBox.Password = draft.ZiplineApiKey ?? string.Empty;
            S3RegionBox.Text = draft.S3Region;
            S3BucketBox.Text = draft.S3Bucket;
            S3PrefixBox.Text = draft.S3KeyPrefix;
            S3PathStyleBox.IsChecked = draft.S3UsePathStyle;
            S3PublicBaseBox.Text = draft.S3PublicBaseUrl;
            S3SignedGetBox.IsChecked = draft.S3UseSignedGetUrls;
            S3ExpiryBox.Text = ((int)draft.S3SignedGetUrlExpiry.TotalMinutes).ToString(System.Globalization.CultureInfo.InvariantCulture);
            S3AccessBox.Password = draft.S3AccessKey ?? string.Empty;
            S3SecretBox.Password = draft.S3SecretKey ?? string.Empty;
            S3SessionBox.Password = draft.S3SessionToken ?? string.Empty;
            SelectSecondary(draft.SecondaryS3ProfileId);
            UpdateBackendVisibility(draft.Backend);
        }
        finally
        {
            isLoading = false;
        }
    }

    private void SaveSelectedFields()
    {
        if (ProfilesList.SelectedItem is not ProfileDraft draft)
        {
            return;
        }

        draft.Name = NameBox.Text.Trim();
        draft.Backend = SelectedBackend();
        draft.Endpoint = EndpointBox.Text.Trim();
        draft.ZiplineApiKey = EmptyToNull(ZiplineTokenBox.Password);
        draft.S3Region = S3RegionBox.Text.Trim();
        draft.S3Bucket = S3BucketBox.Text.Trim();
        draft.S3KeyPrefix = S3PrefixBox.Text.Trim();
        draft.S3UsePathStyle = S3PathStyleBox.IsChecked == true;
        draft.S3PublicBaseUrl = EmptyToNull(S3PublicBaseBox.Text);
        draft.S3UseSignedGetUrls = S3SignedGetBox.IsChecked == true;
        draft.S3SignedGetUrlExpiry = TimeSpan.FromMinutes(ParsePositiveInt(S3ExpiryBox.Text, 30));
        draft.S3AccessKey = EmptyToNull(S3AccessBox.Password);
        draft.S3SecretKey = EmptyToNull(S3SecretBox.Password);
        draft.S3SessionToken = EmptyToNull(S3SessionBox.Password);
        draft.SecondaryS3ProfileId = draft.Backend == UploadBackend.ZiplineV4 && SecondaryProfileBox.SelectedItem is ProfileDraft secondary ? secondary.Id : null;
        RefreshDisplayNames();
    }

    private string? ValidateAll()
    {
        if (drafts.Count == 0)
        {
            return "Add at least one upload profile.";
        }

        foreach (var draft in drafts)
        {
            var error = ValidateDraft(draft);
            if (error is not null)
            {
                return error;
            }
        }


        var runtimeError = ValidateRuntimePreferences();
        if (runtimeError is not null)
        {
            return runtimeError;
        }

        return null;
    }

    private static string? ValidateDraft(ProfileDraft draft)
    {
        if (string.IsNullOrWhiteSpace(draft.Name))
        {
            return "Every profile needs a name.";
        }

        if (draft.Backend == UploadBackend.ZiplineV4)
        {
            if (!Uri.TryCreate(draft.Endpoint, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            {
                return $"{draft.Name}: Zipline endpoint must be a valid HTTPS URL.";
            }

            if (string.IsNullOrWhiteSpace(draft.ZiplineApiKey))
            {
                return $"{draft.Name}: Zipline API token is required.";
            }
        }
        else
        {
            if (!Uri.TryCreate(draft.Endpoint, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
            {
                return $"{draft.Name}: S3 endpoint must be a valid HTTP or HTTPS URL.";
            }

            if (string.IsNullOrWhiteSpace(draft.S3Region) || string.IsNullOrWhiteSpace(draft.S3Bucket))
            {
                return $"{draft.Name}: S3 region and bucket are required.";
            }

            if (string.IsNullOrWhiteSpace(draft.S3AccessKey) || string.IsNullOrWhiteSpace(draft.S3SecretKey))
            {
                return $"{draft.Name}: S3 access key and secret key are required.";
            }
        }


        return null;
    }
    private void UploaderFiltersList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isLoading)
        {
            return;
        }

        LoadSelectedUploaderFilter();
    }

    private void AddUploaderFilter_Click(object sender, RoutedEventArgs e)
    {
        var row = ReadUploaderFilterEditor(Guid.NewGuid().ToString("N"));
        if (row is null)
        {
            return;
        }

        uploaderFilterRows.Add(row);
        UploaderFiltersList.SelectedItem = row;
        UploaderFiltersList.Items.Refresh();
    }

    private void UpdateUploaderFilter_Click(object sender, RoutedEventArgs e)
    {
        if (UploaderFiltersList.SelectedItem is not UploaderFilterRow selected)
        {
            ValidationText.Text = "Select an extension filter to update.";
            return;
        }

        var row = ReadUploaderFilterEditor(selected.Id);
        if (row is null)
        {
            return;
        }

        var index = uploaderFilterRows.IndexOf(selected);
        uploaderFilterRows[index] = row;
        UploaderFiltersList.SelectedItem = row;
        UploaderFiltersList.Items.Refresh();
    }

    private void DeleteUploaderFilter_Click(object sender, RoutedEventArgs e)
    {
        if (UploaderFiltersList.SelectedItem is not UploaderFilterRow selected)
        {
            return;
        }

        var index = uploaderFilterRows.IndexOf(selected);
        uploaderFilterRows.Remove(selected);
        UploaderFiltersList.SelectedIndex = uploaderFilterRows.Count == 0 ? -1 : Math.Min(index, uploaderFilterRows.Count - 1);
        LoadSelectedUploaderFilter();
    }

    private void RefreshRoutingProfilePickers()
    {
        var routing = CurrentRoutingFromControls();
        SetRoutingItems(RoutingImageProfileBox, routing.ImageProfileId);
        SetRoutingItems(RoutingFileProfileBox, routing.FileProfileId);
        SetRoutingItems(RoutingTextProfileBox, routing.TextProfileId);
        SetRoutingItems(RoutingShortenerProfileBox, routing.ShortenerProfileId);

        var selectedFilterProfileId = SelectedProfileId(UploaderFilterProfileBox);
        UploaderFilterProfileBox.ItemsSource = ProfileOptions(includeDefault: false);
        SelectProfileOption(UploaderFilterProfileBox, selectedFilterProfileId);
    }

    private DestinationRoutingConfig CurrentRoutingFromControls()
    {
        if (RoutingImageProfileBox is null || RoutingImageProfileBox.ItemsSource is null)
        {
            return runtimeDraft.DestinationRouting ?? new DestinationRoutingConfig();
        }

        return new DestinationRoutingConfig(
            SelectedProfileId(RoutingImageProfileBox),
            SelectedProfileId(RoutingFileProfileBox),
            SelectedProfileId(RoutingTextProfileBox),
            SelectedProfileId(RoutingShortenerProfileBox));
    }

    private void SetRoutingItems(System.Windows.Controls.ComboBox comboBox, string? selectedProfileId)
    {
        comboBox.ItemsSource = ProfileOptions(includeDefault: true);
        SelectProfileOption(comboBox, selectedProfileId);
    }

    private IReadOnlyList<ProfileOption> ProfileOptions(bool includeDefault)
    {
        var options = new List<ProfileOption>();
        if (includeDefault)
        {
            options.Add(new ProfileOption(null, "Active profile"));
        }

        options.AddRange(drafts.Select(draft => new ProfileOption(draft.Id, draft.Name)));
        return options;
    }

    private void SelectProfileOption(System.Windows.Controls.ComboBox comboBox, string? profileId)
    {
        var options = comboBox.ItemsSource?.Cast<ProfileOption>().ToArray() ?? [];
        comboBox.SelectedItem = options.FirstOrDefault(option => string.Equals(option.ProfileId, profileId, StringComparison.Ordinal)) ?? options.FirstOrDefault();
    }

    private static string? SelectedProfileId(System.Windows.Controls.ComboBox comboBox) =>
        comboBox.SelectedItem is ProfileOption option ? option.ProfileId : null;

    private void LoadUploaderFilters()
    {
        uploaderFilterRows.Clear();
        foreach (var rule in runtimeDraft.UploaderFilters ?? [])
        {
            var normalized = rule.Normalized;
            if (normalized.Extensions.Count == 0 || !ProfileExists(normalized.ProfileId))
            {
                continue;
            }

            uploaderFilterRows.Add(UploaderFilterRow.From(normalized));
        }

        UploaderFiltersList.ItemsSource = uploaderFilterRows;
        UploaderFiltersList.SelectedIndex = uploaderFilterRows.Count > 0 ? 0 : -1;
        LoadSelectedUploaderFilter();
    }


    private void PruneUploaderFiltersForExistingProfiles()
    {
        for (var i = uploaderFilterRows.Count - 1; i >= 0; i--)
        {
            if (!ProfileExists(uploaderFilterRows[i].ProfileId))
            {
                uploaderFilterRows.RemoveAt(i);
            }
        }
    }
    private void LoadSelectedUploaderFilter()
    {
        isLoading = true;
        try
        {
            if (UploaderFiltersList.SelectedItem is UploaderFilterRow row)
            {
                UploaderFilterExtensionsBox.Text = row.ExtensionsText;
                SelectProfileOption(UploaderFilterProfileBox, row.ProfileId);
            }
            else
            {
                UploaderFilterExtensionsBox.Text = string.Empty;
                SelectProfileOption(UploaderFilterProfileBox, drafts.FirstOrDefault()?.Id);
            }
        }
        finally
        {
            isLoading = false;
        }
    }

    private UploaderFilterRow? ReadUploaderFilterEditor(string id)
    {
        var extensions = ParseExtensionsInput(UploaderFilterExtensionsBox.Text);
        if (extensions.Count == 0)
        {
            ValidationText.Text = "Extension filters need at least one extension.";
            return null;
        }

        var profileId = SelectedProfileId(UploaderFilterProfileBox);
        if (!ProfileExists(profileId))
        {
            ValidationText.Text = "Choose a profile for the extension filter.";
            return null;
        }

        ValidationText.Text = string.Empty;
        return new UploaderFilterRow(id, extensions, profileId!);
    }

    private IReadOnlyList<UploaderFilterRule> ReadUploaderFilters() =>
        uploaderFilterRows
            .Select(row => row.ToRule().Normalized)
            .Where(rule => rule.Extensions.Count > 0 && ProfileExists(rule.ProfileId))
            .ToArray();

    private DestinationRoutingConfig ReadDestinationRouting() => new(
        ExistingProfileOrNull(SelectedProfileId(RoutingImageProfileBox)),
        ExistingProfileOrNull(SelectedProfileId(RoutingFileProfileBox)),
        ExistingProfileOrNull(SelectedProfileId(RoutingTextProfileBox)),
        ExistingProfileOrNull(SelectedProfileId(RoutingShortenerProfileBox)));

    private string? ExistingProfileOrNull(string? profileId) => ProfileExists(profileId) ? profileId : null;

    private bool ProfileExists(string? profileId) =>
        !string.IsNullOrWhiteSpace(profileId) && drafts.Any(draft => string.Equals(draft.Id, profileId, StringComparison.Ordinal));

    private static IReadOnlyList<string> ParseExtensionsInput(string raw)
    {
        var parts = raw.Split([',', ';', ' ', '\n', '\r', '\t'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return UploaderFilterRule.NormalizeExtensions(parts);
    }
    private void LoadRuntimePreferences()
    {
        isLoading = true;
        try
        {
            CopyUrlAfterUploadBox.IsChecked = runtimeDraft.CopyUrlAfterUpload;
            CopyImageAfterUploadBox.IsChecked = runtimeDraft.CopyImageAfterUpload;
            OpenUrlAfterUploadBox.IsChecked = runtimeDraft.OpenUrlAfterUpload;
            ShowNotificationAfterUploadBox.IsChecked = runtimeDraft.ShowNotificationAfterUpload;
            AfterCaptureCopyUrlBox.IsChecked = runtimeDraft.AfterCaptureCopyUrl;
            AfterCaptureCopyImageAndUrlBox.IsChecked = runtimeDraft.AfterCaptureCopyImageAndUrl;
            OpenEditorAfterCaptureBox.IsChecked = runtimeDraft.OpenEditorAfterCapture;
            SelectRedactionPolicy(runtimeDraft.RedactionPolicy);
            SelectPalette(runtimeDraft.ActivePaletteId);
            DefaultFileExpirySecondsBox.Text = runtimeDraft.DefaultFileExpirySeconds.ToString(System.Globalization.CultureInfo.InvariantCulture);
            EnableOcrIndexingBox.IsChecked = runtimeDraft.EnableOcrIndexing;
            var clipboardRules = runtimeDraft.ClipboardRules ?? new ClipboardUploadRules();
            ClipboardShortenUrlBox.IsChecked = clipboardRules.ShortenUrl;
            ClipboardUploadUrlContentsBox.IsChecked = clipboardRules.UploadUrlContents;
            ClipboardShareUrlAfterUploadBox.IsChecked = clipboardRules.ShareUrlAfterUpload;
            ClipboardUploadTextContentsBox.IsChecked = clipboardRules.UploadTextContents;
            ClipboardAutoIndexFolderBox.IsChecked = clipboardRules.AutoIndexFolder;
            SmartRedactionBlackBoxBox.IsChecked = runtimeDraft.SmartRedactionRenderMode == SmartRedactionRenderMode.BlackBox;
            var detectorPrefs = (runtimeDraft.SmartRedactionDetectors ?? SmartRedactionDetectorPreferences.Default).Normalized;
            SmartRedactionFaceBox.IsChecked = detectorPrefs.Face;
            SmartRedactionBarcodeBox.IsChecked = detectorPrefs.Barcode;
            SmartRedactionConfidenceBox.Text = detectorPrefs.MinimumConfidence.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
            CaptureIncludeCursorBox.IsChecked = runtimeDraft.CaptureIncludeCursor;
            CaptureDelaySecondsBox.Text = runtimeDraft.CaptureDelaySeconds.ToString(System.Globalization.CultureInfo.InvariantCulture);
            CaptureFixedRegionEnabledBox.IsChecked = runtimeDraft.CaptureFixedRegionEnabled;
            CaptureFixedRegionXBox.Text = runtimeDraft.CaptureFixedRegionX.ToString(System.Globalization.CultureInfo.InvariantCulture);
            CaptureFixedRegionYBox.Text = runtimeDraft.CaptureFixedRegionY.ToString(System.Globalization.CultureInfo.InvariantCulture);
            CaptureFixedRegionWidthBox.Text = runtimeDraft.CaptureFixedRegionWidth.ToString(System.Globalization.CultureInfo.InvariantCulture);
            CaptureFixedRegionHeightBox.Text = runtimeDraft.CaptureFixedRegionHeight.ToString(System.Globalization.CultureInfo.InvariantCulture);
            CaptureShowInfoOverlayBox.IsChecked = runtimeDraft.CaptureShowInfoOverlay;
            CaptureSnapSizesBox.Text = CaptureSnapSize.FormatList(runtimeDraft.CaptureSnapSizes);
            CaptureMirrorToScreenshotsFolderBox.IsChecked = runtimeDraft.CaptureMirrorToScreenshotsFolder;
            CaptureScreenshotsFolderBox.Text = runtimeDraft.CaptureScreenshotsFolder;
            ShortenerProviderBox.SelectedIndex = runtimeDraft.ShortenerProvider == "customGetTemplate" ? 1 : 0;
            ShortenerTemplateBox.Text = runtimeDraft.ShortenerCustomGetTemplate;
            UrlRegexReplaceEnabledBox.IsChecked = runtimeDraft.UrlRegexReplaceEnabled;
            UrlRegexPatternBox.Text = runtimeDraft.UrlRegexPattern;
            UrlRegexReplacementBox.Text = runtimeDraft.UrlRegexReplacement;
            UpdateShortenerVisibility(SelectedShortenerProvider());
            UpdateUrlRegexEnabledState();
            LoadCloudflareAllowlistPreferences();
            LoadHotKeyBindings(runtimeDraft.HotKeys ?? HotKeyBindings.Defaults);
        }
        finally
        {
            isLoading = false;
        }
    }
    private void SaveRuntimePreferences()
    {
        runtimeDraft = runtimeDraft with
        {
            CopyUrlAfterUpload = CopyUrlAfterUploadBox.IsChecked == true,
            CopyImageAfterUpload = CopyImageAfterUploadBox.IsChecked == true,
            OpenUrlAfterUpload = OpenUrlAfterUploadBox.IsChecked == true,
            ShowNotificationAfterUpload = ShowNotificationAfterUploadBox.IsChecked == true,
            AfterCaptureCopyUrl = AfterCaptureCopyUrlBox.IsChecked == true,
            AfterCaptureCopyImageAndUrl = AfterCaptureCopyImageAndUrlBox.IsChecked == true,
            OpenEditorAfterCapture = OpenEditorAfterCaptureBox.IsChecked == true,
            RedactionPolicy = SelectedRedactionPolicy(),
            ActivePaletteId = SelectedPaletteId(),
            DefaultFileExpirySeconds = ParsePositiveInt(DefaultFileExpirySecondsBox.Text, 86400),
            EnableOcrIndexing = EnableOcrIndexingBox.IsChecked == true,
            ClipboardRules = new ClipboardUploadRules(
                ClipboardShortenUrlBox.IsChecked == true,
                ClipboardUploadUrlContentsBox.IsChecked == true,
                ClipboardShareUrlAfterUploadBox.IsChecked == true,
                ClipboardUploadTextContentsBox.IsChecked == true,
                ClipboardAutoIndexFolderBox.IsChecked == true),
            SmartRedactionRenderMode = SmartRedactionBlackBoxBox.IsChecked == true ? SmartRedactionRenderMode.BlackBox : SmartRedactionRenderMode.Pixelate,
            SmartRedactionDetectors = new SmartRedactionDetectorPreferences(
                Face: SmartRedactionFaceBox.IsChecked == true,
                Barcode: SmartRedactionBarcodeBox.IsChecked == true,
                MinimumConfidence: ParseDouble(SmartRedactionConfidenceBox.Text, SmartRedactionDetectorPreferences.Default.MinimumConfidence)).Normalized,
            CaptureIncludeCursor = CaptureIncludeCursorBox.IsChecked == true,
            CaptureDelaySeconds = ParseInt(CaptureDelaySecondsBox.Text, 0),
            CaptureFixedRegionEnabled = CaptureFixedRegionEnabledBox.IsChecked == true,
            CaptureFixedRegionX = ParseInt(CaptureFixedRegionXBox.Text, 0),
            CaptureFixedRegionY = ParseInt(CaptureFixedRegionYBox.Text, 0),
            CaptureFixedRegionWidth = ParsePositiveInt(CaptureFixedRegionWidthBox.Text, 1280),
            CaptureFixedRegionHeight = ParsePositiveInt(CaptureFixedRegionHeightBox.Text, 720),
            CaptureShowInfoOverlay = CaptureShowInfoOverlayBox.IsChecked == true,
            CaptureSnapSizes = CaptureSnapSize.ParseList(CaptureSnapSizesBox.Text),
            CaptureMirrorToScreenshotsFolder = CaptureMirrorToScreenshotsFolderBox.IsChecked == true,
            CaptureScreenshotsFolder = CaptureScreenshotsFolderBox.Text.Trim(),
            ShortenerProvider = SelectedShortenerProvider(),
            ShortenerCustomGetTemplate = ShortenerTemplateBox.Text.Trim(),
            UrlRegexReplaceEnabled = UrlRegexReplaceEnabledBox.IsChecked == true,
            UrlRegexPattern = UrlRegexPatternBox.Text,
            UrlRegexReplacement = UrlRegexReplacementBox.Text,
            HotKeys = ReadHotKeyBindings(),
            UploaderFilters = ReadUploaderFilters(),
            DestinationRouting = ReadDestinationRouting(),
            CloudflareAllowlist = ReadCloudflareAllowlistConfig()
        };
    }

    private void LoadCloudflareAllowlistPreferences()
    {
        var config = (runtimeDraft.CloudflareAllowlist ?? new CloudflareAllowlistConfig()).Normalized;
        CloudflareAllowlistEnabledBox.IsChecked = config.Enabled;
        CloudflareAccountIdBox.Text = config.AccountId;
        CloudflareListIdBox.Text = config.ListId;
        CloudflareDeviceNameBox.Text = config.DeviceName;
        CloudflareIntervalMinutesBox.Text = config.CheckIntervalMinutes.ToString(System.Globalization.CultureInfo.InvariantCulture);
        CloudflareTokenBox.Password = string.Empty;
        RefreshCloudflareTokenStatus();
    }

    private CloudflareAllowlistConfig ReadCloudflareAllowlistConfig() => new CloudflareAllowlistConfig(
        CloudflareAllowlistEnabledBox.IsChecked == true,
        CloudflareAccountIdBox.Text.Trim(),
        CloudflareListIdBox.Text.Trim(),
        CloudflareDeviceNameBox.Text.Trim(),
        ParsePositiveInt(CloudflareIntervalMinutesBox.Text, 15)).Normalized;

    private void SaveCloudflareTokenIfProvided()
    {
        if (cloudflareManager is not null && !string.IsNullOrWhiteSpace(CloudflareTokenBox.Password))
        {
            cloudflareManager.ApiToken = CloudflareTokenBox.Password;
            CloudflareTokenBox.Password = string.Empty;
        }

        RefreshCloudflareTokenStatus();
    }

    private void RefreshCloudflareTokenStatus()
    {
        CloudflareTokenStatusText.Text = cloudflareManager?.HasApiToken == true ? "Token saved" : "No token saved";
    }

    private void ClearCloudflareToken_Click(object sender, RoutedEventArgs e)
    {
        CloudflareTokenBox.Password = string.Empty;
        if (cloudflareManager is not null)
        {
            cloudflareManager.ApiToken = null;
        }

        RefreshCloudflareTokenStatus();
    }

    private async void UpdateCloudflareNow_Click(object sender, RoutedEventArgs e)
    {
        if (cloudflareManager is null)
        {
            ValidationText.Text = "Cloudflare allowlist is not ready.";
            return;
        }

        SaveRuntimePreferences();
        var error = ValidateRuntimePreferences();
        if (error is not null)
        {
            ValidationText.Text = error;
            return;
        }

        try
        {
            SaveCloudflareTokenIfProvided();
            await preferencesStore.SaveAsync(runtimeDraft);
            cloudflareManager.ApplyCurrentPreferences();
            ValidationText.Text = "Updating Cloudflare allowlist...";
            var result = await cloudflareManager.UpdateNowAsync();
            ValidationText.Text = result.IsSuccess ? result.Value?.Message ?? "Cloudflare allowlist updated." : result.Error ?? "Cloudflare allowlist update failed.";
        }
        catch (Exception ex)
        {
            ValidationText.Text = "Cloudflare allowlist update failed: " + ex.Message;
        }
    }
    private void BrowseScreenshotsFolder_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Choose screenshots folder",
            UseDescriptionForTitle = true
        };

        if (!string.IsNullOrWhiteSpace(CaptureScreenshotsFolderBox.Text) && Directory.Exists(CaptureScreenshotsFolderBox.Text))
        {
            dialog.SelectedPath = CaptureScreenshotsFolderBox.Text;
        }

        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            CaptureScreenshotsFolderBox.Text = dialog.SelectedPath;
            CaptureMirrorToScreenshotsFolderBox.IsChecked = true;
        }
    }

    private void LoadHotKeyKeyItems()
    {
        foreach (var combo in HotKeyComboBoxes())
        {
            combo.ItemsSource = HotKeyShortcut.AllowedKeys;
        }
    }

    private void LoadHotKeyBindings(HotKeyBindings bindings)
    {
        var normalized = bindings.Normalized;
        SetHotKey(CaptureRegionHotKeyBox, CaptureRegionCtrlBox, CaptureRegionShiftBox, CaptureRegionAltBox, CaptureRegionWinBox, normalized.CaptureRegionUpload);
        SetHotKey(CaptureRegionExpiringHotKeyBox, CaptureRegionExpiringCtrlBox, CaptureRegionExpiringShiftBox, CaptureRegionExpiringAltBox, CaptureRegionExpiringWinBox, normalized.CaptureRegionUploadExpiring);
        SetHotKey(CaptureRegionFrozenHotKeyBox, CaptureRegionFrozenCtrlBox, CaptureRegionFrozenShiftBox, CaptureRegionFrozenAltBox, CaptureRegionFrozenWinBox, normalized.CaptureRegionUploadFrozen);
        SetHotKey(UploadClipboardHotKeyBox, UploadClipboardCtrlBox, UploadClipboardShiftBox, UploadClipboardAltBox, UploadClipboardWinBox, normalized.UploadClipboard);
    }

    private HotKeyBindings ReadHotKeyBindings() => new HotKeyBindings(
        ReadHotKey(CaptureRegionHotKeyBox, CaptureRegionCtrlBox, CaptureRegionShiftBox, CaptureRegionAltBox, CaptureRegionWinBox),
        ReadHotKey(CaptureRegionExpiringHotKeyBox, CaptureRegionExpiringCtrlBox, CaptureRegionExpiringShiftBox, CaptureRegionExpiringAltBox, CaptureRegionExpiringWinBox),
        ReadHotKey(CaptureRegionFrozenHotKeyBox, CaptureRegionFrozenCtrlBox, CaptureRegionFrozenShiftBox, CaptureRegionFrozenAltBox, CaptureRegionFrozenWinBox),
        ReadHotKey(UploadClipboardHotKeyBox, UploadClipboardCtrlBox, UploadClipboardShiftBox, UploadClipboardAltBox, UploadClipboardWinBox)).Normalized;

    private static void SetHotKey(System.Windows.Controls.ComboBox keyBox, System.Windows.Controls.CheckBox ctrlBox, System.Windows.Controls.CheckBox shiftBox, System.Windows.Controls.CheckBox altBox, System.Windows.Controls.CheckBox winBox, HotKeyShortcut shortcut)
    {
        var normalized = shortcut.Normalized;
        keyBox.SelectedItem = normalized.Key;
        ctrlBox.IsChecked = normalized.Control;
        shiftBox.IsChecked = normalized.Shift;
        altBox.IsChecked = normalized.Alt;
        winBox.IsChecked = normalized.Windows;
    }

    private static HotKeyShortcut ReadHotKey(System.Windows.Controls.ComboBox keyBox, System.Windows.Controls.CheckBox ctrlBox, System.Windows.Controls.CheckBox shiftBox, System.Windows.Controls.CheckBox altBox, System.Windows.Controls.CheckBox winBox) =>
        new HotKeyShortcut(
            keyBox.SelectedItem as string ?? keyBox.Text,
            ctrlBox.IsChecked == true,
            shiftBox.IsChecked == true,
            altBox.IsChecked == true,
            winBox.IsChecked == true).Normalized;

    private void SetHotKeyEditorEnabled(bool enabled)
    {
        foreach (var combo in HotKeyComboBoxes())
        {
            combo.IsEnabled = enabled;
        }

        foreach (var checkBox in HotKeyModifierBoxes())
        {
            checkBox.IsEnabled = enabled;
        }
    }

    private System.Windows.Controls.ComboBox[] HotKeyComboBoxes() =>
    [
        CaptureRegionHotKeyBox,
        CaptureRegionExpiringHotKeyBox,
        CaptureRegionFrozenHotKeyBox,
        UploadClipboardHotKeyBox
    ];

    private System.Windows.Controls.CheckBox[] HotKeyModifierBoxes() =>
    [
        CaptureRegionCtrlBox, CaptureRegionShiftBox, CaptureRegionAltBox, CaptureRegionWinBox,
        CaptureRegionExpiringCtrlBox, CaptureRegionExpiringShiftBox, CaptureRegionExpiringAltBox, CaptureRegionExpiringWinBox,
        CaptureRegionFrozenCtrlBox, CaptureRegionFrozenShiftBox, CaptureRegionFrozenAltBox, CaptureRegionFrozenWinBox,
        UploadClipboardCtrlBox, UploadClipboardShiftBox, UploadClipboardAltBox, UploadClipboardWinBox
    ];
    private string? ValidateRuntimePreferences()
    {
        if (runtimeDraft.DefaultFileExpirySeconds is < 60 or > 5 * 24 * 60 * 60)
        {
            return "Default expiry must be between 60 seconds and 5 days.";
        }

        if (runtimeDraft.FileNameAutoIncrement <= 0)
        {
            return "File name auto-increment must be positive.";
        }

        if (runtimeDraft.CaptureDelaySeconds is < 0 or > 5)
        {
            return "Capture delay must be between 0 and 5 seconds.";
        }

        if (runtimeDraft.CaptureFixedRegionWidth <= 0 || runtimeDraft.CaptureFixedRegionHeight <= 0)
        {
            return "Fixed capture region width and height must be positive.";
        }

        if (runtimeDraft.CaptureMirrorToScreenshotsFolder && !string.IsNullOrWhiteSpace(runtimeDraft.CaptureScreenshotsFolder))
        {
            try
            {
                _ = AppStoragePaths.NormalizeUserDirectory(runtimeDraft.CaptureScreenshotsFolder);
            }
            catch (Exception ex)
            {
                return "Screenshots folder is not a valid path: " + ex.Message;
            }
        }

        if (runtimeDraft.ShortenerProvider == "customGetTemplate" && !runtimeDraft.ShortenerCustomGetTemplate.Contains("{url}", StringComparison.Ordinal))
        {
            return "Custom shortener template must contain {url}.";
        }

        var cloudflare = runtimeDraft.CloudflareAllowlist?.Normalized ?? new CloudflareAllowlistConfig();
        if (cloudflare.Enabled)
        {
            if (string.IsNullOrWhiteSpace(cloudflare.AccountId) || string.IsNullOrWhiteSpace(cloudflare.ListId))
            {
                return "Cloudflare allowlist needs an account ID and IP list.";
            }

            if (cloudflareManager?.HasApiToken != true && string.IsNullOrWhiteSpace(CloudflareTokenBox.Password))
            {
                return "Cloudflare allowlist needs an API token.";
            }
        }

        return null;
    }

    private ImageUploadFormat SelectedImageUploadFormat()
    {
        if (ImageUploadFormatBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag && Enum.TryParse<ImageUploadFormat>(tag, ignoreCase: true, out var format))
        {
            return format;
        }

        return ImageUploadFormat.Png;
    }

    private void SelectImageUploadFormat(ImageUploadFormat format)
    {
        foreach (System.Windows.Controls.ComboBoxItem item in ImageUploadFormatBox.Items)
        {
            if (item.Tag is string tag && Enum.TryParse<ImageUploadFormat>(tag, ignoreCase: true, out var candidate) && candidate == format)
            {
                ImageUploadFormatBox.SelectedItem = item;
                return;
            }
        }

        ImageUploadFormatBox.SelectedIndex = 0;
    }
    private UploadRedactionPolicy SelectedRedactionPolicy() =>
        RedactionPolicyBox.SelectedIndex switch
        {
            1 => UploadRedactionPolicy.AutoRedact,
            2 => UploadRedactionPolicy.Off,
            _ => UploadRedactionPolicy.AskBeforeUpload
        };

    private void SelectRedactionPolicy(UploadRedactionPolicy policy)
    {
        RedactionPolicyBox.SelectedIndex = policy switch
        {
            UploadRedactionPolicy.AutoRedact => 1,
            UploadRedactionPolicy.Off => 2,
            _ => 0
        };
    }

    private string SelectedPaletteId() =>
        ActivePaletteBox.SelectedItem is ComboBoxItem item && item.Tag is string tag ? tag : "classic";

    private void SelectPalette(string paletteId)
    {
        foreach (var item in ActivePaletteBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Tag as string, paletteId, StringComparison.OrdinalIgnoreCase))
            {
                ActivePaletteBox.SelectedItem = item;
                return;
            }
        }

        ActivePaletteBox.SelectedIndex = 0;
    }

    private void ActivePaletteBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isLoading)
        {
            return;
        }

        UpdateCustomPaletteVisibility();
    }

    private void BuildCustomPaletteEditor()
    {
        customPaletteBoxes.Clear();
        CustomPaletteFieldsGrid.ColumnDefinitions.Clear();
        CustomPaletteFieldsGrid.RowDefinitions.Clear();
        CustomPaletteFieldsGrid.Children.Clear();
        CustomPaletteFieldsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
        CustomPaletteFieldsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        for (var index = 0; index < CustomPaletteFields.Length; index++)
        {
            var field = CustomPaletteFields[index];
            CustomPaletteFieldsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var label = new TextBlock
            {
                Text = field.Label,
                Margin = new Thickness(0, 0, 12, 6),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetRow(label, index);
            Grid.SetColumn(label, 0);
            CustomPaletteFieldsGrid.Children.Add(label);

            var box = new System.Windows.Controls.TextBox
            {
                Height = 28,
                Margin = new Thickness(0, 0, 0, 6),
                ToolTip = field.Key
            };
            Grid.SetRow(box, index);
            Grid.SetColumn(box, 1);
            CustomPaletteFieldsGrid.Children.Add(box);
            customPaletteBoxes[field.Key] = box;
        }
    }

    private UiPaletteData CurrentCustomPalette() =>
        (runtimeDraft.CustomPalette ?? UiPaletteCatalog.DefaultCustomSeed()).Normalized(UiPaletteCatalog.DefaultCustomSeed());

    private void LoadCustomPaletteFields(UiPaletteData palette)
    {
        foreach (var (key, _) in CustomPaletteFields)
        {
            customPaletteBoxes[key].Text = GetPaletteColor(palette, key).ToHexRgba();
        }
    }

    private UiPaletteData ReadCustomPalette()
    {
        var current = CurrentCustomPalette();
        return new UiPaletteData(
            ReadPaletteColor("windowGradientA", current.WindowGradientA),
            ReadPaletteColor("windowGradientB", current.WindowGradientB),
            ReadPaletteColor("windowGradientC", current.WindowGradientC),
            ReadPaletteColor("windowRadialSpot", current.WindowRadialSpot),
            ReadPaletteColor("railPanelAccent", current.RailPanelAccent),
            ReadPaletteColor("contextPanelAccent", current.ContextPanelAccent),
            ReadPaletteColor("captureAccent", current.CaptureAccent),
            ReadPaletteColor("uploadAccent", current.UploadAccent),
            ReadPaletteColor("workflowsAccent", current.WorkflowsAccent),
            ReadPaletteColor("toolsAccent", current.ToolsAccent),
            ReadPaletteColor("afterCaptureAccent", current.AfterCaptureAccent),
            ReadPaletteColor("afterUploadAccent", current.AfterUploadAccent),
            ReadPaletteColor("destinationsAccent", current.DestinationsAccent),
            ReadPaletteColor("settingsAccent", current.SettingsAccent),
            ReadPaletteColor("historyAccent", current.HistoryAccent)).Normalized(UiPaletteCatalog.DefaultCustomSeed());
    }

    private RgbaColor ReadPaletteColor(string key, RgbaColor fallback) =>
        customPaletteBoxes.TryGetValue(key, out var box) && RgbaColor.TryParseHex(box.Text, out var color)
            ? color
            : fallback.Normalized;

    private static RgbaColor GetPaletteColor(UiPaletteData palette, string key) => key switch
    {
        "windowGradientA" => palette.WindowGradientA,
        "windowGradientB" => palette.WindowGradientB,
        "windowGradientC" => palette.WindowGradientC,
        "windowRadialSpot" => palette.WindowRadialSpot,
        "railPanelAccent" => palette.RailPanelAccent,
        "contextPanelAccent" => palette.ContextPanelAccent,
        "captureAccent" => palette.CaptureAccent,
        "uploadAccent" => palette.UploadAccent,
        "workflowsAccent" => palette.WorkflowsAccent,
        "toolsAccent" => palette.ToolsAccent,
        "afterCaptureAccent" => palette.AfterCaptureAccent,
        "afterUploadAccent" => palette.AfterUploadAccent,
        "destinationsAccent" => palette.DestinationsAccent,
        "settingsAccent" => palette.SettingsAccent,
        "historyAccent" => palette.HistoryAccent,
        _ => UiPaletteCatalog.DefaultCustomSeed().WindowGradientA
    };

    private void UpdateCustomPaletteVisibility() =>
        CustomPalettePanel.Visibility = string.Equals(SelectedPaletteId(), UiPaletteCatalog.CustomId, StringComparison.OrdinalIgnoreCase)
            ? Visibility.Visible
            : Visibility.Collapsed;

    private void ResetCustomPalette_Click(object sender, RoutedEventArgs e)
    {
        LoadCustomPaletteFields(UiPaletteCatalog.DefaultCustomSeed());
        UpdateCustomPaletteVisibility();
    }
    private string SelectedShortenerProvider() =>
        ShortenerProviderBox.SelectedIndex == 1 ? "customGetTemplate" : "tinyURL";

    private void UpdateShortenerVisibility(string provider)
    {
        var visibility = provider == "customGetTemplate" ? Visibility.Visible : Visibility.Collapsed;
        ShortenerTemplateLabel.Visibility = visibility;
        ShortenerTemplateBox.Visibility = visibility;
    }

    private void UpdateUrlRegexEnabledState()
    {
        var enabled = UrlRegexReplaceEnabledBox.IsEnabled && UrlRegexReplaceEnabledBox.IsChecked == true;
        UrlRegexPatternBox.IsEnabled = enabled;
        UrlRegexReplacementBox.IsEnabled = enabled;
    }

    private void RefreshSecondaryProfiles()
    {
        var selectedId = ProfilesList.SelectedItem is ProfileDraft selected ? selected.SecondaryS3ProfileId : null;
        SecondaryProfileBox.ItemsSource = drafts.Where(draft => draft.Backend == UploadBackend.S3Compatible).ToArray();
        SelectSecondary(selectedId);
    }

    private void SelectSecondary(string? id)
    {
        SecondaryProfileBox.SelectedItem = id is null ? null : drafts.FirstOrDefault(draft => draft.Id == id);
    }

    private void RefreshDisplayNames()
    {
        foreach (var draft in drafts)
        {
            draft.IsActive = draft.Id == activeProfileId;
        }

        ProfilesList.Items.Refresh();
    }

    private void UpdateBackendVisibility(UploadBackend backend)
    {
        var ziplineVisibility = backend == UploadBackend.ZiplineV4 ? Visibility.Visible : Visibility.Collapsed;
        var s3Visibility = backend == UploadBackend.S3Compatible ? Visibility.Visible : Visibility.Collapsed;
        ZiplineTokenLabel.Visibility = ziplineVisibility;
        ZiplineTokenBox.Visibility = ziplineVisibility;
        foreach (var element in new FrameworkElement[]
        {
            S3RegionLabel, S3RegionBox, S3BucketLabel, S3BucketBox, S3PrefixLabel, S3PrefixBox,
            S3PathStyleBox, S3PublicBaseLabel, S3PublicBaseBox, S3SignedGetBox, S3ExpiryLabel,
            S3ExpiryBox, S3AccessLabel, S3AccessBox, S3SecretLabel, S3SecretBox, S3SessionLabel, S3SessionBox
        })
        {
            element.Visibility = s3Visibility;
        }

        SecondaryProfileBox.IsEnabled = backend == UploadBackend.ZiplineV4;
    }

    private void SetEditorEnabled(bool enabled)
    {
        NameBox.IsEnabled = enabled;
        BackendBox.IsEnabled = enabled;
        EndpointBox.IsEnabled = enabled;
        ZiplineTokenBox.IsEnabled = enabled;
        S3RegionBox.IsEnabled = enabled;
        S3BucketBox.IsEnabled = enabled;
        S3PrefixBox.IsEnabled = enabled;
        S3PathStyleBox.IsEnabled = enabled;
        S3PublicBaseBox.IsEnabled = enabled;
        S3SignedGetBox.IsEnabled = enabled;
        S3ExpiryBox.IsEnabled = enabled;
        S3AccessBox.IsEnabled = enabled;
        S3SecretBox.IsEnabled = enabled;
        S3SessionBox.IsEnabled = enabled;
        SecondaryProfileBox.IsEnabled = enabled;
        CopyUrlAfterUploadBox.IsEnabled = enabled;
        CopyImageAfterUploadBox.IsEnabled = enabled;
        OpenUrlAfterUploadBox.IsEnabled = enabled;
        ShowNotificationAfterUploadBox.IsEnabled = enabled;
        AfterCaptureCopyUrlBox.IsEnabled = enabled;
        AfterCaptureCopyImageAndUrlBox.IsEnabled = enabled;
        OpenEditorAfterCaptureBox.IsEnabled = enabled;
        RedactionPolicyBox.IsEnabled = enabled;
        ActivePaletteBox.IsEnabled = enabled;
        CustomPalettePanel.IsEnabled = enabled;
        DefaultFileExpirySecondsBox.IsEnabled = enabled;
        EnableOcrIndexingBox.IsEnabled = enabled;
        ImageUploadFormatBox.IsEnabled = enabled;
        StripImageMetadataBeforeUploadBox.IsEnabled = enabled;
        FileUploadUseNamePatternBox.IsEnabled = enabled;
        FileUploadUseRandom16NameBox.IsEnabled = enabled;
        FileNamePatternBox.IsEnabled = enabled;
        FileNameAutoIncrementBox.IsEnabled = enabled;
        FileUploadReplaceProblematicCharactersBox.IsEnabled = enabled;
        SmartRedactionBlackBoxBox.IsEnabled = enabled;
        SmartRedactionFaceBox.IsEnabled = enabled;
        SmartRedactionBarcodeBox.IsEnabled = enabled;
        SmartRedactionConfidenceBox.IsEnabled = enabled;
        ClipboardShortenUrlBox.IsEnabled = enabled;
        ClipboardUploadUrlContentsBox.IsEnabled = enabled;
        ClipboardShareUrlAfterUploadBox.IsEnabled = enabled;
        ClipboardUploadTextContentsBox.IsEnabled = enabled;
        ClipboardAutoIndexFolderBox.IsEnabled = enabled;
        CaptureIncludeCursorBox.IsEnabled = enabled;
        CaptureDelaySecondsBox.IsEnabled = enabled;
        CaptureFixedRegionEnabledBox.IsEnabled = enabled;
        CaptureFixedRegionXBox.IsEnabled = enabled;
        CaptureFixedRegionYBox.IsEnabled = enabled;
        CaptureFixedRegionWidthBox.IsEnabled = enabled;
        CaptureFixedRegionHeightBox.IsEnabled = enabled;
        CaptureShowInfoOverlayBox.IsEnabled = enabled;
        CaptureSnapSizesBox.IsEnabled = enabled;
        CaptureMirrorToScreenshotsFolderBox.IsEnabled = enabled;
        CaptureScreenshotsFolderBox.IsEnabled = enabled;
        ShortenerProviderBox.IsEnabled = enabled;
        ShortenerTemplateBox.IsEnabled = enabled;
        UrlRegexReplaceEnabledBox.IsEnabled = enabled;
        UpdateUrlRegexEnabledState();
        RoutingImageProfileBox.IsEnabled = enabled;
        RoutingFileProfileBox.IsEnabled = enabled;
        RoutingTextProfileBox.IsEnabled = enabled;
        RoutingShortenerProfileBox.IsEnabled = enabled;
        UploaderFiltersList.IsEnabled = enabled;
        UploaderFilterExtensionsBox.IsEnabled = enabled;
        UploaderFilterProfileBox.IsEnabled = enabled;
        CloudflareAllowlistEnabledBox.IsEnabled = enabled;
        CloudflareAccountIdBox.IsEnabled = enabled;
        CloudflareListIdBox.IsEnabled = enabled;
        CloudflareDeviceNameBox.IsEnabled = enabled;
        CloudflareIntervalMinutesBox.IsEnabled = enabled;
        CloudflareTokenBox.IsEnabled = enabled;
        SetHotKeyEditorEnabled(enabled);
    }

    private UploadBackend SelectedBackend() =>
        BackendBox.SelectedIndex == 1 ? UploadBackend.S3Compatible : UploadBackend.ZiplineV4;

    private static string? EmptyToNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static int ParsePositiveInt(string value, int fallback) =>
        int.TryParse(value.Trim(), out var parsed) && parsed > 0 ? parsed : fallback;

    private static int ParseInt(string value, int fallback) =>
        int.TryParse(value.Trim(), out var parsed) ? parsed : fallback;

    private static double ParseDouble(string value, double fallback) =>
        double.TryParse(value.Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsed) ? parsed : fallback;


    private sealed record ProfileOption(string? ProfileId, string DisplayName);

    private sealed class UploaderFilterRow
    {
        public UploaderFilterRow(string id, IReadOnlyList<string> extensions, string profileId)
        {
            Id = id;
            Extensions = extensions;
            ProfileId = profileId;
        }

        public string Id { get; }

        public IReadOnlyList<string> Extensions { get; }

        public string ProfileId { get; }

        public string ExtensionsText => string.Join(", ", Extensions);

        public string DisplayName => $"{ExtensionsText} -> {ProfileId}";

        public UploaderFilterRule ToRule() => new(Id, Extensions, ProfileId);

        public static UploaderFilterRow From(UploaderFilterRule rule) => new(rule.Id, rule.Extensions, rule.ProfileId);
    }
    private sealed class ProfileDraft
    {
        public string Id { get; init; } = Guid.NewGuid().ToString("N");
        public string Name { get; set; } = string.Empty;
        public UploadBackend Backend { get; set; }
        public string Endpoint { get; set; } = string.Empty;
        public string? ZiplineApiKey { get; set; }
        public string S3Region { get; set; } = "us-east-1";
        public string S3Bucket { get; set; } = string.Empty;
        public string S3KeyPrefix { get; set; } = "uploads";
        public bool S3UsePathStyle { get; set; } = true;
        public string? S3PublicBaseUrl { get; set; }
        public bool S3UseSignedGetUrls { get; set; }
        public TimeSpan S3SignedGetUrlExpiry { get; set; } = TimeSpan.FromMinutes(30);
        public string? S3AccessKey { get; set; }
        public string? S3SecretKey { get; set; }
        public string? S3SessionToken { get; set; }
        public string? SecondaryS3ProfileId { get; set; }
        public bool IsActive { get; set; }
        public string DisplayName => IsActive ? Name + " (active)" : Name;

        public static ProfileDraft New(UploadBackend backend, string name) => new()
        {
            Name = name,
            Backend = backend,
            Endpoint = backend == UploadBackend.ZiplineV4 ? "https://" : "https://",
            S3ConfigDefaults = backend
        };

        private UploadBackend S3ConfigDefaults
        {
            set
            {
                if (value == UploadBackend.S3Compatible)
                {
                    S3Region = "us-east-1";
                    S3KeyPrefix = "uploads";
                    S3UsePathStyle = true;
                    S3SignedGetUrlExpiry = TimeSpan.FromMinutes(30);
                }
            }
        }

        public static ProfileDraft From(UploadProfile profile, ProfileSecrets secrets, bool isActive)
        {
            var cfg = profile.S3Config;
            return new ProfileDraft
            {
                Id = profile.Id,
                Name = profile.Name,
                Backend = profile.Backend,
                Endpoint = profile.Backend == UploadBackend.S3Compatible ? cfg?.Endpoint ?? profile.Endpoint : profile.Endpoint,
                ZiplineApiKey = secrets.ZiplineApiKey,
                S3Region = cfg?.Region ?? "us-east-1",
                S3Bucket = cfg?.Bucket ?? string.Empty,
                S3KeyPrefix = cfg?.KeyPrefix ?? "uploads",
                S3UsePathStyle = cfg?.UsePathStyle ?? true,
                S3PublicBaseUrl = cfg?.PublicBaseUrl,
                S3UseSignedGetUrls = cfg?.UseSignedGetUrls ?? false,
                S3SignedGetUrlExpiry = cfg?.SignedGetUrlExpiry ?? TimeSpan.FromMinutes(30),
                S3AccessKey = secrets.S3AccessKey,
                S3SecretKey = secrets.S3SecretKey,
                S3SessionToken = secrets.S3SessionToken,
                SecondaryS3ProfileId = profile.Backend == UploadBackend.ZiplineV4 ? profile.SecondaryS3ProfileId : null,
                IsActive = isActive
            };
        }

        public UploadProfile ToProfile()
        {
            var cfg = Backend == UploadBackend.S3Compatible
                ? new S3DestinationConfig(
                    Endpoint,
                    S3Region,
                    S3Bucket,
                    S3KeyPrefix,
                    S3UsePathStyle,
                    S3PublicBaseUrl,
                    S3UseSignedGetUrls,
                    S3SignedGetUrlExpiry)
                : null;
            return new UploadProfile(Id, Name, Backend == UploadBackend.ZiplineV4 ? Endpoint : string.Empty, Backend, cfg, Backend == UploadBackend.ZiplineV4 ? SecondaryS3ProfileId : null);
        }

        public ProfileSecrets ToSecrets() => new(ZiplineApiKey, S3AccessKey, S3SecretKey, S3SessionToken);
    }
}















