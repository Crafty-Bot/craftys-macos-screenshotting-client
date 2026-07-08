using System.ComponentModel;
using System.IO;
using System.Windows;
using CraftyCannon.Core;
using CraftyCannon.Upload;
using WinForms = System.Windows.Forms;

namespace CraftyCannon.App;

public partial class DirectoryIndexerWindow : Window
{
    private readonly UploadPayloadPreparer preparer;
    private readonly IFileRevealLauncher fileRevealLauncher;
    private readonly Action<string, string>? notify;
    private string? selectedFolderPath;
    private string? outputFilePath;
    private int generation;
    private bool isWorking;

    public DirectoryIndexerWindow(AppStoragePaths paths, IFileRevealLauncher fileRevealLauncher, Action<string, string>? notify = null)
    {
        InitializeComponent();
        this.fileRevealLauncher = fileRevealLauncher;
        this.notify = notify;
        preparer = new UploadPayloadPreparer(paths, new UnusedTransport());
        RefreshState();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }

    private void ChooseFolder_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new WinForms.FolderBrowserDialog
        {
            Description = "Choose Folder",
            UseDescriptionForTitle = true,
            SelectedPath = selectedFolderPath ?? string.Empty,
            ShowNewFolderButton = false
        };

        if (dialog.ShowDialog() != WinForms.DialogResult.OK || string.IsNullOrWhiteSpace(dialog.SelectedPath))
        {
            return;
        }

        selectedFolderPath = dialog.SelectedPath;
        FolderPathText.Text = selectedFolderPath;
        SetStatus(string.Empty);
        RefreshState();
    }

    private async void Generate_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(selectedFolderPath))
        {
            return;
        }

        var token = ++generation;
        isWorking = true;
        outputFilePath = null;
        OutputTextBox.Text = string.Empty;
        SetStatus(string.Empty);
        RefreshState();

        try
        {
            var includeSubdirectories = IncludeSubdirectoriesCheckBox.IsChecked == true;
            var payload = await preparer.PrepareFolderIndexAsync(
                selectedFolderPath,
                includeSubdirectories,
                UploadSourceKind.ManualFolderIndex);
            var text = await File.ReadAllTextAsync(payload.FilePath);
            if (token != generation)
            {
                return;
            }

            outputFilePath = payload.FilePath;
            OutputTextBox.Text = text;
        }
        catch (Exception ex)
        {
            if (token == generation)
            {
                SetStatus(ex.Message, isError: true);
            }
        }
        finally
        {
            if (token == generation)
            {
                isWorking = false;
                RefreshState();
            }
        }
    }

    private void CopyText_Click(object sender, RoutedEventArgs e)
    {
        var trimmed = OutputTextBox.Text.Trim();
        if (trimmed.Length == 0)
        {
            return;
        }

        System.Windows.Clipboard.SetText(trimmed);
        SetStatus("Copied");
        notify?.Invoke("Copied", "Folder index text");
    }

    private void RevealFile_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(outputFilePath) && fileRevealLauncher.TryRevealFile(outputFilePath))
        {
            return;
        }

        SetStatus("Unable to reveal file.", isError: true);
    }

    private void OutputTextBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        RefreshState();

    private void RefreshState()
    {
        WorkingProgress.Visibility = isWorking ? Visibility.Visible : Visibility.Collapsed;
        GenerateButton.IsEnabled = !isWorking && !string.IsNullOrWhiteSpace(selectedFolderPath);
        CopyTextButton.IsEnabled = OutputTextBox.Text.Trim().Length > 0;
        RevealFileButton.IsEnabled = !string.IsNullOrWhiteSpace(outputFilePath);
    }


    private void SetStatus(string message, bool isError = false)
    {
        StatusText.Text = message;
        StatusText.Foreground = isError
            ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(161, 38, 38))
            : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(89, 98, 115));
    }    private sealed class UnusedTransport : IHttpTransport
    {
        public Task<TransportResponse> SendAsync(TransportRequest request, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException("Directory Indexer does not use HTTP transport.");
    }
}



