using CraftyCannon.Ocr;

namespace CraftyCannon.App;

public sealed class WindowsBarcodeSmartRedactionDetector : ISmartRedactionDetector
{
    public Task<IReadOnlyList<RedactionFinding>> DetectAsync(string imagePath, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var image = QrCodeService.LoadImage(imagePath);
        var findings = QrCodeService.DecodeResults(image)
            .Where(result => result.Width > 0 && result.Height > 0)
            .Select(result => new RedactionFinding(
                RedactionDetectorType.Barcode,
                1.0,
                result.X,
                result.Y,
                result.Width,
                result.Height,
                string.Empty))
            .ToArray();
        return Task.FromResult<IReadOnlyList<RedactionFinding>>(findings);
    }
}