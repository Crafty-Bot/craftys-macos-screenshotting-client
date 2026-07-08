using CraftyCannon.Core;

namespace CraftyCannon.Capture;

public readonly record struct ScreenRect(int X, int Y, int Width, int Height);

public sealed record CaptureRequest(
    CaptureMode Mode,
    ScreenRect? FixedRegion,
    TimeSpan Delay,
    bool IncludeCursor,
    TimeSpan? RecordingDuration,
    string? RecordingOutputDirectory = null,
    bool ShowOverlayInfo = true,
    IReadOnlyList<CaptureSnapSize>? SnapSizes = null);

public sealed record CaptureResult(
    string FilePath,
    CaptureMode Mode,
    DateTimeOffset CapturedAt,
    ScreenRect? SourceRegion);

public interface IScreenCaptureService
{
    Task<CaptureResult> CaptureAsync(CaptureRequest request, CancellationToken cancellationToken);
}