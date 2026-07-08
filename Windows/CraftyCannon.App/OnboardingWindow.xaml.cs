using System.Windows;
using System.Windows.Controls;
using CraftyCannon.Core;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public partial class OnboardingWindow : Window
{
    private readonly Func<UploadProfile, Task<EndpointValidationResult>> ziplineValidator;

    public OnboardingWindow(Func<UploadProfile, Task<EndpointValidationResult>>? ziplineValidator = null)
    {
        InitializeComponent();
        this.ziplineValidator = ziplineValidator ?? (profile => new ZiplineClient(new HttpClientTransport()).ValidateAsync(profile));
        PresetBox.SelectedIndex = 0;
        ProfileNameBox.Text = "Primary";
        ApplyPreset("Zipline");
    }

    public OnboardingResult? Result { get; private set; }

    private void PresetBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded)
        {
            return;
        }

        ApplyPreset(SelectedPreset());
    }

    private void BackendBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded)
        {
            return;
        }

        UpdateBackendVisibility(SelectedBackend());
    }

    private async void Continue_Click(object sender, RoutedEventArgs e)
    {
        var backend = SelectedBackend();
        var profileName = ProfileNameBox.Text.Trim();
        var endpoint = EndpointBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(profileName) || string.IsNullOrWhiteSpace(endpoint))
        {
            ValidationText.Text = "Profile name and endpoint are required.";
            return;
        }

        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var endpointUri) || endpointUri.Scheme != Uri.UriSchemeHttps || endpointUri.Host is null)
        {
            ValidationText.Text = backend == UploadBackend.S3Compatible
                ? "S3 endpoint must be a valid HTTPS URL."
                : "Zipline endpoint must be a valid HTTPS URL.";
            return;
        }

        if (backend == UploadBackend.ZiplineV4)
        {
            var token = ZiplineTokenBox.Password.Trim();
            if (string.IsNullOrWhiteSpace(token))
            {
                ValidationText.Text = "Zipline API secret is required.";
                return;
            }

            var profile = new UploadProfile(Guid.NewGuid().ToString("N"), profileName, endpoint, UploadBackend.ZiplineV4, null, null);
            ValidationText.Text = "Validating endpoint...";
            var validation = await ziplineValidator(profile);
            if (!validation.IsValid)
            {
                ValidationText.Text = "Endpoint validation failed: " + validation.Message;
                return;
            }

            Result = new OnboardingResult(profile, new ProfileSecrets(ZiplineApiKey: token));
            DialogResult = true;
            Close();
            return;
        }

        var region = S3RegionBox.Text.Trim();
        var bucket = S3BucketBox.Text.Trim();
        var accessKey = S3AccessBox.Text.Trim();
        var secretKey = S3SecretBox.Password.Trim();
        if (string.IsNullOrWhiteSpace(region) || string.IsNullOrWhiteSpace(bucket) || string.IsNullOrWhiteSpace(accessKey) || string.IsNullOrWhiteSpace(secretKey))
        {
            ValidationText.Text = "S3 region, bucket, access key ID, and secret access key are required.";
            return;
        }

        var config = new S3DestinationConfig(endpoint, region, bucket, "uploads", true, null, false, TimeSpan.FromMinutes(30));
        Result = new OnboardingResult(
            new UploadProfile(Guid.NewGuid().ToString("N"), profileName, string.Empty, UploadBackend.S3Compatible, config, null),
            new ProfileSecrets(S3AccessKey: accessKey, S3SecretKey: secretKey, S3SessionToken: EmptyToNull(S3SessionBox.Password)));
        DialogResult = true;
        Close();
    }

    private void ApplyPreset(string preset)
    {
        switch (preset)
        {
            case "S3":
                BackendBox.SelectedIndex = 1;
                BackendBox.IsEnabled = false;
                EndpointBox.Text = "https://s3.amazonaws.com";
                break;
            case "Custom":
                BackendBox.SelectedIndex = 0;
                BackendBox.IsEnabled = true;
                EndpointBox.Text = string.Empty;
                break;
            default:
                BackendBox.SelectedIndex = 0;
                BackendBox.IsEnabled = false;
                EndpointBox.Text = "https://zipline.example.com";
                break;
        }

        S3RegionBox.Text = string.IsNullOrWhiteSpace(S3RegionBox.Text) ? "us-east-1" : S3RegionBox.Text;
        UpdateBackendVisibility(SelectedBackend());
        ValidationText.Text = string.Empty;
    }

    private string SelectedPreset() =>
        PresetBox.SelectedItem is ComboBoxItem item && item.Tag is string tag ? tag : "Zipline";

    private UploadBackend SelectedBackend() => BackendBox.SelectedIndex == 1 ? UploadBackend.S3Compatible : UploadBackend.ZiplineV4;

    private void UpdateBackendVisibility(UploadBackend backend)
    {
        var ziplineVisibility = backend == UploadBackend.ZiplineV4 ? Visibility.Visible : Visibility.Collapsed;
        var s3Visibility = backend == UploadBackend.S3Compatible ? Visibility.Visible : Visibility.Collapsed;
        ZiplineTokenLabel.Visibility = ziplineVisibility;
        ZiplineTokenBox.Visibility = ziplineVisibility;
        foreach (var element in new FrameworkElement[]
        {
            S3RegionLabel, S3RegionBox, S3BucketLabel, S3BucketBox, S3AccessLabel, S3AccessBox, S3SecretLabel, S3SecretBox, S3SessionLabel, S3SessionBox
        })
        {
            element.Visibility = s3Visibility;
        }
    }

    private static string? EmptyToNull(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

public sealed record OnboardingResult(UploadProfile Profile, ProfileSecrets Secrets);