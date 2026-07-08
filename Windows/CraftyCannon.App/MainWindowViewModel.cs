using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using CraftyCannon.Core;

namespace CraftyCannon.App;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private WindowsPortSection selectedSection;
    private string? selectedItem;
    private string filterText = string.Empty;
    private string statusText = "Ready";
    private string historySearchText = string.Empty;
    private string historyStatusFilter = HistoryStatusAll;
    private HistoryRecordViewModel? selectedHistoryRow;

    private const string HistoryStatusAll = "All";

    public MainWindowViewModel()
    {
        Sections = new ObservableCollection<WindowsPortSection>(WindowsPortSections.Default);
        selectedSection = Sections[0];
        selectedItem = selectedSection.Items[0];
        RebuildFilteredItems();
        HistoryStatusFilters = new ObservableCollection<string>([HistoryStatusAll, nameof(UploadStatus.Uploaded), nameof(UploadStatus.Failed), nameof(UploadStatus.Uploading), "Pending"]);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<WindowsPortSection> Sections { get; }

    public ObservableCollection<string> FilteredItems { get; } = [];

    public ObservableCollection<string> HistoryStatusFilters { get; }

    public ObservableCollection<HistoryRecordViewModel> HistoryRows { get; } = [];

    public ObservableCollection<HistoryRecordViewModel> FilteredHistoryRows { get; } = [];

    public WindowsPortSection SelectedSection
    {
        get => selectedSection;
        set
        {
            if (selectedSection == value)
            {
                return;
            }

            selectedSection = value;
            selectedItem = selectedSection.Items.FirstOrDefault();
            RebuildFilteredItems();
            OnPropertyChanged(nameof(SelectedSection));
            OnPropertyChanged(nameof(SelectedItem));
            OnPropertyChanged(nameof(DetailText));
            OnPropertyChanged(nameof(IsHistorySelected));
        }
    }

    public string? SelectedItem
    {
        get => selectedItem;
        set
        {
            if (selectedItem == value)
            {
                return;
            }

            selectedItem = value;
            OnPropertyChanged(nameof(SelectedItem));
            OnPropertyChanged(nameof(DetailText));
        }
    }

    public string FilterText
    {
        get => filterText;
        set
        {
            if (filterText == value)
            {
                return;
            }

            filterText = value;
            RebuildFilteredItems();
            OnPropertyChanged(nameof(FilterText));
        }
    }

    public string StatusText
    {
        get => statusText;
        set
        {
            if (statusText == value)
            {
                return;
            }

            statusText = value;
            OnPropertyChanged(nameof(StatusText));
        }
    }

    public string HistorySearchText
    {
        get => historySearchText;
        set
        {
            if (historySearchText == value)
            {
                return;
            }

            historySearchText = value;
            RebuildFilteredHistoryRows();
            OnPropertyChanged(nameof(HistorySearchText));
        }
    }

    public string HistoryStatusFilter
    {
        get => historyStatusFilter;
        set
        {
            if (historyStatusFilter == value)
            {
                return;
            }

            historyStatusFilter = value;
            RebuildFilteredHistoryRows();
            OnPropertyChanged(nameof(HistoryStatusFilter));
        }
    }

    public HistoryRecordViewModel? SelectedHistoryRow
    {
        get => selectedHistoryRow;
        set
        {
            if (selectedHistoryRow == value)
            {
                return;
            }

            selectedHistoryRow = value;
            OnPropertyChanged(nameof(SelectedHistoryRow));
            OnPropertyChanged(nameof(HasSelectedHistoryRow));
            OnPropertyChanged(nameof(CanCopySelectedHistoryUrl));
            OnPropertyChanged(nameof(CanOpenSelectedHistoryUrl));
            OnPropertyChanged(nameof(CanShortenSelectedHistoryUrl));
            OnPropertyChanged(nameof(CanRevealSelectedHistoryFile));
            OnPropertyChanged(nameof(CanReuploadSelectedHistoryFile));
            OnPropertyChanged(nameof(CanEditSelectedHistoryImage));
            OnPropertyChanged(nameof(CanDeleteSelectedManagedCopy));
        }
    }

    public bool IsHistorySelected => SelectedSection.Name == "History";

    public bool HasSelectedHistoryRow => SelectedHistoryRow is not null;

    public bool CanCopySelectedHistoryUrl => !string.IsNullOrWhiteSpace(SelectedHistoryRow?.PreferredUrl);

    public bool CanOpenSelectedHistoryUrl => CanCopySelectedHistoryUrl;

    public bool CanShortenSelectedHistoryUrl => !string.IsNullOrWhiteSpace(SelectedHistoryRow?.Record.RemoteUrl);

    public bool CanRevealSelectedHistoryFile => SelectedHistoryRow?.HasLocalFile == true;

    public bool CanReuploadSelectedHistoryFile => !string.IsNullOrWhiteSpace(SelectedHistoryRow?.Record.LocalFilePath);

    public bool CanEditSelectedHistoryImage => SelectedHistoryRow?.Record is { } record && UploadHistoryActions.CanEditImage(record) && File.Exists(record.LocalFilePath);

    public bool CanDeleteSelectedManagedCopy => SelectedHistoryRow?.CanDeleteManagedCopy == true;

    public string DetailText =>
        $"This surface is the initial WPF parity shell for {SelectedSection.Name} / {SelectedItem}. " +
        "The command groups intentionally mirror the macOS ShareX-style rail while implementation modules are ported behind stable Windows services.";

    public void SelectHistoryWorkspace()
    {
        var history = Sections.FirstOrDefault(section => section.Name == "History");
        if (history is not null)
        {
            SelectedSection = history;
        }
    }

    public void SetHistoryRecords(IEnumerable<UploadRecord> records)
    {
        var selectedId = SelectedHistoryRow?.Record.Id;
        HistoryRows.Clear();
        foreach (var record in records.OrderByDescending(record => record.CreatedAt).ThenByDescending(record => record.Id))
        {
            HistoryRows.Add(new HistoryRecordViewModel(record));
        }

        RebuildFilteredHistoryRows(selectedId);
    }

    private void RebuildFilteredItems()
    {
        FilteredItems.Clear();
        foreach (var item in selectedSection.Items.Where(MatchesFilter))
        {
            FilteredItems.Add(item);
        }
    }

    private void RebuildFilteredHistoryRows(string? preferredSelectedId = null)
    {
        var selectedId = preferredSelectedId ?? SelectedHistoryRow?.Record.Id;
        FilteredHistoryRows.Clear();
        foreach (var row in HistoryRows.Where(MatchesHistoryFilter))
        {
            FilteredHistoryRows.Add(row);
        }

        SelectedHistoryRow = selectedId is null
            ? FilteredHistoryRows.FirstOrDefault()
            : FilteredHistoryRows.FirstOrDefault(row => row.Record.Id == selectedId) ?? FilteredHistoryRows.FirstOrDefault();
        OnPropertyChanged(nameof(FilteredHistoryRows));
    }

    private bool MatchesFilter(string item) =>
        string.IsNullOrWhiteSpace(filterText) ||
        item.Contains(filterText, StringComparison.CurrentCultureIgnoreCase);

    private bool MatchesHistoryFilter(HistoryRecordViewModel row)
    {
        if (historyStatusFilter == "Pending")
        {
            return false;
        }

        if (historyStatusFilter != HistoryStatusAll && !string.Equals(row.Record.Status.ToString(), historyStatusFilter, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var query = historySearchText.Trim();
        return query.Length == 0 || row.SearchText.Contains(query, StringComparison.CurrentCultureIgnoreCase);
    }

    private void OnPropertyChanged(string propertyName) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class HistoryRecordViewModel
{
    public HistoryRecordViewModel(UploadRecord record)
    {
        Record = record;
    }

    public UploadRecord Record { get; }

    public string FileName => string.IsNullOrWhiteSpace(Record.FileName) ? "-" : Record.FileName;

    public string Status
    {
        get
        {
            var parts = new List<string> { Record.Status.ToString(), Record.SourceKind.ToString() };
            if (Record.OcrStatus != OcrIndexStatus.NotQueued)
            {
                parts.Add("OCR " + Record.OcrStatus);
            }
            if (Record.SecondaryStatus != SecondaryUploadStatus.NotConfigured)
            {
                parts.Add("S3 " + Record.SecondaryStatus);
            }
            return string.Join(" | ", parts);
        }
    }

    public string Progress => Record.Status switch
    {
        UploadStatus.Uploaded => "100%",
        UploadStatus.Uploading => "...",
        UploadStatus.Failed => "Err",
        _ => "-"
    };

    public string Speed => "-";

    public string Elapsed => "-";

    public string Remaining => "-";

    public string Url => !string.IsNullOrWhiteSpace(Record.ErrorMessage) ? "Error" : PreferredUrl ?? Record.RemoteUrl ?? "-";

    public string? PreferredUrl => UploadHistoryActions.PreferredUrl(Record);

    public string CreatedAt => Record.CreatedAt.ToLocalTime().ToString("g");

    public string Profile => string.IsNullOrWhiteSpace(Record.ProfileName) ? "-" : Record.ProfileName;

    public string Source => Record.SourceKind.ToString();

    public string LocalFile => string.IsNullOrWhiteSpace(Record.LocalFilePath) ? "-" : Record.LocalFilePath;

    public string RemotePath => string.IsNullOrWhiteSpace(Record.RemotePath) ? "-" : Record.RemotePath;

    public string Expiry => Record.ExpiresAt?.ToLocalTime().ToString("g") ?? "-";

    public string Secondary => Record.SecondaryStatus == SecondaryUploadStatus.NotConfigured
        ? "Not configured"
        : string.Join(" | ", new[] { Record.SecondaryStatus.ToString(), Record.SecondaryUrl, Record.SecondaryError }.Where(value => !string.IsNullOrWhiteSpace(value))!);

    public string Ocr => Record.OcrStatus == OcrIndexStatus.NotQueued
        ? "Not queued"
        : string.Join(" | ", new[] { Record.OcrStatus.ToString(), Record.OcrEngine, Record.OcrError }.Where(value => !string.IsNullOrWhiteSpace(value))!);

    public string Error => string.IsNullOrWhiteSpace(Record.ErrorMessage) ? "-" : Record.ErrorMessage;

    public bool HasLocalFile => !string.IsNullOrWhiteSpace(Record.LocalFilePath) && File.Exists(Record.LocalFilePath);

    public bool CanDeleteManagedCopy => Record.IsManagedLocalCopy && HasLocalFile;

    public string SearchText => string.Join(" ", new[]
    {
        FileName,
        Status,
        Profile,
        Source,
        Record.RemoteUrl ?? string.Empty,
        Record.ShortenedUrl ?? string.Empty,
        Record.ErrorMessage ?? string.Empty,
        Record.SecondaryUrl ?? string.Empty,
        Record.SecondaryError ?? string.Empty,
        Record.OcrText ?? string.Empty,
        Record.OcrError ?? string.Empty
    });
}






