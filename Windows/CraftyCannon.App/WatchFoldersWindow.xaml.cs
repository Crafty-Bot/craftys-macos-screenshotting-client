using System.IO;
using System.Windows;
using System.Windows.Controls;
using CraftyCannon.Core;
using WinForms = System.Windows.Forms;

namespace CraftyCannon.App;

public partial class WatchFoldersWindow : Window
{
    private readonly RuntimePreferencesStore preferencesStore;
    private readonly Action applyPreferences;
    private List<WatchFolderRule> rules = [];
    private bool loading;

    public WatchFoldersWindow(RuntimePreferencesStore preferencesStore, Action applyPreferences)
    {
        InitializeComponent();
        this.preferencesStore = preferencesStore;
        this.applyPreferences = applyPreferences;
        LoadFromPreferences();
    }

    private void LoadFromPreferences()
    {
        loading = true;
        rules = preferencesStore.Current.WatchFolderRules?.ToList() ?? [];
        EnabledBox.IsChecked = preferencesStore.Current.WatchFoldersEnabled;
        ModeBox.SelectedIndex = 0;
        ClearFields();
        RefreshRulesList();
        loading = false;
    }

    private async void EnabledBox_Changed(object sender, RoutedEventArgs e)
    {
        if (loading)
        {
            return;
        }

        await SaveAsync();
    }

    private void RulesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RulesList.SelectedItem is not RuleRow row)
        {
            ClearFields();
            return;
        }

        var rule = rules.First(candidate => candidate.Id == row.Id);
        PathBox.Text = rule.Path;
        FilterBox.Text = rule.FileFilter;
        RuleEnabledBox.IsChecked = rule.Enabled;
        IncludeSubdirectoriesBox.IsChecked = rule.IncludeSubdirectories;
        SelectMode(rule.Mode);
        ExpiryBox.Text = rule.ExpirySeconds?.ToString() ?? "0";
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new WinForms.FolderBrowserDialog
        {
            Description = "Choose Watch Folder",
            UseDescriptionForTitle = true,
            SelectedPath = Directory.Exists(PathBox.Text) ? PathBox.Text : string.Empty
        };
        if (dialog.ShowDialog() == WinForms.DialogResult.OK)
        {
            PathBox.Text = dialog.SelectedPath;
        }
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        var rule = ReadDraft(newId: true, preserveEnabled: true);
        if (rule is null)
        {
            return;
        }

        rules.Add(rule);
        await SaveAsync(rule.Id);
    }

    private async void Update_Click(object sender, RoutedEventArgs e)
    {
        if (RulesList.SelectedItem is not RuleRow row)
        {
            Add_Click(sender, e);
            return;
        }

        var existing = rules.First(candidate => candidate.Id == row.Id);
        var updated = ReadDraft(newId: false, preserveEnabled: existing.Enabled, id: existing.Id);
        if (updated is null)
        {
            return;
        }

        var index = rules.FindIndex(candidate => candidate.Id == existing.Id);
        rules[index] = updated;
        await SaveAsync(updated.Id);
    }

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (RulesList.SelectedItem is not RuleRow row)
        {
            return;
        }

        rules.RemoveAll(rule => rule.Id == row.Id);
        await SaveAsync(rules.FirstOrDefault()?.Id);
    }

    private WatchFolderRule? ReadDraft(bool newId, bool preserveEnabled, string? id = null)
    {
        var path = PathBox.Text.Trim();
        if (path.Length == 0)
        {
            StatusText.Text = "Path is required.";
            return null;
        }

        var expiry = ParseExpirySeconds(ExpiryBox.Text);
        if (expiry < 0 || expiry > 432000)
        {
            StatusText.Text = "Expiry must be between 0 and 432000 seconds.";
            return null;
        }

        return new WatchFolderRule(
            newId ? Guid.NewGuid().ToString("N") : id ?? Guid.NewGuid().ToString("N"),
            path,
            IncludeSubdirectoriesBox.IsChecked == true,
            string.IsNullOrWhiteSpace(FilterBox.Text) ? "*" : FilterBox.Text.Trim(),
            SelectedMode(),
            expiry == 0 ? null : expiry,
            RuleEnabledBox.IsChecked == true);
    }

    private async Task SaveAsync(string? selectedId = null)
    {
        var normalized = preferencesStore.Current with
        {
            WatchFoldersEnabled = EnabledBox.IsChecked == true,
            WatchFolderRules = rules
        };
        await preferencesStore.SaveAsync(normalized);
        rules = preferencesStore.Current.WatchFolderRules?.ToList() ?? [];
        RefreshRulesList(selectedId);
        applyPreferences();
        StatusText.Text = "Watch folder preferences saved.";
    }

    private void RefreshRulesList(string? selectedId = null)
    {
        RulesList.ItemsSource = rules.Select(rule => new RuleRow(rule.Id, RuleTitle(rule))).ToArray();
        if (selectedId is not null)
        {
            RulesList.SelectedItem = RulesList.Items.Cast<RuleRow>().FirstOrDefault(row => row.Id == selectedId);
        }
    }

    private void ClearFields()
    {
        PathBox.Text = string.Empty;
        FilterBox.Text = "*";
        RuleEnabledBox.IsChecked = true;
        IncludeSubdirectoriesBox.IsChecked = true;
        ModeBox.SelectedIndex = 0;
        ExpiryBox.Text = "0";
    }

    private void SelectMode(WatchFolderMode mode)
    {
        foreach (ComboBoxItem item in ModeBox.Items)
        {
            if (string.Equals((string?)item.Tag, mode.ToString(), StringComparison.OrdinalIgnoreCase))
            {
                ModeBox.SelectedItem = item;
                return;
            }
        }

        ModeBox.SelectedIndex = 0;
    }

    private WatchFolderMode SelectedMode()
    {
        var tag = (ModeBox.SelectedItem as ComboBoxItem)?.Tag as string;
        return Enum.TryParse<WatchFolderMode>(tag, ignoreCase: true, out var mode) ? mode : WatchFolderMode.Auto;
    }

    private static int ParseExpirySeconds(string raw) =>
        int.TryParse(raw.Trim(), out var seconds) ? Math.Clamp(seconds, 0, 432000) : 0;

    private static string RuleTitle(WatchFolderRule rule) =>
        $"[{(rule.Enabled ? "x" : " ")}] {rule.Path}  -  {ModeRawValue(rule.Mode)}";

    private static string ModeRawValue(WatchFolderMode mode) => mode switch
    {
        WatchFolderMode.ImageOnly => "imageOnly",
        WatchFolderMode.FileOnly => "fileOnly",
        _ => "auto"
    };

    private sealed record RuleRow(string Id, string Title)
    {
        public override string ToString() => Title;
    }
}