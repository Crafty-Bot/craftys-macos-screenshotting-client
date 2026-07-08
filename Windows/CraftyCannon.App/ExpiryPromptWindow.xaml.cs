using System.Globalization;
using System.Windows;

namespace CraftyCannon.App;

public partial class ExpiryPromptWindow : Window
{
    private const int MaxSeconds = 5 * 24 * 60 * 60;

    public ExpiryPromptWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => DaysBox.Focus();
    }

    public int ExpirySeconds { get; private set; }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        if (!TryParseNonNegative(DaysBox.Text, out var days) ||
            !TryParseNonNegative(HoursBox.Text, out var hours) ||
            !TryParseNonNegative(MinutesBox.Text, out var minutes))
        {
            ValidationText.Text = "Use whole numbers for days, hours, and minutes.";
            return;
        }

        var seconds = checked((days * 24 * 60 * 60) + (hours * 60 * 60) + (minutes * 60));
        if (seconds <= 0)
        {
            ValidationText.Text = "Expiry must be at least one minute.";
            return;
        }

        if (seconds > MaxSeconds)
        {
            ValidationText.Text = "Expiry cannot exceed 5 days.";
            return;
        }

        ExpirySeconds = seconds;
        DialogResult = true;
        Close();
    }

    private static bool TryParseNonNegative(string value, out int result) =>
        int.TryParse(value.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out result) && result >= 0;
}

