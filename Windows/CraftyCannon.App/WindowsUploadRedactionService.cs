using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CraftyCannon.Core;
using CraftyCannon.Ocr;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public sealed class WindowsUploadRedactionService : IUploadRedactionService
{
    private const double DefaultFilterStrength = 14;
    private readonly AppStoragePaths paths;
    private readonly ISmartRedactionDetector detector;

    public WindowsUploadRedactionService(AppStoragePaths paths, ISmartRedactionDetector detector)
    {
        this.paths = paths;
        this.detector = detector;
    }

    public async Task<UploadRedactionResult> PrepareImageAsync(
        string imagePath,
        UploadRedactionPolicy policy,
        SmartRedactionRenderMode renderMode,
        CancellationToken cancellationToken = default)
    {
        IReadOnlyList<RedactionFinding> findings;
        try
        {
            findings = await detector.DetectAsync(imagePath, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return UploadRedactionResult.Failed("Redaction check failed; upload was not sent: " + ex.Message);
        }

        if (findings.Count == 0)
        {
            return UploadRedactionResult.Original();
        }

        if (policy == UploadRedactionPolicy.AskBeforeUpload)
        {
            var decision = PromptForDecision(findings);
            if (decision == RedactionUploadDecision.Cancel)
            {
                return UploadRedactionResult.Cancelled("Upload cancelled.");
            }

            if (decision == RedactionUploadDecision.UploadOriginal)
            {
                return UploadRedactionResult.Original();
            }
        }

        try
        {
            var output = RedactToManagedPng(imagePath, findings, renderMode);
            return UploadRedactionResult.Redacted(output, isManagedLocalCopy: true, $"Redacted {findings.Count} sensitive region(s) before upload.");
        }
        catch (Exception ex)
        {
            return UploadRedactionResult.Failed("Redaction rendering failed; upload was not sent: " + ex.Message);
        }
    }

    private RedactionUploadDecision PromptForDecision(IReadOnlyList<RedactionFinding> findings)
    {
        var summary = RedactionPromptSummary(findings);
        return System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            var result = System.Windows.MessageBox.Show(
                summary,
                "Sensitive content detected",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);
            return result switch
            {
                MessageBoxResult.Yes => RedactionUploadDecision.Redact,
                MessageBoxResult.No => RedactionUploadDecision.UploadOriginal,
                _ => RedactionUploadDecision.Cancel
            };
        });
    }

    private static string RedactionPromptSummary(IReadOnlyList<RedactionFinding> findings)
    {
        var grouped = findings
            .GroupBy(finding => finding.Type)
            .Select(group => $"{DisplayName(group.Key)}: {group.Count()}")
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        var countLabel = findings.Count == 1 ? "1 region" : $"{findings.Count} regions";
        return $"CraftyCannon found {countLabel} that may need redaction before upload.\n\n{string.Join(Environment.NewLine, grouped)}\n\nYes: Redact & Upload\nNo: Upload Original\nCancel: Cancel Upload";
    }

    private static string DisplayName(RedactionDetectorType type) => type switch
    {
        RedactionDetectorType.Barcode => "Barcodes",
        RedactionDetectorType.Face => "Faces",
        RedactionDetectorType.TextOcr => "Text OCR",
        _ => type.ToString()
    };

    private string RedactToManagedPng(string imagePath, IReadOnlyList<RedactionFinding> findings, SmartRedactionRenderMode mode)
    {
        var image = LoadBitmap(imagePath);
        var redacted = ApplyFindings(image, findings, mode) ?? throw new InvalidOperationException("No redaction regions could be applied.");
        Directory.CreateDirectory(paths.ImagesDirectory);
        var output = Path.Combine(paths.ImagesDirectory, $"redacted-{Guid.NewGuid():N}.png");
        SavePng(redacted, output);
        return output;
    }

    private static BitmapSource LoadBitmap(string imagePath)
    {
        using var stream = File.OpenRead(imagePath);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames.First();
        var converted = ConvertToPbgra(frame);
        converted.Freeze();
        return converted;
    }

    private static void SavePng(BitmapSource image, string output)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = File.Create(output);
        encoder.Save(stream);
    }

    private static BitmapSource? ApplyFindings(BitmapSource image, IReadOnlyList<RedactionFinding> findings, SmartRedactionRenderMode mode)
    {
        if (findings.Count == 0)
        {
            return null;
        }

        var source = ConvertToPbgra(image);
        var width = source.PixelWidth;
        var height = source.PixelHeight;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        source.CopyPixels(pixels, stride, 0);

        var applied = RedactionImageRenderer.ApplyToBgra32(
            pixels,
            width,
            height,
            findings,
            mode,
            Math.Max(2, (int)Math.Round(DefaultFilterStrength)));

        if (applied == 0)
        {
            return null;
        }

        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private static BitmapSource ConvertToPbgra(BitmapSource image)
    {
        if (image.Format == PixelFormats.Pbgra32)
        {
            return image;
        }

        var converted = new FormatConvertedBitmap(image, PixelFormats.Pbgra32, null, 0);
        converted.Freeze();
        return converted;
    }

    private enum RedactionUploadDecision
    {
        Redact,
        UploadOriginal,
        Cancel
    }
}


