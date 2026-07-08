using System.Windows;

namespace CraftyCannon.App;

public partial class MainWindow : Window
{
    public MainWindow(MainWindowViewModel? viewModel = null)
    {
        InitializeComponent();
        DataContext = viewModel ?? new MainWindowViewModel();
    }

    private App CurrentApp => (App)System.Windows.Application.Current;

    private async void CaptureRegion_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureRegionFromWindowAsync();

    private async void CaptureRegionExpiring_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureRegionExpiringFromWindowAsync();

    private async void CaptureFrozenRegion_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureFrozenRegionFromWindowAsync();

    private async void CaptureWindow_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureWindowFromWindowAsync();

    private async void CaptureTopTaskbar_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureTopTaskbarFromWindowAsync();

    private async void CaptureFullScreen_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureFullScreenFromWindowAsync();

    private async void CaptureScreenRecording_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.CaptureScreenRecordingFromWindowAsync();

    private async void UploadClipboard_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadClipboardFromWindowAsync();

    private async void UploadFile_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadFileFromWindowAsync();

    private async void UploadExpiringFile_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadExpiringFileFromWindowAsync();

    private async void UploadUrl_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadRemoteUrlFromWindowAsync();

    private async void ShortenUrl_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.ShortenUrlFromWindowAsync();

    private async void UploadText_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadTextFromWindowAsync();

    private async void UploadFolder_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadFolderBatchFromWindowAsync();

    private async void WatchFolders_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.OpenWatchFoldersFromWindowAsync();

    private async void IndexFolder_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.UploadFolderIndexFromWindowAsync();

    private void HistoryClearSearch_Click(object sender, RoutedEventArgs e) =>
        ((MainWindowViewModel)DataContext).HistorySearchText = string.Empty;

    private void HistoryCopy_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.CopySelectedHistoryUrlFromWindow();

    private void HistoryOpen_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.OpenSelectedHistoryUrlFromWindow();

    private async void HistoryShorten_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.ShortenSelectedHistoryUrlFromWindowAsync();

    private void HistoryReveal_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.RevealSelectedHistoryFileFromWindow();

    private async void HistoryReupload_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.ReuploadSelectedHistoryFileFromWindowAsync();

    private async void HistoryEdit_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.OpenSelectedHistoryInEditorFromWindowAsync();

    private async void HistoryDelete_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.DeleteSelectedManagedHistoryFileFromWindowAsync();

    private void ColorPicker_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.OpenColorPickerFromWindow();

    private void QrCode_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.OpenQrCodeFromWindow();

    private void HashChecker_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.OpenHashCheckerFromWindow();

    private void DirectoryIndexer_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.OpenDirectoryIndexerFromWindow();

    private void PinClipboardImage_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.PinClipboardImageFromWindow();

    private void PinImageFile_Click(object sender, RoutedEventArgs e) =>
        CurrentApp.PinImageFileFromWindow();

    private async void OpenLatestEditor_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.OpenLatestImageInEditorFromWindowAsync();

    private async void Preferences_Click(object sender, RoutedEventArgs e) =>
        await CurrentApp.OpenPreferencesFromWindowAsync();
}










