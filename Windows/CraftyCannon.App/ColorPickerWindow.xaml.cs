using System.ComponentModel;
using System.Drawing;
using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using WinForms = System.Windows.Forms;
using MediaColor = System.Windows.Media.Color;

namespace CraftyCannon.App;

public partial class ColorPickerWindow : Window
{
    private readonly Action<string, string>? notify;
    private MediaColor color = MediaColor.FromRgb(255, 59, 48);
    private string lastPickSource = "Palette";

    public ColorPickerWindow(Action<string, string>? notify = null)
    {
        this.notify = notify;
        InitializeComponent();
        RefreshColor();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }

    private void PaletteButton_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new WinForms.ColorDialog
        {
            AllowFullOpen = true,
            AnyColor = true,
            FullOpen = true,
            Color = System.Drawing.Color.FromArgb(color.A, color.R, color.G, color.B)
        };

        if (dialog.ShowDialog() != WinForms.DialogResult.OK)
        {
            return;
        }

        color = MediaColor.FromArgb(dialog.Color.A, dialog.Color.R, dialog.Color.G, dialog.Color.B);
        RefreshColor();
    }

    private async void PickFromScreenButton_Click(object sender, RoutedEventArgs e)
    {
        var wasVisible = IsVisible;
        Hide();
        await Task.Delay(120);
        var picked = ScreenColorSamplerWindow.PickColor();
        if (wasVisible)
        {
            Show();
            Activate();
        }

        if (picked is not { } selected)
        {
            return;
        }

        color = selected;
        lastPickSource = "Screen";
        RefreshColor();
    }

    private void CopyHexRgb_Click(object sender, RoutedEventArgs e) => Copy(HexRgbBox.Text);

    private void CopyHexRgba_Click(object sender, RoutedEventArgs e) => Copy(HexRgbaBox.Text);

    private void CopyRgba_Click(object sender, RoutedEventArgs e) => Copy(RgbaBox.Text);

    private void RefreshColor()
    {
        ColorSwatch.Background = new SolidColorBrush(color);
        HexRgbBox.Text = HexRgb(color);
        HexRgbaBox.Text = HexRgba(color);
        RgbaBox.Text = RgbaString(color);
        SourceText.Text = "Source: " + lastPickSource;
    }

    private void Copy(string value)
    {
        System.Windows.Clipboard.SetText(value);
        CopyStatusText.Text = "Copied: " + value;
        notify?.Invoke("Copied", value);
    }

    private static string HexRgb(MediaColor c) =>
        string.Create(CultureInfo.InvariantCulture, $"#{c.R:X2}{c.G:X2}{c.B:X2}");

    private static string HexRgba(MediaColor c) =>
        string.Create(CultureInfo.InvariantCulture, $"#{c.R:X2}{c.G:X2}{c.B:X2}{c.A:X2}");

    private static string RgbaString(MediaColor c) =>
        string.Create(CultureInfo.InvariantCulture, $"rgba({c.R}, {c.G}, {c.B}, {c.A / 255.0:0.000})");

    private sealed class ScreenColorSamplerWindow : Window
    {
        private MediaColor? pickedColor;

        private ScreenColorSamplerWindow()
        {
            var bounds = WinForms.SystemInformation.VirtualScreen;
            Left = bounds.Left;
            Top = bounds.Top;
            Width = bounds.Width;
            Height = bounds.Height;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = new SolidColorBrush(MediaColor.FromArgb(1, 0, 0, 0));
            Topmost = true;
            ShowInTaskbar = false;
            Cursor = System.Windows.Input.Cursors.Cross;
            Focusable = true;
        }

        public static MediaColor? PickColor()
        {
            var picker = new ScreenColorSamplerWindow();
            picker.ShowDialog();
            return picker.pickedColor;
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            pickedColor = SampleCursorPixel();
            Close();
        }

        protected override void OnKeyDown(System.Windows.Input.KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                Close();
            }
        }

        private static MediaColor SampleCursorPixel()
        {
            var point = WinForms.Cursor.Position;
            using var bitmap = new Bitmap(1, 1);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(point, new System.Drawing.Point(0, 0), new System.Drawing.Size(1, 1));
            }

            var sampled = bitmap.GetPixel(0, 0);
            return MediaColor.FromArgb(sampled.A, sampled.R, sampled.G, sampled.B);
        }
    }
}

