using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using CraftyCannon.Core;

namespace CraftyCannon.App;

public partial class HashCheckerWindow : Window
{
    private readonly Action<string, string>? notify;
    private string? selectedFilePath;
    private int computeGeneration;
    private bool isComputing;
    private HashDigest? currentDigest;

    public HashCheckerWindow(Action<string, string>? notify = null)
    {
        this.notify = notify;
        InitializeComponent();
        Loaded += (_, _) => Recompute();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }

    private void ChooseFile_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Choose File",
            CheckFileExists = true,
            Multiselect = false,
            Filter = "All files|*.*"
        };

        if (dialog.ShowDialog(this) == true)
        {
            selectedFilePath = dialog.FileName;
            FilePathText.Text = selectedFilePath;
            ClearFileButton.IsEnabled = true;
            Recompute();
        }
    }

    private void ClearFile_Click(object sender, RoutedEventArgs e)
    {
        selectedFilePath = null;
        FilePathText.Text = string.Empty;
        ClearFileButton.IsEnabled = false;
        Recompute();
    }

    private void InputTextBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (selectedFilePath is null)
        {
            Recompute();
        }
    }

    private void ExpectedHashBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        UpdateExpectedMatch();

    private void CopyMd5_Click(object sender, RoutedEventArgs e) => CopyHash(Md5Box.Text);
    private void CopySha1_Click(object sender, RoutedEventArgs e) => CopyHash(Sha1Box.Text);
    private void CopySha256_Click(object sender, RoutedEventArgs e) => CopyHash(Sha256Box.Text);

    private async void Recompute()
    {
        ErrorText.Text = string.Empty;
        CopyStatusText.Text = string.Empty;
        currentDigest = null;
        SetDigest(null);

        var filePath = selectedFilePath;
        var text = InputTextBox.Text ?? string.Empty;
        if (filePath is null && text.Length == 0)
        {
            isComputing = false;
            RefreshState();
            UpdateExpectedMatch();
            return;
        }

        var generation = ++computeGeneration;
        isComputing = true;
        RefreshState();

        try
        {
            var digest = filePath is not null
                ? await HashUtilities.ComputeFileAsync(filePath).ConfigureAwait(true)
                : HashUtilities.ComputeText(text);

            if (generation != computeGeneration)
            {
                return;
            }

            currentDigest = digest;
            SetDigest(digest);
        }
        catch (Exception ex)
        {
            if (generation != computeGeneration)
            {
                return;
            }

            ErrorText.Text = ex.Message;
        }
        finally
        {
            if (generation == computeGeneration)
            {
                isComputing = false;
                RefreshState();
                UpdateExpectedMatch();
            }
        }
    }

    private void SetDigest(HashDigest? digest)
    {
        Md5Box.Text = digest?.Md5 ?? string.Empty;
        Sha1Box.Text = digest?.Sha1 ?? string.Empty;
        Sha256Box.Text = digest?.Sha256 ?? string.Empty;
        CopyMd5Button.IsEnabled = !string.IsNullOrWhiteSpace(Md5Box.Text);
        CopySha1Button.IsEnabled = !string.IsNullOrWhiteSpace(Sha1Box.Text);
        CopySha256Button.IsEnabled = !string.IsNullOrWhiteSpace(Sha256Box.Text);
    }

    private void RefreshState()
    {
        ComputingProgress.Visibility = isComputing ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateExpectedMatch()
    {
        var match = currentDigest?.MatchExpected(ExpectedHashBox.Text ?? string.Empty);
        ExpectedMatchText.Text = match ?? string.Empty;
        ExpectedMatchText.Foreground = match == "No match"
            ? new SolidColorBrush(System.Windows.Media.Color.FromRgb(161, 38, 38))
            : new SolidColorBrush(System.Windows.Media.Color.FromRgb(89, 98, 115));
    }

    private void CopyHash(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            return;
        }

        System.Windows.Clipboard.SetText(trimmed);
        CopyStatusText.Text = "Copied";
        notify?.Invoke("Copied", trimmed);
    }
}



