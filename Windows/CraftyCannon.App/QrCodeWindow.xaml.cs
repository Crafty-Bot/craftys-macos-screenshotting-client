using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace CraftyCannon.App;

public partial class QrCodeWindow : Window
{
    private readonly Action<string, string>? notify;
    private BitmapSource? currentQrImage;

    public QrCodeWindow(Action<string, string>? notify = null)
    {
        this.notify = notify;
        InitializeComponent();
        Regenerate();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }

    private void InputTextBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        InputPlaceholder.Visibility = string.IsNullOrEmpty(InputTextBox.Text) ? Visibility.Visible : Visibility.Collapsed;
        Regenerate();
    }

    private void Regenerate()
    {
        currentQrImage = QrCodeService.Generate(InputTextBox.Text ?? string.Empty);
        QrImage.Source = currentQrImage;
        EmptyQrText.Visibility = currentQrImage is null ? Visibility.Visible : Visibility.Collapsed;
        CopyQrButton.IsEnabled = currentQrImage is not null;
        SavePngButton.IsEnabled = currentQrImage is not null;
        SetGenerateStatus(string.Empty);
    }

    private void CopyQrButton_Click(object sender, RoutedEventArgs e)
    {
        if (currentQrImage is null)
        {
            return;
        }

        System.Windows.Clipboard.SetImage(currentQrImage);
        SetGenerateStatus("Copied");
        notify?.Invoke("Copied", "QR code image");
    }

    private void SavePngButton_Click(object sender, RoutedEventArgs e)
    {
        if (currentQrImage is null)
        {
            return;
        }

        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Title = "Save QR Code",
            FileName = "qrcode.png",
            Filter = "PNG image (*.png)|*.png",
            AddExtension = true,
            DefaultExt = ".png",
            OverwritePrompt = true
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var bytes = QrCodeService.EncodePng(currentQrImage);
            if (bytes.Length == 0)
            {
                throw new InvalidOperationException("Failed to encode PNG");
            }

            File.WriteAllBytes(dialog.FileName, bytes);
            var savedName = Path.GetFileName(dialog.FileName);
            SetGenerateStatus("Saved: " + savedName);
            notify?.Invoke("Saved", savedName);
        }
        catch (Exception ex)
        {
            SetGenerateStatus("Save failed: " + ex.Message, isError: true);
            notify?.Invoke("Save failed", ex.Message);
        }
    }

    private void DecodeClipboardButton_Click(object sender, RoutedEventArgs e)
    {
        ClearDecode();
        if (!System.Windows.Clipboard.ContainsImage())
        {
            SetDecodeStatus("Clipboard has no image", isError: true);
            return;
        }

        var image = System.Windows.Clipboard.GetImage();
        if (image is null)
        {
            SetDecodeStatus("Clipboard has no image", isError: true);
            return;
        }

        DecodeImage(image);
    }

    private void DecodeFileButton_Click(object sender, RoutedEventArgs e)
    {
        ClearDecode();
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Choose Image",
            CheckFileExists = true,
            Multiselect = false,
            Filter = "Image files|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.tif;*.tiff;*.webp|All files|*.*"
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            DecodeImage(QrCodeService.LoadImage(dialog.FileName));
        }
        catch
        {
            SetDecodeStatus("Failed to load image", isError: true);
        }
    }

    private void DecodeImage(BitmapSource image)
    {
        var decoded = QrCodeService.Decode(image);
        if (string.IsNullOrEmpty(decoded))
        {
            SetDecodeStatus("No QR code found", isError: true);
            DecodedTextBox.Text = string.Empty;
            return;
        }

        DecodedTextBox.Text = decoded;
        SetDecodeStatus(string.Empty);
    }

    private void CopyDecodedButton_Click(object sender, RoutedEventArgs e)
    {
        var trimmed = DecodedTextBox.Text.Trim();
        if (trimmed.Length == 0)
        {
            return;
        }

        System.Windows.Clipboard.SetText(trimmed);
        SetDecodeStatus("Copied");
        notify?.Invoke("Copied", "Decoded text");
    }

    private void DecodedTextBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        CopyDecodedButton.IsEnabled = DecodedTextBox.Text.Trim().Length > 0;

    private void ClearDecode()
    {
        DecodedTextBox.Text = string.Empty;
        SetDecodeStatus(string.Empty);
    }

    private void SetGenerateStatus(string message, bool isError = false) =>
        SetStatus(GenerateStatusText, message, isError);

    private void SetDecodeStatus(string message, bool isError = false) =>
        SetStatus(DecodeStatusText, message, isError);

    private static void SetStatus(System.Windows.Controls.TextBlock target, string message, bool isError)
    {
        target.Text = message;
        target.Foreground = isError
            ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(161, 38, 38))
            : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(89, 98, 115));
    }
}



