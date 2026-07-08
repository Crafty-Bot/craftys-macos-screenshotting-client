using System.Globalization;
using System.Windows;

namespace CraftyCannon.App;

public partial class ResizePromptWindow : Window
{
    private readonly int originalWidth;
    private readonly int originalHeight;

    public ResizePromptWindow(int width, int height)
    {
        originalWidth = Math.Max(1, width);
        originalHeight = Math.Max(1, height);
        InitializeComponent();
        WidthBox.Text = originalWidth.ToString(CultureInfo.InvariantCulture);
        HeightBox.Text = originalHeight.ToString(CultureInfo.InvariantCulture);
        Loaded += (_, _) =>
        {
            WidthBox.Focus();
            WidthBox.SelectAll();
        };
    }

    public int PixelWidth { get; private set; }

    public int PixelHeight { get; private set; }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        if (!TryParsePositive(WidthBox.Text, out var width) || !TryParsePositive(HeightBox.Text, out var height))
        {
            ValidationText.Text = "Use whole-number pixel dimensions greater than zero.";
            return;
        }

        if (LockAspectBox.IsChecked == true && originalWidth > 0 && originalHeight > 0)
        {
            var aspect = (double)originalHeight / originalWidth;
            var widthChanged = width != originalWidth;
            var heightChanged = height != originalHeight;
            if (widthChanged && !heightChanged)
            {
                height = Math.Max(1, (int)Math.Round(width * aspect));
            }
            else if (heightChanged && !widthChanged)
            {
                width = Math.Max(1, (int)Math.Round(height / aspect));
            }
            else
            {
                height = Math.Max(1, (int)Math.Round(width * aspect));
            }
        }

        PixelWidth = width;
        PixelHeight = height;
        DialogResult = true;
        Close();
    }

    private static bool TryParsePositive(string value, out int result) =>
        int.TryParse(value.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out result) && result > 0;
}