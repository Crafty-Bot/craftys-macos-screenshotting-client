using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CraftyCannon.Core;
using CraftyCannon.Upload;

namespace CraftyCannon.App;

public sealed class WindowsImageUploadPreprocessor(AppStoragePaths paths) : IImageUploadPreprocessor
{
    public async Task<ImageUploadPreprocessingResult> PrepareImageAsync(
        string imagePath,
        bool stripMetadata,
        ImageUploadFormat targetFormat,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var sourceFormat = FormatForPath(imagePath);
            var transcode = sourceFormat != targetFormat;
            if (!stripMetadata && !transcode)
            {
                return ImageUploadPreprocessingResult.Original();
            }

            if (stripMetadata && !transcode && sourceFormat == ImageUploadFormat.Gif)
            {
                return ImageUploadPreprocessingResult.Original();
            }

            var frame = LoadFrame(imagePath);
            var outputFrame = targetFormat == ImageUploadFormat.Jpeg ? FlattenOnWhite(frame) : frame;
            var directory = Path.Combine(paths.TempRoot, "ImagePreprocessing");
            Directory.CreateDirectory(directory);
            var fileName = $"{SafeBaseName(imagePath)}-{Guid.NewGuid():N}.{ExtensionFor(targetFormat)}";
            var outputPath = Path.Combine(directory, fileName);

            await using var stream = File.Create(outputPath);
            var encoder = EncoderFor(targetFormat);
            encoder.Frames.Add(BitmapFrame.Create(outputFrame));
            encoder.Save(stream);
            return ImageUploadPreprocessingResult.Preprocessed(outputPath, MimeTypeFor(targetFormat));
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return ImageUploadPreprocessingResult.Failed("Image metadata stripping or format conversion failed: " + ex.Message);
        }
    }

    private static BitmapSource LoadFrame(string imagePath)
    {
        var decoder = BitmapDecoder.Create(
            new Uri(Path.GetFullPath(imagePath), UriKind.Absolute),
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad);
        if (decoder.Frames.Count == 0)
        {
            throw new InvalidOperationException("Image contains no frames.");
        }

        return decoder.Frames[0];
    }

    private static BitmapSource FlattenOnWhite(BitmapSource source)
    {
        var width = source.PixelWidth;
        var height = source.PixelHeight;
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.DrawRectangle(System.Windows.Media.Brushes.White, null, new Rect(0, 0, width, height));
            context.DrawImage(source, new Rect(0, 0, width, height));
        }

        var flattened = new RenderTargetBitmap(width, height, source.DpiX, source.DpiY, PixelFormats.Pbgra32);
        flattened.Render(visual);
        return flattened;
    }

    private static BitmapEncoder EncoderFor(ImageUploadFormat format) => format switch
    {
        ImageUploadFormat.Jpeg => new JpegBitmapEncoder { QualityLevel = 92 },
        ImageUploadFormat.Gif => new GifBitmapEncoder(),
        ImageUploadFormat.Tiff => new TiffBitmapEncoder(),
        _ => new PngBitmapEncoder()
    };

    private static ImageUploadFormat FormatForPath(string imagePath)
    {
        var ext = Path.GetExtension(imagePath).TrimStart('.').ToLowerInvariant();
        return ext switch
        {
            "jpg" or "jpeg" => ImageUploadFormat.Jpeg,
            "gif" => ImageUploadFormat.Gif,
            "tif" or "tiff" => ImageUploadFormat.Tiff,
            _ => ImageUploadFormat.Png
        };
    }

    private static string ExtensionFor(ImageUploadFormat format) => format switch
    {
        ImageUploadFormat.Jpeg => "jpg",
        ImageUploadFormat.Gif => "gif",
        ImageUploadFormat.Tiff => "tiff",
        _ => "png"
    };

    private static string MimeTypeFor(ImageUploadFormat format) => format switch
    {
        ImageUploadFormat.Jpeg => "image/jpeg",
        ImageUploadFormat.Gif => "image/gif",
        ImageUploadFormat.Tiff => "image/tiff",
        _ => "image/png"
    };

    private static string SafeBaseName(string imagePath)
    {
        var name = Path.GetFileNameWithoutExtension(imagePath).Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            return "image";
        }

        foreach (var invalid in Path.GetInvalidFileNameChars())
        {
            name = name.Replace(invalid, '-');
        }

        return string.IsNullOrWhiteSpace(name) ? "image" : name;
    }
}