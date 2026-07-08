using System.Windows;

namespace CraftyCannon.App;

public partial class PromptWindow : Window
{
    public PromptWindow(string title, string prompt, bool multiLine = false, string initialValue = "")
    {
        InitializeComponent();
        Title = title;
        PromptText.Text = prompt;
        ValueBox.AcceptsReturn = multiLine;
        ValueBox.Height = multiLine ? double.NaN : 32;
        ValueBox.Text = initialValue;
        Loaded += (_, _) =>
        {
            ValueBox.Focus();
            ValueBox.SelectAll();
        };
    }

    public string Value => ValueBox.Text;

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
        Close();
    }
}
