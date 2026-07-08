using System.IO;
using System.Windows;
using CraftyCannon.Capture;
using CraftyCannon.Core;
using CraftyCannon.Ocr;

namespace CraftyCannon.App;

public sealed class WindowsHistoryEditorLauncher : IEditorLauncher
{
    private readonly IUploadHistoryStore history;
    private readonly string tempRoot;
    private readonly Func<Window?> ownerProvider;
    private readonly Func<string, Task<bool>> saveAndUploadAsync;
    private readonly IScreenCaptureService? screenCapture;
    private readonly ISmartRedactionDetector? smartRedactionDetector;
    private readonly Func<SmartRedactionRenderMode> redactionRenderModeProvider;
    private readonly Action<string, string>? notify;

    public WindowsHistoryEditorLauncher(
        IUploadHistoryStore history,
        string tempRoot,
        Func<Window?> ownerProvider,
        Func<string, Task<bool>> saveAndUploadAsync,
        IScreenCaptureService? screenCapture = null,
        ISmartRedactionDetector? smartRedactionDetector = null,
        Func<SmartRedactionRenderMode>? redactionRenderModeProvider = null,
        Action<string, string>? notify = null)
    {
        this.history = history;
        this.tempRoot = tempRoot;
        this.ownerProvider = ownerProvider;
        this.saveAndUploadAsync = saveAndUploadAsync;
        this.screenCapture = screenCapture;
        this.smartRedactionDetector = smartRedactionDetector;
        this.redactionRenderModeProvider = redactionRenderModeProvider ?? (() => SmartRedactionRenderMode.Pixelate);
        this.notify = notify;
    }

    public bool TryOpenRecord(string recordId)
    {
        var record = history.Records.FirstOrDefault(candidate => candidate.Id == recordId);
        if (record is null || !UploadHistoryActions.CanEditImage(record) || !File.Exists(record.LocalFilePath))
        {
            notify?.Invoke("CraftyCannon", "No local file to edit");
            return false;
        }

        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            var window = new EditorWindow(record, tempRoot, saveAndUploadAsync, screenCapture, smartRedactionDetector, redactionRenderModeProvider, notify)
            {
                Owner = ownerProvider()
            };
            window.Show();
            window.Activate();
        });
        return true;
    }
}
