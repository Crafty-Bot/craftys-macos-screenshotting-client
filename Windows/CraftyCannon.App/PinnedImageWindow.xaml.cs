using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;

namespace CraftyCannon.App;

public partial class PinnedImageWindow : Window
{
    public string Id { get; } = Guid.NewGuid().ToString("N");

    private readonly BitmapSource image;

    public PinnedImageWindow(BitmapSource image, string title = "Pinned")
    {
        InitializeComponent();
        this.image = image;
        Title = title;
        PinnedImage.Source = image;

        Width = Math.Max(240, Math.Min(640, image.PixelWidth));
        Height = Math.Max(180, Math.Min(420, image.PixelHeight));
    }

    private void Root_MouseEnter(object sender, System.Windows.Input.MouseEventArgs e) =>
        ControlPanel.Opacity = 1.0;

    private void Root_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e) =>
        ControlPanel.Opacity = 0.0;

    private void Root_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e) =>
        System.Windows.Clipboard.SetImage(image);

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        Close();
}