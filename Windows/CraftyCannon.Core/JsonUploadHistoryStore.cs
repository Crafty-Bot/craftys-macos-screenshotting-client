using System.Text.Json;

namespace CraftyCannon.Core;

public sealed class JsonUploadHistoryStore : IUploadHistoryWriter
{
    private readonly string path;
    private readonly List<UploadRecord> records = [];

    public JsonUploadHistoryStore(AppStoragePaths paths)
    {
        path = paths.HistoryPath;
    }

    public IReadOnlyList<UploadRecord> Records => records;

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        records.Clear();
        if (!File.Exists(path))
        {
            return;
        }

        try
        {
            await using var stream = File.OpenRead(path);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            if (document.RootElement.ValueKind == JsonValueKind.Array)
            {
                var rawRecords = document.RootElement.Deserialize<IReadOnlyList<UploadRecord>>(JsonOptions.Default);
                records.AddRange(rawRecords ?? []);
                return;
            }

            var file = document.RootElement.Deserialize<HistoryFile>(JsonOptions.Default);
            records.AddRange(file?.Records ?? []);
        }
        catch (JsonException)
        {
            records.Clear();
        }
    }

    public async Task UpsertAsync(UploadRecord record, CancellationToken cancellationToken = default)
    {
        var existingIndex = records.FindIndex(existing => existing.Id == record.Id);
        if (existingIndex >= 0)
        {
            records[existingIndex] = record;
        }
        else
        {
            records.Insert(0, record);
        }

        await SaveAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken = default)
    {
        records.RemoveAll(record => record.Id == id);
        await SaveAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task SaveAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await using var stream = File.Create(path);
        var file = new HistoryFile(Version: 1, Records: records);
        await JsonSerializer.SerializeAsync(stream, file, JsonOptions.Default, cancellationToken).ConfigureAwait(false);
    }

    private sealed record HistoryFile(int Version, IReadOnlyList<UploadRecord>? Records);
}

