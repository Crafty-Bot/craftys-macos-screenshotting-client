using System.IO;
using Windows.Graphics.Imaging;
using Windows.Media.FaceAnalysis;
using Windows.Storage;
using CraftyCannon.Core;
using CraftyCannon.Ocr;

namespace CraftyCannon.App;

public sealed record FaceDetectionBox(uint X, uint Y, uint Width, uint Height, double Confidence = 1.0);

public interface IFaceDetectionBackend
{
    Task<IReadOnlyList<FaceDetectionBox>> DetectFacesAsync(string imagePath, CancellationToken cancellationToken = default);
}

public sealed class WindowsFaceDetectionBackend : IFaceDetectionBackend
{
    public async Task<IReadOnlyList<FaceDetectionBox>> DetectFacesAsync(string imagePath, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(imagePath));
        using var stream = await file.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(stream);
        using var bitmap = await decoder.GetSoftwareBitmapAsync();
        var supported = FaceDetector.GetSupportedBitmapPixelFormats();
        var faceBitmap = supported.Contains(bitmap.BitmapPixelFormat)
            ? bitmap
            : SoftwareBitmap.Convert(bitmap, supported.FirstOrDefault() == default ? BitmapPixelFormat.Gray8 : supported.First());
        var disposeConverted = !ReferenceEquals(faceBitmap, bitmap);
        try
        {
            var detector = await FaceDetector.CreateAsync();
            var faces = await detector.DetectFacesAsync(faceBitmap);
            return faces
                .Where(face => face.FaceBox.Width > 0 && face.FaceBox.Height > 0)
                .Select(face => new FaceDetectionBox(face.FaceBox.X, face.FaceBox.Y, face.FaceBox.Width, face.FaceBox.Height))
                .ToArray();
        }
        finally
        {
            if (disposeConverted)
            {
                faceBitmap.Dispose();
            }
        }
    }
}

public sealed class WindowsSmartRedactionDetector : ISmartRedactionDetector
{
    private readonly IFaceDetectionBackend faceBackend;
    private readonly Func<SmartRedactionDetectorPreferences> settingsProvider;

    public WindowsSmartRedactionDetector(IFaceDetectionBackend? faceBackend = null, Func<SmartRedactionDetectorPreferences>? settingsProvider = null)
    {
        this.faceBackend = faceBackend ?? new WindowsFaceDetectionBackend();
        this.settingsProvider = settingsProvider ?? (() => SmartRedactionDetectorPreferences.Default);
    }

    public async Task<IReadOnlyList<RedactionFinding>> DetectAsync(string imagePath, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var settings = (settingsProvider() ?? SmartRedactionDetectorPreferences.Default).Normalized;
        if (!settings.Barcode && !settings.Face)
        {
            return [];
        }

        var image = QrCodeService.LoadImage(imagePath);
        var findings = settings.Barcode
            ? QrCodeService.DecodeResults(image)
                .Where(result => result.Width > 0 && result.Height > 0 && 1.0 >= settings.MinimumConfidence)
                .Select(result => new RedactionFinding(
                    RedactionDetectorType.Barcode,
                    1.0,
                    result.X,
                    result.Y,
                    result.Width,
                    result.Height,
                    string.Empty))
                .ToList()
            : [];

        if (!settings.Face)
        {
            return findings;
        }

        foreach (var face in await faceBackend.DetectFacesAsync(imagePath, cancellationToken).ConfigureAwait(false))
        {
            if (face.Width == 0 || face.Height == 0 || image.Width <= 0 || image.Height <= 0 || face.Confidence < settings.MinimumConfidence)
            {
                continue;
            }

            findings.Add(new RedactionFinding(
                RedactionDetectorType.Face,
                face.Confidence,
                Math.Clamp(face.X / (double)image.Width, 0, 1),
                Math.Clamp(face.Y / (double)image.Height, 0, 1),
                Math.Clamp(face.Width / (double)image.Width, 0, 1),
                Math.Clamp(face.Height / (double)image.Height, 0, 1),
                string.Empty));
        }

        return findings;
    }
}