using CraftyCannon.Core;

namespace CraftyCannon.Upload;

public enum ImageUploadPreprocessingResultKind
{
    Original,
    Preprocessed,
    Failed
}

public sealed record ImageUploadPreprocessingResult(
    ImageUploadPreprocessingResultKind Kind,
    string? FilePath = null,
    string? MimeType = null,
    string? Message = null)
{
    public static ImageUploadPreprocessingResult Original() => new(ImageUploadPreprocessingResultKind.Original);

    public static ImageUploadPreprocessingResult Preprocessed(string filePath, string mimeType) =>
        new(ImageUploadPreprocessingResultKind.Preprocessed, filePath, mimeType);

    public static ImageUploadPreprocessingResult Failed(string message) => new(ImageUploadPreprocessingResultKind.Failed, Message: message);
}

public interface IImageUploadPreprocessor
{
    Task<ImageUploadPreprocessingResult> PrepareImageAsync(
        string imagePath,
        bool stripMetadata,
        ImageUploadFormat targetFormat,
        CancellationToken cancellationToken = default);
}