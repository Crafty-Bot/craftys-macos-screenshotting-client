using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CraftyCannon.Core;

namespace CraftyCannon.Capture;

public sealed class WindowsScreenCaptureService : IScreenCaptureService
{
    public async Task<CaptureResult> CaptureAsync(CaptureRequest request, CancellationToken cancellationToken)
    {
        if (request.Delay > TimeSpan.Zero)
        {
            await Task.Delay(request.Delay, cancellationToken);
        }

        if (request.Mode == CaptureMode.ScreenRecording)
        {
            return await CaptureScreenRecordingAsync(request, cancellationToken).ConfigureAwait(false);
        }

        return request.Mode switch
        {
            CaptureMode.FullScreen => CaptureFullScreen(request),
            CaptureMode.FixedRegion when request.FixedRegion is { } region => CaptureRegion(request, region),
            CaptureMode.Region => CaptureInteractiveRegion(request),
            CaptureMode.FrozenRegion => CaptureFrozenInteractiveRegion(request),
            CaptureMode.Window => CaptureInteractiveWindow(request),
            CaptureMode.TopTaskbar => CaptureTopTaskbar(request),
            _ => throw new NotImplementedException($"{request.Mode} capture is reserved for a later capture implementation.")
        };
    }

    private static async Task<CaptureResult> CaptureScreenRecordingAsync(CaptureRequest request, CancellationToken cancellationToken)
    {
        var bounds = SystemInformation.VirtualScreen;
        var region = request.FixedRegion ?? new ScreenRect(bounds.X, bounds.Y, bounds.Width, bounds.Height);
        var durationSeconds = Math.Clamp((request.RecordingDuration ?? TimeSpan.FromSeconds(30)).TotalSeconds, 1, 30);
        var duration = TimeSpan.FromSeconds(durationSeconds);
        var outputDirectory = string.IsNullOrWhiteSpace(request.RecordingOutputDirectory)
            ? TempCaptureDirectory
            : request.RecordingOutputDirectory;
        Directory.CreateDirectory(outputDirectory);
        var filePath = Path.Combine(outputDirectory, $"recording-{DateTimeOffset.Now:yyyy-MM-dd_HH-mm-ss}-{Guid.NewGuid().ToString("N")[..6].ToLowerInvariant()}.avi");

        const int framesPerSecond = 5;
        using var writer = new MjpegAviWriter(filePath, region.Width, region.Height, framesPerSecond);
        var interval = TimeSpan.FromMilliseconds(1000d / framesPerSecond);
        var stopAt = DateTimeOffset.UtcNow + duration;
        var nextFrameAt = DateTimeOffset.UtcNow;

        while (DateTimeOffset.UtcNow < stopAt)
        {
            cancellationToken.ThrowIfCancellationRequested();
            using var frame = CaptureBitmap(region, request.IncludeCursor);
            writer.AddFrame(frame);
            nextFrameAt += interval;
            var wait = nextFrameAt - DateTimeOffset.UtcNow;
            if (wait > TimeSpan.Zero)
            {
                await Task.Delay(wait, cancellationToken).ConfigureAwait(false);
            }
        }

        if (writer.FrameCount == 0)
        {
            throw new InvalidOperationException("Recording did not produce any frames.");
        }

        writer.Finish();
        return new CaptureResult(filePath, request.Mode, DateTimeOffset.UtcNow, region);
    }
    private static CaptureResult CaptureFullScreen(CaptureRequest request)
    {
        var bounds = SystemInformation.VirtualScreen;
        var region = new ScreenRect(bounds.X, bounds.Y, bounds.Width, bounds.Height);
        return CaptureRegion(request, region);
    }

    private static CaptureResult CaptureInteractiveWindow(CaptureRequest request)
    {
        var bounds = SystemInformation.VirtualScreen;
        using var background = CaptureBitmap(new ScreenRect(bounds.X, bounds.Y, bounds.Width, bounds.Height), request.IncludeCursor);
        var region = WindowSelectionOverlay.Select(bounds, background)
            ?? throw new OperationCanceledException("Window capture cancelled.");
        return CaptureRegion(request, region);
    }

    private static CaptureResult CaptureTopTaskbar(CaptureRequest request)
    {
        var screen = Screen.PrimaryScreen ?? Screen.AllScreens.FirstOrDefault()
            ?? throw new InvalidOperationException("No screen is available to capture.");
        if (TryGetTopTaskbarBounds(out var taskbarBounds))
        {
            var dropdownDepth = Math.Min(600, Math.Max(0, screen.Bounds.Bottom - taskbarBounds.Bottom));
            return CaptureRegion(request, new ScreenRect(
                taskbarBounds.X,
                taskbarBounds.Y,
                taskbarBounds.Width,
                taskbarBounds.Height + dropdownDepth));
        }

        var bounds = screen.Bounds;
        var height = Math.Min(48, Math.Max(1, bounds.Height));
        return CaptureRegion(request, new ScreenRect(bounds.X, bounds.Y, bounds.Width, height));
    }

    private static CaptureResult CaptureInteractiveRegion(CaptureRequest request)
    {
        var bounds = SystemInformation.VirtualScreen;
        var region = RegionSelectionOverlay.Select(bounds, showOverlayInfo: request.ShowOverlayInfo, snapSizes: request.SnapSizes)
            ?? throw new OperationCanceledException("Region capture cancelled.");
        return CaptureRegion(request, region);
    }

    private static CaptureResult CaptureFrozenInteractiveRegion(CaptureRequest request)
    {
        var bounds = SystemInformation.VirtualScreen;
        using var frozen = CaptureBitmap(new ScreenRect(bounds.X, bounds.Y, bounds.Width, bounds.Height), request.IncludeCursor);
        var region = RegionSelectionOverlay.Select(bounds, frozen, request.ShowOverlayInfo, request.SnapSizes)
            ?? throw new OperationCanceledException("Frozen region capture cancelled.");
        var relative = new Rectangle(region.X - bounds.X, region.Y - bounds.Y, region.Width, region.Height);
        using var cropped = frozen.Clone(relative, PixelFormat.Format32bppArgb);
        var filePath = NewCapturePath();
        cropped.Save(filePath, ImageFormat.Png);
        return new CaptureResult(filePath, request.Mode, DateTimeOffset.UtcNow, region);
    }

    private static CaptureResult CaptureRegion(CaptureRequest request, ScreenRect region)
    {
        using var bitmap = CaptureBitmap(region, request.IncludeCursor);
        var filePath = NewCapturePath();
        bitmap.Save(filePath, ImageFormat.Png);
        return new CaptureResult(filePath, request.Mode, DateTimeOffset.UtcNow, region);
    }

    private static bool TryGetTopTaskbarBounds(out Rectangle bounds)
    {
        var data = new AppBarData { cbSize = Marshal.SizeOf<AppBarData>() };
        var result = SHAppBarMessage(AbmGetTaskbarPos, ref data);
        bounds = Rectangle.Empty;
        if (result == nint.Zero || data.uEdge != AbeTop)
        {
            return false;
        }

        bounds = Rectangle.FromLTRB(data.rc.Left, data.rc.Top, data.rc.Right, data.rc.Bottom);
        return bounds.Width > 0 && bounds.Height > 0;
    }

    private static Bitmap CaptureBitmap(ScreenRect region, bool includeCursor = false)
    {
        if (region.Width <= 0 || region.Height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(region), "Capture regions must have positive dimensions.");
        }

        var bitmap = new Bitmap(region.Width, region.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(region.X, region.Y, 0, 0, new Size(region.Width, region.Height), CopyPixelOperation.SourceCopy);
        if (includeCursor)
        {
            DrawCursor(graphics, region);
        }

        return bitmap;
    }

    private static void DrawCursor(Graphics graphics, ScreenRect region)
    {
        var cursorInfo = new CursorInfo { cbSize = Marshal.SizeOf<CursorInfo>() };
        if (!GetCursorInfo(out cursorInfo) || (cursorInfo.flags & CursorShowing) == 0 || cursorInfo.hCursor == nint.Zero)
        {
            return;
        }

        var x = cursorInfo.ptScreenPos.X - region.X;
        var y = cursorInfo.ptScreenPos.Y - region.Y;
        if (x < -64 || y < -64 || x > region.Width + 64 || y > region.Height + 64)
        {
            return;
        }

        var hdc = graphics.GetHdc();
        try
        {
            DrawIcon(hdc, x, y, cursorInfo.hCursor);
        }
        finally
        {
            graphics.ReleaseHdc(hdc);
        }
    }

    private static string NewCapturePath()
    {
        Directory.CreateDirectory(TempCaptureDirectory);
        return Path.Combine(TempCaptureDirectory, $"capture-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}.png");
    }

    private const int CursorShowing = 0x00000001;

    [DllImport("user32.dll")]
    private static extern bool GetCursorInfo(out CursorInfo pci);

    [DllImport("user32.dll")]
    private static extern bool DrawIcon(nint hDC, int x, int y, nint hIcon);

    [StructLayout(LayoutKind.Sequential)]
    private struct CursorInfo
    {
        public int cbSize;
        public int flags;
        public nint hCursor;
        public NativePoint ptScreenPos;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativePoint
    {
        public readonly int X;
        public readonly int Y;
    }

    private const uint AbmGetTaskbarPos = 0x00000005;
    private const uint AbeTop = 1;

    [DllImport("shell32.dll")]
    private static extern nint SHAppBarMessage(uint dwMessage, ref AppBarData pData);

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        public int cbSize;
        public nint hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public NativeRect rc;
        public nint lParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativeRect
    {
        public readonly int Left;
        public readonly int Top;
        public readonly int Right;
        public readonly int Bottom;
    }

    private static string TempCaptureDirectory =>
        Path.Combine(Path.GetTempPath(), "CraftyCannon", "Captures");
}



