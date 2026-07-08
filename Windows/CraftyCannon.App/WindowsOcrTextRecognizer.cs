using System.IO;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;
using CraftyCannon.Ocr;

namespace CraftyCannon.App;

public sealed class WindowsOcrTextRecognizer : IOcrTextRecognizer
{
    public string EngineName => "Windows.Media.Ocr";

    public string? EngineVersion => "winrt-v1";

    public async Task<OcrTextResult> RecognizeAsync(string imagePath, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var engine = OcrEngine.TryCreateFromUserProfileLanguages()
            ?? OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en-US"));
        if (engine is null)
        {
            throw new InvalidOperationException("Windows OCR is not available for the current user languages.");
        }

        var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(imagePath));
        using var stream = await file.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(stream);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        cancellationToken.ThrowIfCancellationRequested();
        var result = await engine.RecognizeAsync(bitmap);
        cancellationToken.ThrowIfCancellationRequested();
        var text = string.Join(Environment.NewLine, result.Lines.Select(line => line.Text).Where(line => !string.IsNullOrWhiteSpace(line)));
        return new OcrTextResult(text, EngineName, engine.RecognizerLanguage?.LanguageTag ?? EngineVersion);
    }
}
