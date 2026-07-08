using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CraftyCannon.Ocr;
using ZXing;
using ZXing.Common;
using ZXing.QrCode;
using ZXing.QrCode.Internal;
using ZXing.Rendering;

namespace CraftyCannon.App;

public sealed record QrCodeDecodeResult(string Text, double X, double Y, double Width, double Height);

public static class QrCodeService
{
    private const int PreviewPixels = 220;
    private const int QuietZoneModules = 4;

    public static BitmapSource? Generate(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        var writer = new BarcodeWriterPixelData
        {
            Format = BarcodeFormat.QR_CODE,
            Options = new QrCodeEncodingOptions
            {
                CharacterSet = "UTF-8",
                ErrorCorrection = ErrorCorrectionLevel.M,
                Height = PreviewPixels,
                Width = PreviewPixels,
                Margin = QuietZoneModules
            }
        };

        var pixelData = writer.Write(trimmed);
        var bitmap = BitmapSource.Create(
            pixelData.Width,
            pixelData.Height,
            96,
            96,
            PixelFormats.Bgra32,
            null,
            pixelData.Pixels,
            pixelData.Width * 4);
        bitmap.Freeze();
        return bitmap;
    }

    public static string Decode(BitmapSource source)
    {
        var messages = DecodeResults(source)
            .Select(result => result.Text)
            .Where(text => !string.IsNullOrEmpty(text))
            .ToArray();
        return string.Join(Environment.NewLine, messages);
    }

    public static IReadOnlyList<QrCodeDecodeResult> DecodeResults(BitmapSource source)
    {
        var normalized = NormalizeToBgra32(source);
        var width = normalized.PixelWidth;
        var height = normalized.PixelHeight;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        normalized.CopyPixels(pixels, stride, 0);

        var reader = new BarcodeReaderGeneric
        {
            AutoRotate = true,
            Options = new DecodingOptions
            {
                TryHarder = true,
                PossibleFormats = new[] { BarcodeFormat.QR_CODE }
            }
        };

        var results = reader.DecodeMultiple(pixels, width, height, RGBLuminanceSource.BitmapFormat.BGRA32)
            ?? Array.Empty<Result>();
        return results
            .Where(result => !string.IsNullOrEmpty(result.Text))
            .Select(result => ToDecodeResult(result, width, height))
            .ToArray();
    }

    public static BitmapSource LoadImage(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames.First();
        var bitmap = NormalizeToBgra32(frame);
        bitmap.Freeze();
        return bitmap;
    }

    public static byte[] EncodePng(BitmapSource source)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static QrCodeDecodeResult ToDecodeResult(Result result, int imageWidth, int imageHeight)
    {
        var points = (result.ResultPoints ?? Array.Empty<ResultPoint>())
            .Select(point => new BarcodePoint(point.X, point.Y))
            .ToArray();
        var finding = BarcodeRedactionGeometry.FindingFromPoints(result.Text, imageWidth, imageHeight, points);
        return new QrCodeDecodeResult(result.Text, finding.X, finding.Y, finding.Width, finding.Height);
    }
    private static BitmapSource NormalizeToBgra32(BitmapSource source)
    {
        if (source.Format == PixelFormats.Bgra32)
        {
            if (source.CanFreeze && !source.IsFrozen)
            {
                source.Freeze();
            }

            return source;
        }

        var converted = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        converted.Freeze();
        return converted;
    }
}