using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using CraftyCannon.Capture;
using CraftyCannon.Core;
using CraftyCannon.Editor;
using CraftyCannon.Ocr;
using WpfColor = System.Windows.Media.Color;
using WpfMouseEventArgs = System.Windows.Input.MouseEventArgs;
using WpfPoint = System.Windows.Point;

namespace CraftyCannon.App;

public partial class EditorWindow : Window
{
    private static readonly WpfColor DefaultInkColor = Colors.Red;
    private static readonly WpfColor HighlightColor = Colors.Yellow;
    private const double PenWidth = 6.0;
    private const double HighlighterAlpha = 0.35;
    private const double HighlighterWidth = 10.0;
    private const double EraserWidth = 18.0;
    private const double DefaultMagnifierZoom = 1.4;
    private const double DefaultFontSize = 28.0;
    private const double StepDiameter = 44.0;
    private const double DefaultFilterStrength = 14.0;
    private const int MaxUndoDepth = 50;

    private readonly UploadRecord record;
    private readonly string tempRoot;
    private readonly Func<string, Task<bool>> saveAndUploadAsync;
    private readonly IScreenCaptureService? screenCapture;
    private readonly ISmartRedactionDetector? smartRedactionDetector;
    private readonly Func<SmartRedactionRenderMode> redactionRenderModeProvider;
    private readonly Action<string, string>? notify;
    private readonly List<EditorInkStroke> strokes = [];
    private readonly List<EditorOverlay> overlays = [];
    private readonly List<EditorSnapshot> undoStack = [];
    private readonly List<EditorSnapshot> redoStack = [];
    private readonly List<WpfPoint> activeStrokePoints = [];
    private readonly List<Line> activeArrowLines = [];
    private WpfPoint? activeOverlayStart;
    private WpfPoint? activeOverlayCurrent;
    private WpfPoint? lastPointerMovePoint;
    private int? selectedOverlayIndex;
    private BitmapSource? baseImage;
    private Polyline? activePolyline;
    private bool isDrawing;
    private bool isDrawingOverlay;
    private bool isSmartErasing;
    private bool isMovingOverlay;
    private bool didRequestSmartEraserUndo;
    private bool didRequestMoveUndo;
    private bool smartRedactionInProgress;
    private int nextStepNumber = 1;
    private string stickerText = string.Empty;
    private double strokeWidth = PenWidth;
    private double fontSize = DefaultFontSize;
    private double filterStrength = DefaultFilterStrength;
    private WpfColor selectedInkColor = DefaultInkColor;

    public EditorWindow(UploadRecord record, string tempRoot, Func<string, Task<bool>> saveAndUploadAsync, IScreenCaptureService? screenCapture = null, ISmartRedactionDetector? smartRedactionDetector = null, Func<SmartRedactionRenderMode>? redactionRenderModeProvider = null, Action<string, string>? notify = null)
    {
        this.record = record;
        this.tempRoot = tempRoot;
        this.saveAndUploadAsync = saveAndUploadAsync;
        this.screenCapture = screenCapture;
        this.smartRedactionDetector = smartRedactionDetector;
        this.redactionRenderModeProvider = redactionRenderModeProvider ?? (() => SmartRedactionRenderMode.Pixelate);
        this.notify = notify;
        InitializeComponent();
        InitializeStyleControls();
        Title = "CraftyCannon Editor - " + record.FileName;
        ToolPicker.ItemsSource = EditorToolCatalog.ParityTools;
        ToolList.ItemsSource = EditorToolCatalog.ParityTools;
        ToolPicker.SelectedItem = EditorTool.Pen;
        ToolList.SelectedItem = EditorTool.Pen;
        LoadImage(record.LocalFilePath!);
        UpdateZoomText();
        RefreshEditorState();
    }

    private void InitializeStyleControls()
    {
        strokeWidth = PenWidth;
        fontSize = DefaultFontSize;
        filterStrength = DefaultFilterStrength;
        selectedInkColor = DefaultInkColor;
        if (StrokeWidthSlider is not null)
        {
            StrokeWidthSlider.Value = strokeWidth;
        }

        if (FontSizeSlider is not null)
        {
            FontSizeSlider.Value = fontSize;
        }

        if (FilterStrengthSlider is not null)
        {
            FilterStrengthSlider.Value = filterStrength;
        }

        UpdateStyleText();
    }

    private void UpdateStyleText()
    {
        if (StrokeWidthText is not null)
        {
            StrokeWidthText.Text = $"Stroke width: {Math.Round(strokeWidth)}";
        }

        if (FontSizeText is not null)
        {
            FontSizeText.Text = $"Font size: {Math.Round(fontSize)}";
        }

        if (FilterStrengthText is not null)
        {
            FilterStrengthText.Text = $"Filter strength: {Math.Round(filterStrength)}";
        }
    }
    private EditorTool SelectedTool => ToolPicker.SelectedItem is EditorTool tool ? tool : EditorTool.Pen;

    private void LoadImage(string path)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(System.IO.Path.GetFullPath(path), UriKind.Absolute);
        image.EndInit();
        image.Freeze();
        SetBaseImage(image);
    }


    private void SetBaseImage(BitmapSource image)
    {
        if (image.CanFreeze && !image.IsFrozen)
        {
            image.Freeze();
        }

        baseImage = image;
        ImagePreview.Source = image;
        EditorSurface.Width = image.PixelWidth;
        EditorSurface.Height = image.PixelHeight;
        InkLayerImage.Width = image.PixelWidth;
        InkLayerImage.Height = image.PixelHeight;
        OverlayCanvas.Width = image.PixelWidth;
        OverlayCanvas.Height = image.PixelHeight;
        InkCanvas.Width = image.PixelWidth;
        InkCanvas.Height = image.PixelHeight;
        RedrawInkLayer();
        RedrawOverlayCanvas();
    }

    private void Resize_Click(object sender, RoutedEventArgs e)
    {
        if (baseImage is null)
        {
            return;
        }

        var dialog = new ResizePromptWindow(baseImage.PixelWidth, baseImage.PixelHeight)
        {
            Owner = this
        };
        if (dialog.ShowDialog() == true)
        {
            ApplyResize(dialog.PixelWidth, dialog.PixelHeight);
        }
    }

    private void RotateLeft_Click(object sender, RoutedEventArgs e) => ApplyTransform(ImageTransform.RotateLeft);

    private void RotateRight_Click(object sender, RoutedEventArgs e) => ApplyTransform(ImageTransform.RotateRight);

    private void FlipHorizontal_Click(object sender, RoutedEventArgs e) => ApplyTransform(ImageTransform.FlipHorizontal);

    private void FlipVertical_Click(object sender, RoutedEventArgs e) => ApplyTransform(ImageTransform.FlipVertical);

    private async void DetectSensitive_Click(object sender, RoutedEventArgs e)
    {
        await DetectSensitiveAsync().ConfigureAwait(true);
    }

    private async void SaveAndUpload_Click(object sender, RoutedEventArgs e)
    {
        await SaveAndUploadAsync().ConfigureAwait(true);
    }

    private async Task SaveAndUploadAsync()
    {
        if (baseImage is null || !SaveUploadButton.IsEnabled)
        {
            return;
        }

        SaveUploadButton.IsEnabled = false;
        try
        {
            BitmapSource rendered;
            try
            {
                rendered = RenderCompositeImage();
            }
            catch
            {
                NotifyEditor("Failed to render");
                return;
            }

            string exportPath;
            try
            {
                Directory.CreateDirectory(tempRoot);
                exportPath = System.IO.Path.Combine(tempRoot, $"edited-{Guid.NewGuid():N}.png");
                await using var stream = File.Create(exportPath);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(rendered));
                encoder.Save(stream);
            }
            catch
            {
                NotifyEditor("Export failed");
                return;
            }

            if (await saveAndUploadAsync(exportPath).ConfigureAwait(true))
            {
                Close();
            }
        }
        finally
        {
            SaveUploadButton.IsEnabled = true;
        }
    }
    private async Task DetectSensitiveAsync()
    {
        if (baseImage is null || smartRedactionInProgress)
        {
            return;
        }

        if (smartRedactionDetector is null)
        {
            NotifyEditor("Sensitive content detection is not available yet.");
            return;
        }

        BitmapSource composite;
        try
        {
            composite = RenderCompositeImage();
        }
        catch
        {
            NotifyEditor("Failed to render image for redaction");
            return;
        }

        string? detectionPath = null;
        smartRedactionInProgress = true;
        RefreshEditorState();
        try
        {
            Directory.CreateDirectory(tempRoot);
            detectionPath = System.IO.Path.Combine(tempRoot, $"redaction-detect-{Guid.NewGuid():N}.png");
            try
            {
                SaveBitmap(composite, detectionPath);
            }
            catch
            {
                NotifyEditor("Failed to prepare image for redaction");
                return;
            }

            NotifyEditor("Detecting sensitive content...");
            var findings = await smartRedactionDetector.DetectAsync(detectionPath, CancellationToken.None).ConfigureAwait(true);
            if (findings.Count == 0)
            {
                NotifyEditor("No sensitive content detected");
                return;
            }

            var redacted = ApplySmartRedactionFindings(composite, findings, redactionRenderModeProvider(), filterStrength);
            if (redacted is null)
            {
                NotifyEditor("No redaction regions could be applied");
                return;
            }

            PushUndoSnapshot();
            SetBaseImage(redacted);
            strokes.Clear();
            overlays.Clear();
            selectedOverlayIndex = null;
            RedrawInkCanvas();
            RedrawOverlayCanvas();
            RefreshEditorState();
            NotifyEditor($"Redacted {findings.Count} sensitive region(s)");
        }
        catch
        {
            NotifyEditor("Sensitive text detection failed");
        }
        finally
        {
            smartRedactionInProgress = false;
            RefreshEditorState();
            if (detectionPath is not null)
            {
                try
                {
                    File.Delete(detectionPath);
                }
                catch
                {
                }
            }
        }
    }
    private void NotifyEditor(string message)
    {
        if (notify is not null)
        {
            notify("CraftyCannon", message);
            return;
        }

        System.Windows.MessageBox.Show(this, message, "CraftyCannon");
    }
    private void FitImageToViewport()
    {
        if (baseImage is null || EditorScrollViewer is null)
        {
            return;
        }

        var viewportWidth = EditorScrollViewer.ViewportWidth;
        var viewportHeight = EditorScrollViewer.ViewportHeight;
        if (double.IsNaN(viewportWidth) || double.IsNaN(viewportHeight) || viewportWidth <= 0 || viewportHeight <= 0)
        {
            return;
        }

        var horizontalScale = viewportWidth / baseImage.PixelWidth;
        var verticalScale = viewportHeight / baseImage.PixelHeight;
        var zoom = Math.Clamp(Math.Min(horizontalScale, verticalScale) * 100.0, ZoomSlider.Minimum, ZoomSlider.Maximum);
        if (zoom > 0)
        {
            ZoomSlider.Value = zoom;
        }
    }
    private BitmapSource RenderCompositeImage()
    {
        if (baseImage is null)
        {
            throw new InvalidOperationException("No editor image is loaded.");
        }

        var converted = new FormatConvertedBitmap();
        converted.BeginInit();
        converted.Source = baseImage;
        converted.DestinationFormat = PixelFormats.Pbgra32;
        converted.EndInit();
        converted.Freeze();

        var width = converted.PixelWidth;
        var height = converted.PixelHeight;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        converted.CopyPixels(pixels, stride, 0);

        foreach (var stroke in strokes)
        {
            if (stroke.Points.Count >= 2)
            {
                DrawStrokeToPixels(pixels, width, height, stroke);
            }
        }

        var inkedBase = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
        inkedBase.Freeze();
        if (overlays.Count == 0)
        {
            return inkedBase;
        }

        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.DrawImage(inkedBase, new Rect(0, 0, width, height));
            foreach (var overlay in overlays)
            {
                DrawOverlay(context, overlay, includeSelection: false);
            }
        }

        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    private static void SaveBitmap(BitmapSource image, string path)
    {
        using var stream = File.Create(path);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        encoder.Save(stream);
    }
    private BitmapSource? RenderInkLayerBitmap(IEnumerable<EditorInkStroke> sourceStrokes)
    {
        if (baseImage is null)
        {
            return null;
        }

        var width = baseImage.PixelWidth;
        var height = baseImage.PixelHeight;
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        var pixels = new byte[width * height * 4];
        var drewAny = false;
        foreach (var stroke in sourceStrokes)
        {
            if (stroke.Points.Count < 2)
            {
                continue;
            }

            DrawStrokeToPixels(pixels, width, height, stroke);
            drewAny = true;
        }

        if (!drewAny)
        {
            return null;
        }

        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, width * 4);
        bitmap.Freeze();
        return bitmap;
    }

    private static void DrawStrokeToPixels(byte[] pixels, int pixelWidth, int pixelHeight, EditorInkStroke stroke)
    {
        for (var i = 1; i < stroke.Points.Count; i++)
        {
            DrawLineToPixels(
                pixels,
                pixelWidth,
                pixelHeight,
                DenormalizePoint(stroke.Points[i - 1], pixelWidth, pixelHeight),
                DenormalizePoint(stroke.Points[i], pixelWidth, pixelHeight),
                stroke.Width,
                stroke.Color,
                stroke.Alpha,
                stroke.Mode == InkMode.Erase);
        }

        if (stroke.Mode == InkMode.Draw && stroke.ArrowHead && stroke.Points.Count >= 2)
        {
            DrawArrowHeadToPixels(
                pixels,
                pixelWidth,
                pixelHeight,
                DenormalizePoint(stroke.Points[^2], pixelWidth, pixelHeight),
                DenormalizePoint(stroke.Points[^1], pixelWidth, pixelHeight),
                stroke.Width,
                stroke.Color,
                stroke.Alpha);
        }
    }

    private static void DrawArrowHeadToPixels(byte[] pixels, int pixelWidth, int pixelHeight, WpfPoint previous, WpfPoint tip, double width, WpfColor color, double alpha)
    {
        var dx = tip.X - previous.X;
        var dy = tip.Y - previous.Y;
        var length = Math.Max(1, Math.Sqrt((dx * dx) + (dy * dy)));
        var ux = dx / length;
        var uy = dy / length;
        var headLength = Math.Max(10, width * 2.5);
        const double angle = Math.PI / 7.0;
        var left = Rotate(-ux, -uy, angle);
        var right = Rotate(-ux, -uy, -angle);
        DrawLineToPixels(pixels, pixelWidth, pixelHeight, tip, new WpfPoint(tip.X + (left.X * headLength), tip.Y + (left.Y * headLength)), width, color, alpha, erase: false);
        DrawLineToPixels(pixels, pixelWidth, pixelHeight, tip, new WpfPoint(tip.X + (right.X * headLength), tip.Y + (right.Y * headLength)), width, color, alpha, erase: false);
    }

    private static void DrawLineToPixels(byte[] pixels, int pixelWidth, int pixelHeight, WpfPoint start, WpfPoint end, double width, WpfColor color, double alpha, bool erase)
    {
        var radius = Math.Max(0.5, width / 2.0);
        var dx = end.X - start.X;
        var dy = end.Y - start.Y;
        var length = Math.Sqrt((dx * dx) + (dy * dy));
        var step = Math.Max(0.5, radius / 2.0);
        var steps = Math.Max(1, (int)Math.Ceiling(length / step));
        for (var i = 0; i <= steps; i++)
        {
            var t = (double)i / steps;
            DrawCircleToPixels(
                pixels,
                pixelWidth,
                pixelHeight,
                start.X + (dx * t),
                start.Y + (dy * t),
                radius,
                color,
                alpha,
                erase);
        }
    }

    private static void DrawCircleToPixels(byte[] pixels, int pixelWidth, int pixelHeight, double centerX, double centerY, double radius, WpfColor color, double alpha, bool erase)
    {
        var minX = Math.Max(0, (int)Math.Floor(centerX - radius));
        var maxX = Math.Min(pixelWidth - 1, (int)Math.Ceiling(centerX + radius));
        var minY = Math.Max(0, (int)Math.Floor(centerY - radius));
        var maxY = Math.Min(pixelHeight - 1, (int)Math.Ceiling(centerY + radius));
        var radiusSquared = radius * radius;

        for (var y = minY; y <= maxY; y++)
        {
            for (var x = minX; x <= maxX; x++)
            {
                var dx = x + 0.5 - centerX;
                var dy = y + 0.5 - centerY;
                if ((dx * dx) + (dy * dy) > radiusSquared)
                {
                    continue;
                }

                var offset = ((y * pixelWidth) + x) * 4;
                if (erase)
                {
                    pixels[offset] = 0;
                    pixels[offset + 1] = 0;
                    pixels[offset + 2] = 0;
                    pixels[offset + 3] = 0;
                    continue;
                }

                BlendSourceOver(pixels, offset, color, alpha);
            }
        }
    }

    private static void BlendSourceOver(byte[] pixels, int offset, WpfColor color, double alpha)
    {
        var sourceAlpha = (byte)Math.Clamp((int)Math.Round(255 * Math.Clamp(alpha, 0, 1)), 0, 255);
        if (sourceAlpha == 0)
        {
            return;
        }

        var inverse = 255 - sourceAlpha;
        var sourceBlue = (color.B * sourceAlpha) / 255;
        var sourceGreen = (color.G * sourceAlpha) / 255;
        var sourceRed = (color.R * sourceAlpha) / 255;

        pixels[offset] = (byte)Math.Min(255, sourceBlue + ((pixels[offset] * inverse) / 255));
        pixels[offset + 1] = (byte)Math.Min(255, sourceGreen + ((pixels[offset + 1] * inverse) / 255));
        pixels[offset + 2] = (byte)Math.Min(255, sourceRed + ((pixels[offset + 2] * inverse) / 255));
        pixels[offset + 3] = (byte)Math.Min(255, sourceAlpha + ((pixels[offset + 3] * inverse) / 255));
    }

    private static WpfPoint Rotate(double x, double y, double angle) =>
        new((x * Math.Cos(angle)) - (y * Math.Sin(angle)), (x * Math.Sin(angle)) + (y * Math.Cos(angle)));

    private void EditorSurface_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (baseImage is null || e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        var tool = SelectedTool;
        if (tool == EditorTool.Pointer)
        {
            if (TryNormalizePoint(e.GetPosition(EditorSurface), out var pointerPoint))
            {
                var hit = HitTestOverlays(DenormalizePoint(pointerPoint));
                selectedOverlayIndex = hit;
                if (hit is not null)
                {
                    isMovingOverlay = true;
                    didRequestMoveUndo = false;
                    lastPointerMovePoint = pointerPoint;
                    EditorSurface.CaptureMouse();
                }
            }
            else
            {
                selectedOverlayIndex = null;
            }

            RedrawOverlayCanvas();
            e.Handled = true;
            return;
        }

        if (TryNormalizePoint(e.GetPosition(EditorSurface), out var clickPoint))
        {
            if (tool == EditorTool.StepMarker)
            {
                AddStepOverlay(clickPoint);
                e.Handled = true;
                return;
            }

            if (tool == EditorTool.CursorStamp)
            {
                AddCursorOverlay(clickPoint);
                e.Handled = true;
                return;
            }

            if (tool == EditorTool.Sticker)
            {
                AddStickerOverlay(clickPoint);
                e.Handled = true;
                return;
            }

            if (tool is EditorTool.Text or EditorTool.TextOutline or EditorTool.TextBackground or EditorTool.SpeechBalloon)
            {
                AddTextOverlay(tool, clickPoint);
                e.Handled = true;
                return;
            }
        }
        if ((IsShapeOverlayTool(tool) || IsDestructiveRectTool(tool) || IsImageInsertTool(tool)) && TryNormalizePoint(e.GetPosition(EditorSurface), out var overlayPoint))
        {
            selectedOverlayIndex = null;
            activeOverlayStart = overlayPoint;
            activeOverlayCurrent = overlayPoint;
            isDrawingOverlay = true;
            EditorSurface.CaptureMouse();
            RedrawOverlayCanvas();
            e.Handled = true;
            return;
        }

        if (IsInkTool(tool))
        {
            if (!TryNormalizePoint(e.GetPosition(EditorSurface), out var point))
            {
                return;
            }

            activeStrokePoints.Clear();
            activeStrokePoints.Add(point);
            activePolyline = tool == EditorTool.Eraser ? null : NewDisplayPolyline(StyleForTool(tool));
            if (activePolyline is not null)
            {
                activePolyline.Points.Add(DenormalizePoint(point));
                InkCanvas.Children.Add(activePolyline);
            }
            else
            {
                RefreshActiveInkPreview();
            }

            isDrawing = true;
            EditorSurface.CaptureMouse();
            e.Handled = true;
            return;
        }

        if (tool == EditorTool.SmartEraser && TryNormalizePoint(e.GetPosition(EditorSurface), out var smartPoint))
        {
            isSmartErasing = true;
            didRequestSmartEraserUndo = false;
        didRequestMoveUndo = false;
            SmartEraseAt(smartPoint);
            EditorSurface.CaptureMouse();
            e.Handled = true;
        }
    }

    private void EditorSurface_MouseMove(object sender, WpfMouseEventArgs e)
    {
        if (isMovingOverlay && e.LeftButton == MouseButtonState.Pressed)
        {
            if (TryNormalizePoint(e.GetPosition(EditorSurface), out var point))
            {
                MoveSelectedOverlay(point);
            }

            e.Handled = true;
            return;
        }
        if (isSmartErasing && e.LeftButton == MouseButtonState.Pressed)
        {
            if (TryNormalizePoint(e.GetPosition(EditorSurface), out var point))
            {
                SmartEraseAt(point);
            }

            e.Handled = true;
            return;
        }

        if (isDrawingOverlay && e.LeftButton == MouseButtonState.Pressed)
        {
            activeOverlayCurrent = NormalizePointClamped(e.GetPosition(EditorSurface));
            RedrawOverlayCanvas();
            e.Handled = true;
            return;
        }

        if (!isDrawing || e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        if (!TryNormalizePoint(e.GetPosition(EditorSurface), out var inkPoint))
        {
            return;
        }

        if (activeStrokePoints.Count == 0 || Distance(DenormalizePoint(activeStrokePoints[^1]), DenormalizePoint(inkPoint)) >= 1.0)
        {
            activeStrokePoints.Add(inkPoint);
            if (activePolyline is not null)
            {
                activePolyline.Points.Add(DenormalizePoint(inkPoint));
                RefreshActiveArrowHead();
            }
            else
            {
                RefreshActiveInkPreview();
            }
        }
    }

    private void EditorSurface_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (isMovingOverlay && e.ChangedButton == MouseButton.Left)
        {
            if (TryNormalizePoint(e.GetPosition(EditorSurface), out var point))
            {
                MoveSelectedOverlay(point);
            }

            isMovingOverlay = false;
            didRequestMoveUndo = false;
            lastPointerMovePoint = null;
            EditorSurface.ReleaseMouseCapture();
            RefreshEditorState();
            e.Handled = true;
            return;
        }
        if (isSmartErasing && e.ChangedButton == MouseButton.Left)
        {
            if (TryNormalizePoint(e.GetPosition(EditorSurface), out var point))
            {
                SmartEraseAt(point);
            }

            isSmartErasing = false;
            didRequestSmartEraserUndo = false;
            EditorSurface.ReleaseMouseCapture();
            RefreshEditorState();
            e.Handled = true;
            return;
        }

        if (isDrawingOverlay && e.ChangedButton == MouseButton.Left)
        {
            activeOverlayCurrent = NormalizePointClamped(e.GetPosition(EditorSurface));
            FinishActiveOverlay();
            e.Handled = true;
            return;
        }

        if (!isDrawing || e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        FinishActiveStroke();
        e.Handled = true;
    }

    private void EditorSurface_MouseLeave(object sender, WpfMouseEventArgs e)
    {
        if (isMovingOverlay && e.LeftButton != MouseButtonState.Pressed)
        {
            isMovingOverlay = false;
            didRequestMoveUndo = false;
            lastPointerMovePoint = null;
            EditorSurface.ReleaseMouseCapture();
            RefreshEditorState();
        }
        if (isDrawing && e.LeftButton != MouseButtonState.Pressed)
        {
            FinishActiveStroke();
        }

        if (isDrawingOverlay && e.LeftButton != MouseButtonState.Pressed)
        {
            CancelActiveInteraction();
        }

        if (isSmartErasing && e.LeftButton != MouseButtonState.Pressed)
        {
            isSmartErasing = false;
            didRequestSmartEraserUndo = false;
            EditorSurface.ReleaseMouseCapture();
            RefreshEditorState();
        }
    }

    private void FinishActiveStroke()
    {
        if (activeStrokePoints.Count >= 2)
        {
            var style = StyleForTool(SelectedTool);
            PushUndoSnapshot();
            strokes.Add(new EditorInkStroke([.. activeStrokePoints], style.Color, style.Width, style.Alpha, style.Mode, style.ArrowHead));
        }

        activeStrokePoints.Clear();
        RemoveActiveArrowHead();
        activePolyline = null;
        isDrawing = false;
        EditorSurface.ReleaseMouseCapture();
        RedrawInkCanvas();
        RefreshEditorState();
    }

    private void FinishActiveOverlay()
    {
        if (activeOverlayStart is { } start && activeOverlayCurrent is { } current)
        {
            if (IsDestructiveRectTool(SelectedTool))
            {
                ApplyDestructiveTool(SelectedTool, DestructiveRectFromDrag(start, current));
            }
                        else if (SelectedTool == EditorTool.InsertImage)
            {
                AddImageOverlayFromDrag(start, current);
            }
            else if (SelectedTool == EditorTool.InsertScreenImage)
            {
                AddScreenImageOverlayFromDrag(start, current);
            }
            else if (CreateOverlayFromDrag(SelectedTool, start, current) is { } overlay)
            {
                PushUndoSnapshot();
                overlays.Add(overlay);
                selectedOverlayIndex = overlays.Count - 1;
            }
        }

        activeOverlayStart = null;
        activeOverlayCurrent = null;
        isDrawingOverlay = false;
        EditorSurface.ReleaseMouseCapture();
        RedrawOverlayCanvas();
        RefreshEditorState();
    }

    private EditorOverlay? CreateOverlayFromDrag(EditorTool tool, WpfPoint start, WpfPoint current)
    {
        if (baseImage is null)
        {
            return null;
        }

        var startPixels = DenormalizePoint(start);
        var currentPixels = DenormalizePoint(current);
        var rect = RectBetween(startPixels, currentPixels);
        if (rect.Width < 5 || rect.Height < 5)
        {
            rect = new Rect(startPixels.X - 160, startPixels.Y - 120, 320, 240);
        }

        rect = ClampRectToImage(rect);
        var a = new WpfPoint(rect.Left / baseImage.PixelWidth, rect.Top / baseImage.PixelHeight);
        var b = new WpfPoint(rect.Right / baseImage.PixelWidth, rect.Bottom / baseImage.PixelHeight);

        return tool switch
        {
            EditorTool.Line => new EditorOverlay(OverlayKind.Line, a, b, selectedInkColor, strokeWidth),
            EditorTool.Arrow => new EditorOverlay(OverlayKind.Arrow, a, b, selectedInkColor, strokeWidth),
            EditorTool.Rectangle => new EditorOverlay(OverlayKind.Rectangle, a, b, selectedInkColor, strokeWidth),
            EditorTool.FilledRectangle => new EditorOverlay(OverlayKind.FilledRectangle, a, b, selectedInkColor, 0),
            EditorTool.Ellipse => new EditorOverlay(OverlayKind.Ellipse, a, b, selectedInkColor, strokeWidth),
            EditorTool.HighlightBox => new EditorOverlay(OverlayKind.HighlightBox, a, b, HighlightColor, Math.Max(1, strokeWidth * 0.35)),
            EditorTool.Magnifier => new EditorOverlay(OverlayKind.Magnifier, a, b, Colors.White, Math.Max(1, strokeWidth * 0.35), MagnifierZoomForFilterStrength()),
            _ => null
        };
    }



    private void AddImageOverlayFromDrag(WpfPoint start, WpfPoint current)
    {
        if (baseImage is null)
        {
            return;
        }

        var rect = DestructiveRectFromDrag(start, current);
        if (rect.Width < 1 || rect.Height < 1)
        {
            return;
        }

        var image = PromptForOverlayImage();
        if (image is null)
        {
            return;
        }

        var a = new WpfPoint(rect.Left / baseImage.PixelWidth, rect.Top / baseImage.PixelHeight);
        var b = new WpfPoint(rect.Right / baseImage.PixelWidth, rect.Bottom / baseImage.PixelHeight);
        AddOverlay(new EditorOverlay(OverlayKind.Image, a, b, Colors.White, 0, FontSize: 0, ImageAlpha: 1.0, Image: image));
    }

    private BitmapSource? PromptForOverlayImage()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Insert Image",
            Filter = "Image files|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp|All files|*.*",
            CheckFileExists = true,
            Multiselect = false
        };

        if (dialog.ShowDialog(this) != true)
        {
            return null;
        }

        var image = LoadOverlayImage(dialog.FileName);
        if (image is null)
        {
            NotifyEditor("Failed to load image");
        }

        return image;
    }
    private async void AddScreenImageOverlayFromDrag(WpfPoint start, WpfPoint current)
    {
        if (baseImage is null)
        {
            return;
        }

        if (screenCapture is null)
        {
            NotifyEditor("Screen capture is not available.");
            return;
        }

        var rect = DestructiveRectFromDrag(start, current);
        if (rect.Width < 1 || rect.Height < 1)
        {
            return;
        }

        string? capturePath = null;
        string? errorMessage = null;
        try
        {
            Hide();
            var result = await screenCapture.CaptureAsync(
                new CaptureRequest(CraftyCannon.Core.CaptureMode.FullScreen, FixedRegion: null, TimeSpan.FromMilliseconds(150), IncludeCursor: false, RecordingDuration: null),
                CancellationToken.None);
            capturePath = result.FilePath;
        }
        catch (Exception ex)
        {
            errorMessage = "Screen image capture failed: " + ex.Message;
        }
        finally
        {
            Show();
            Activate();
        }

        if (errorMessage is not null)
        {
            NotifyEditor(errorMessage);
            return;
        }

        if (baseImage is null || capturePath is null)
        {
            return;
        }

        var image = LoadOverlayImage(capturePath);
        try
        {
            File.Delete(capturePath);
        }
        catch
        {
        }

        if (image is null)
        {
            NotifyEditor("Failed to load captured image");
            return;
        }

        var a = new WpfPoint(rect.Left / baseImage.PixelWidth, rect.Top / baseImage.PixelHeight);
        var b = new WpfPoint(rect.Right / baseImage.PixelWidth, rect.Bottom / baseImage.PixelHeight);
        AddOverlay(new EditorOverlay(OverlayKind.Image, a, b, Colors.White, 0, FontSize: 0, ImageAlpha: 1.0, Image: image));
    }
    private static BitmapSource? LoadOverlayImage(string path)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(System.IO.Path.GetFullPath(path), UriKind.Absolute);
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    private void ApplyResize(int width, int height)
    {
        if (baseImage is null)
        {
            return;
        }

        width = Math.Max(1, width);
        height = Math.Max(1, height);
        PushUndoSnapshot();
        CommitEditsToBase();
        if (ResizeBaseImage(width, height) is { } resized)
        {
            selectedOverlayIndex = null;
            SetBaseImage(resized);
            FitImageToViewport();
        }
    }

    private void ApplyTransform(ImageTransform transform)
    {
        if (baseImage is null)
        {
            return;
        }

        PushUndoSnapshot();
        CommitEditsToBase();
        var output = transform switch
        {
            ImageTransform.RotateLeft => RotateBaseImage(clockwise: false),
            ImageTransform.RotateRight => RotateBaseImage(clockwise: true),
            ImageTransform.FlipHorizontal => FlipBaseImage(horizontal: true),
            ImageTransform.FlipVertical => FlipBaseImage(horizontal: false),
            _ => baseImage
        };

        if (output is not null)
        {
            selectedOverlayIndex = null;
            SetBaseImage(output);
            FitImageToViewport();
        }
    }

    private BitmapSource? ResizeBaseImage(int newWidth, int newHeight)
    {
        if (baseImage is null)
        {
            return null;
        }

        var source = ConvertToPbgra(baseImage);
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var context = visual.RenderOpen())
        {
            context.DrawImage(source, new Rect(0, 0, newWidth, newHeight));
        }

        var bitmap = new RenderTargetBitmap(newWidth, newHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    private BitmapSource? RotateBaseImage(bool clockwise)
    {
        if (baseImage is null)
        {
            return null;
        }

        var source = ConvertToPbgra(baseImage);
        var sourceWidth = source.PixelWidth;
        var sourceHeight = source.PixelHeight;
        var sourceStride = sourceWidth * 4;
        var sourcePixels = new byte[sourceStride * sourceHeight];
        source.CopyPixels(sourcePixels, sourceStride, 0);

        var destWidth = sourceHeight;
        var destHeight = sourceWidth;
        var destStride = destWidth * 4;
        var destPixels = new byte[destStride * destHeight];
        for (var y = 0; y < sourceHeight; y++)
        {
            for (var x = 0; x < sourceWidth; x++)
            {
                var destX = clockwise ? sourceHeight - 1 - y : y;
                var destY = clockwise ? x : sourceWidth - 1 - x;
                CopyPixel(sourcePixels, sourceStride, x, y, destPixels, destStride, destX, destY);
            }
        }

        var bitmap = BitmapSource.Create(destWidth, destHeight, 96, 96, PixelFormats.Pbgra32, null, destPixels, destStride);
        bitmap.Freeze();
        return bitmap;
    }

    private BitmapSource? FlipBaseImage(bool horizontal)
    {
        if (baseImage is null)
        {
            return null;
        }

        var source = ConvertToPbgra(baseImage);
        var width = source.PixelWidth;
        var height = source.PixelHeight;
        var stride = width * 4;
        var sourcePixels = new byte[stride * height];
        var destPixels = new byte[stride * height];
        source.CopyPixels(sourcePixels, stride, 0);

        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var destX = horizontal ? width - 1 - x : x;
                var destY = horizontal ? y : height - 1 - y;
                CopyPixel(sourcePixels, stride, x, y, destPixels, stride, destX, destY);
            }
        }

        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, destPixels, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private static void CopyPixel(byte[] source, int sourceStride, int sourceX, int sourceY, byte[] destination, int destinationStride, int destinationX, int destinationY)
    {
        var sourceOffset = (sourceY * sourceStride) + (sourceX * 4);
        var destinationOffset = (destinationY * destinationStride) + (destinationX * 4);
        destination[destinationOffset] = source[sourceOffset];
        destination[destinationOffset + 1] = source[sourceOffset + 1];
        destination[destinationOffset + 2] = source[sourceOffset + 2];
        destination[destinationOffset + 3] = source[sourceOffset + 3];
    }

    private void ApplyDestructiveTool(EditorTool tool, Rect pixelRect)
    {
        if (baseImage is null || pixelRect.Width < 1 || pixelRect.Height < 1)
        {
            return;
        }

        PushUndoSnapshot();
        CommitEditsToBase();

        var bounds = PixelBounds(pixelRect, baseImage.PixelWidth, baseImage.PixelHeight);
        if (bounds.Width <= 0 || bounds.Height <= 0)
        {
            return;
        }

        var output = tool switch
        {
            EditorTool.Crop => CropBaseImage(bounds),
            EditorTool.Blur => FilterBaseImage(bounds, PixelFilter.Blur),
            EditorTool.Pixelate => FilterBaseImage(bounds, PixelFilter.Pixelate),
            EditorTool.BlackRedact => FilterBaseImage(bounds, PixelFilter.BlackRedact),
            _ => baseImage
        };

        if (output is not null)
        {
            selectedOverlayIndex = null;
            SetBaseImage(output);
        }
    }

    private void CommitEditsToBase()
    {
        if (baseImage is null || (strokes.Count == 0 && overlays.Count == 0))
        {
            return;
        }

        SetBaseImage(RenderCompositeImage());
        strokes.Clear();
        overlays.Clear();
        selectedOverlayIndex = null;
        RedrawInkCanvas();
        RedrawOverlayCanvas();
    }

    private Rect DestructiveRectFromDrag(WpfPoint start, WpfPoint current)
    {
        if (baseImage is null)
        {
            return Rect.Empty;
        }

        var startPixels = DenormalizePoint(start);
        var currentPixels = DenormalizePoint(current);
        var rect = RectBetween(startPixels, currentPixels);
        if (rect.Width < 5 || rect.Height < 5)
        {
            rect = new Rect(startPixels.X - 160, startPixels.Y - 120, 320, 240);
        }

        return ClampRectToImage(rect);
    }

    private BitmapSource? CropBaseImage(Int32Rect bounds)
    {
        if (baseImage is null)
        {
            return null;
        }

        var source = ConvertToPbgra(baseImage);
        var stride = bounds.Width * 4;
        var cropped = new byte[stride * bounds.Height];
        source.CopyPixels(bounds, cropped, stride, 0);
        var bitmap = BitmapSource.Create(bounds.Width, bounds.Height, 96, 96, PixelFormats.Pbgra32, null, cropped, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private BitmapSource? FilterBaseImage(Int32Rect bounds, PixelFilter filter)
    {
        if (baseImage is null)
        {
            return null;
        }

        var source = ConvertToPbgra(baseImage);
        var width = source.PixelWidth;
        var height = source.PixelHeight;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        source.CopyPixels(pixels, stride, 0);

        switch (filter)
        {
            case PixelFilter.Blur:
                BlurRegion(pixels, width, height, bounds, (int)Math.Round(filterStrength));
                break;
            case PixelFilter.Pixelate:
                PixelateRegion(pixels, width, height, bounds, Math.Max(2, (int)Math.Round(filterStrength)));
                break;
            case PixelFilter.BlackRedact:
                FillRegion(pixels, width, height, bounds, Colors.Black);
                break;
        }

        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private static BitmapSource? ApplySmartRedactionFindings(BitmapSource image, IReadOnlyList<RedactionFinding> findings, SmartRedactionRenderMode mode, double filterStrength = DefaultFilterStrength)
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

        var applied = 0;
        foreach (var finding in findings)
        {
            var pixelRect = new Rect(finding.X * width, finding.Y * height, finding.Width * width, finding.Height * height);
            var bounds = PixelBounds(pixelRect, width, height);
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                continue;
            }

            if (mode == SmartRedactionRenderMode.BlackBox)
            {
                FillRegion(pixels, width, height, bounds, Colors.Black);
            }
            else
            {
                PixelateRegion(pixels, width, height, bounds, Math.Max(2, (int)Math.Round(filterStrength)));
            }

            applied++;
        }

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

        var converted = new FormatConvertedBitmap();
        converted.BeginInit();
        converted.Source = image;
        converted.DestinationFormat = PixelFormats.Pbgra32;
        converted.EndInit();
        converted.Freeze();
        return converted;
    }

    private static Int32Rect PixelBounds(Rect rect, int imageWidth, int imageHeight)
    {
        var left = Math.Clamp((int)Math.Floor(rect.Left), 0, imageWidth);
        var top = Math.Clamp((int)Math.Floor(rect.Top), 0, imageHeight);
        var right = Math.Clamp((int)Math.Ceiling(rect.Right), 0, imageWidth);
        var bottom = Math.Clamp((int)Math.Ceiling(rect.Bottom), 0, imageHeight);
        return new Int32Rect(left, top, Math.Max(0, right - left), Math.Max(0, bottom - top));
    }

    private static void FillRegion(byte[] pixels, int width, int height, Int32Rect bounds, WpfColor color)
    {
        var right = Math.Min(width, bounds.X + bounds.Width);
        var bottom = Math.Min(height, bounds.Y + bounds.Height);
        for (var y = bounds.Y; y < bottom; y++)
        {
            var offset = (y * width + bounds.X) * 4;
            for (var x = bounds.X; x < right; x++)
            {
                pixels[offset] = color.B;
                pixels[offset + 1] = color.G;
                pixels[offset + 2] = color.R;
                pixels[offset + 3] = 255;
                offset += 4;
            }
        }
    }

    private static void PixelateRegion(byte[] pixels, int width, int height, Int32Rect bounds, int blockSize)
    {
        var right = Math.Min(width, bounds.X + bounds.Width);
        var bottom = Math.Min(height, bounds.Y + bounds.Height);
        for (var y = bounds.Y; y < bottom; y += blockSize)
        {
            for (var x = bounds.X; x < right; x += blockSize)
            {
                var blockRight = Math.Min(right, x + blockSize);
                var blockBottom = Math.Min(bottom, y + blockSize);
                long b = 0;
                long g = 0;
                long r = 0;
                long a = 0;
                var count = 0;
                for (var yy = y; yy < blockBottom; yy++)
                {
                    var offset = (yy * width + x) * 4;
                    for (var xx = x; xx < blockRight; xx++)
                    {
                        b += pixels[offset];
                        g += pixels[offset + 1];
                        r += pixels[offset + 2];
                        a += pixels[offset + 3];
                        count++;
                        offset += 4;
                    }
                }

                if (count == 0)
                {
                    continue;
                }

                var bb = (byte)(b / count);
                var gg = (byte)(g / count);
                var rr = (byte)(r / count);
                var aa = (byte)(a / count);
                for (var yy = y; yy < blockBottom; yy++)
                {
                    var offset = (yy * width + x) * 4;
                    for (var xx = x; xx < blockRight; xx++)
                    {
                        pixels[offset] = bb;
                        pixels[offset + 1] = gg;
                        pixels[offset + 2] = rr;
                        pixels[offset + 3] = aa;
                        offset += 4;
                    }
                }
            }
        }
    }

    private static void BlurRegion(byte[] pixels, int width, int height, Int32Rect bounds, int radius)
    {
        radius = Math.Clamp(radius, 1, 40);
        var right = Math.Min(width, bounds.X + bounds.Width);
        var bottom = Math.Min(height, bounds.Y + bounds.Height);
        var regionWidth = right - bounds.X;
        var regionHeight = bottom - bounds.Y;
        if (regionWidth <= 0 || regionHeight <= 0)
        {
            return;
        }

        var source = new byte[regionWidth * regionHeight * 4];
        for (var y = 0; y < regionHeight; y++)
        {
            Buffer.BlockCopy(pixels, ((bounds.Y + y) * width + bounds.X) * 4, source, y * regionWidth * 4, regionWidth * 4);
        }

        var horizontal = new byte[source.Length];
        for (var y = 0; y < regionHeight; y++)
        {
            for (var x = 0; x < regionWidth; x++)
            {
                AverageSpan(source, horizontal, regionWidth, regionHeight, x, y, Math.Max(0, x - radius), Math.Min(regionWidth - 1, x + radius), y, y);
            }
        }

        var blurred = new byte[source.Length];
        for (var y = 0; y < regionHeight; y++)
        {
            for (var x = 0; x < regionWidth; x++)
            {
                AverageSpan(horizontal, blurred, regionWidth, regionHeight, x, y, x, x, Math.Max(0, y - radius), Math.Min(regionHeight - 1, y + radius));
            }
        }

        for (var y = 0; y < regionHeight; y++)
        {
            Buffer.BlockCopy(blurred, y * regionWidth * 4, pixels, ((bounds.Y + y) * width + bounds.X) * 4, regionWidth * 4);
        }
    }

    private static void AverageSpan(byte[] source, byte[] destination, int width, int height, int x, int y, int left, int right, int top, int bottom)
    {
        long b = 0;
        long g = 0;
        long r = 0;
        long a = 0;
        var count = 0;
        for (var yy = top; yy <= bottom; yy++)
        {
            for (var xx = left; xx <= right; xx++)
            {
                var offset = (yy * width + xx) * 4;
                b += source[offset];
                g += source[offset + 1];
                r += source[offset + 2];
                a += source[offset + 3];
                count++;
            }
        }

        var destinationOffset = (y * width + x) * 4;
        destination[destinationOffset] = (byte)(b / count);
        destination[destinationOffset + 1] = (byte)(g / count);
        destination[destinationOffset + 2] = (byte)(r / count);
        destination[destinationOffset + 3] = (byte)(a / count);
    }

    private void AddTextOverlay(EditorTool tool, WpfPoint point)
    {
        var title = tool switch
        {
            EditorTool.TextOutline => "Text (Outline)",
            EditorTool.TextBackground => "Text (Background)",
            EditorTool.SpeechBalloon => "Speech Balloon",
            _ => "Text"
        };
        var text = PromptEditorText(title, "Enter text.", multiLine: true);
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        var kind = tool switch
        {
            EditorTool.TextOutline => OverlayKind.TextOutline,
            EditorTool.TextBackground => OverlayKind.TextBackground,
            EditorTool.SpeechBalloon => OverlayKind.SpeechBalloon,
            _ => OverlayKind.Text
        };
        var fill = WpfColor.FromArgb(191, selectedInkColor.R, selectedInkColor.G, selectedInkColor.B);
        var textColor = kind is OverlayKind.SpeechBalloon or OverlayKind.TextBackground ? ContrastingTextColor(fill) : selectedInkColor;
        var overlay = new EditorOverlay(
            kind,
            point,
            point,
            textColor,
            strokeWidth,
            Text: text.Trim(),
            FontSize: fontSize,
            FillColor: kind is OverlayKind.SpeechBalloon or OverlayKind.TextBackground ? fill : null,
            OutlineColor: kind is OverlayKind.SpeechBalloon or OverlayKind.TextOutline or OverlayKind.TextBackground ? selectedInkColor : null,
            OutlineWidth: kind is OverlayKind.SpeechBalloon or OverlayKind.TextBackground ? Math.Max(2, strokeWidth * 0.4) : (kind == OverlayKind.TextOutline ? Math.Max(2, strokeWidth * 0.35) : 0),
            Padding: kind == OverlayKind.SpeechBalloon ? 12 : (kind == OverlayKind.TextBackground ? 8 : 0));
        AddOverlay(overlay);
    }

    private void AddStepOverlay(WpfPoint center)
    {
        if (baseImage is null)
        {
            return;
        }

        var halfW = (StepDiameter / baseImage.PixelWidth) / 2;
        var halfH = (StepDiameter / baseImage.PixelHeight) / 2;
        var a = new WpfPoint(Math.Clamp(center.X - halfW, 0, 1), Math.Clamp(center.Y - halfH, 0, 1));
        var b = new WpfPoint(Math.Clamp(center.X + halfW, 0, 1), Math.Clamp(center.Y + halfH, 0, 1));
        var overlay = new EditorOverlay(OverlayKind.StepMarker, a, b, selectedInkColor, Math.Max(1, strokeWidth * 0.35), Text: nextStepNumber.ToString(CultureInfo.InvariantCulture), FontSize: fontSize);
        nextStepNumber++;
        AddOverlay(overlay);
    }

    private void AddStickerOverlay(WpfPoint point)
    {
        if (string.IsNullOrWhiteSpace(stickerText))
        {
            var value = PromptEditorText("Sticker", "Enter sticker text (emoji or short label).", multiLine: false, initialValue: stickerText);
            if (string.IsNullOrWhiteSpace(value))
            {
                return;
            }

            stickerText = value.Trim();
        }

        AddOverlay(new EditorOverlay(OverlayKind.Sticker, point, point, selectedInkColor, 0, Text: stickerText, FontSize: fontSize));
    }

    private void AddCursorOverlay(WpfPoint point)
    {
        AddOverlay(new EditorOverlay(OverlayKind.CursorStamp, point, point, selectedInkColor, strokeWidth, FontSize: fontSize, ImageAlpha: 1.0));
    }

    private void AddOverlay(EditorOverlay overlay)
    {
        PushUndoSnapshot();
        overlays.Add(overlay);
        selectedOverlayIndex = overlays.Count - 1;
        RedrawOverlayCanvas();
        RefreshEditorState();
    }

    private string? PromptEditorText(string title, string prompt, bool multiLine, string initialValue = "")
    {
        var dialog = new PromptWindow(title, prompt, multiLine, initialValue)
        {
            Owner = this
        };
        return dialog.ShowDialog() == true ? dialog.Value : null;
    }
    private void SmartEraseAt(WpfPoint normalizedPoint)
    {
        if (baseImage is null)
        {
            return;
        }

        if (!didRequestSmartEraserUndo)
        {
            didRequestSmartEraserUndo = true;
            PushUndoSnapshot();
        }

        var center = DenormalizePoint(normalizedPoint);
        var radius = Math.Max(12, strokeWidth * 2.4);
        var kept = strokes.Where(stroke => !StrokeIntersectsCircle(stroke, center, radius)).ToList();
        if (kept.Count != strokes.Count)
        {
            strokes.Clear();
            strokes.AddRange(kept);
            RedrawInkCanvas();
        }

        var keptOverlays = overlays.Where(overlay => !CircleIntersectsRect(center, radius, InflateRect(OverlayBounds(overlay), 2, 2))).ToList();
        if (keptOverlays.Count != overlays.Count)
        {
            overlays.Clear();
            overlays.AddRange(keptOverlays);
            selectedOverlayIndex = null;
            RedrawOverlayCanvas();
        }

        RefreshEditorState();
    }

    private bool StrokeIntersectsCircle(EditorInkStroke stroke, WpfPoint center, double radius)
    {
        if (stroke.Points.Count < 2)
        {
            return false;
        }

        var last = DenormalizePoint(stroke.Points[0]);
        foreach (var point in stroke.Points.Skip(1))
        {
            var current = DenormalizePoint(point);
            if (DistancePointToSegment(center, last, current) <= radius)
            {
                return true;
            }

            last = current;
        }

        return false;
    }

    private static double DistancePointToSegment(WpfPoint point, WpfPoint start, WpfPoint end)
    {
        var dx = end.X - start.X;
        var dy = end.Y - start.Y;
        if (Math.Abs(dx) < double.Epsilon && Math.Abs(dy) < double.Epsilon)
        {
            return Distance(point, start);
        }

        var t = (((point.X - start.X) * dx) + ((point.Y - start.Y) * dy)) / ((dx * dx) + (dy * dy));
        t = Math.Clamp(t, 0, 1);
        return Distance(point, new WpfPoint(start.X + (t * dx), start.Y + (t * dy)));
    }

    private void Undo_Click(object sender, RoutedEventArgs e) => UndoAction();

    private void Redo_Click(object sender, RoutedEventArgs e) => RedoAction();

    private void UndoAction()
    {
        if (undoStack.Count == 0)
        {
            return;
        }

        redoStack.Add(CurrentSnapshot());
        var snapshot = undoStack[^1];
        undoStack.RemoveAt(undoStack.Count - 1);
        Restore(snapshot);
    }

    private void RedoAction()
    {
        if (redoStack.Count == 0)
        {
            return;
        }

        undoStack.Add(CurrentSnapshot());
        var snapshot = redoStack[^1];
        redoStack.RemoveAt(redoStack.Count - 1);
        Restore(snapshot);
    }

    private void ToolPicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        CancelActiveInteraction();
        if (ToolList is not null && ToolList.SelectedItem != ToolPicker.SelectedItem)
        {
            ToolList.SelectedItem = ToolPicker.SelectedItem;
        }

        RefreshEditorState();
    }

    private void ToolList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        CancelActiveInteraction();
        if (ToolPicker is not null && ToolPicker.SelectedItem != ToolList.SelectedItem)
        {
            ToolPicker.SelectedItem = ToolList.SelectedItem;
        }

        RefreshEditorState();
    }

    private void RedrawInkCanvas()
    {
        InkCanvas.Children.Clear();
        activePolyline = null;
        RemoveActiveArrowHead();
        RedrawInkLayer();
    }

    private void RedrawInkLayer()
    {
        InkLayerImage.Source = RenderInkLayerBitmap(strokes);
    }

    private void RedrawOverlayCanvas()
    {
        OverlayCanvas.Children.Clear();
        for (var i = 0; i < overlays.Count; i++)
        {
            OverlayCanvas.Children.Add(CreateOverlayElement(overlays[i], selectedOverlayIndex == i));
        }

        if (isDrawingOverlay && activeOverlayStart is { } start && activeOverlayCurrent is { } current)
        {
            if (IsDestructiveRectTool(SelectedTool))
            {
                OverlayCanvas.Children.Add(CreateDestructiveDragPreview(SelectedTool, start, current));
            }
            else if (IsImageInsertTool(SelectedTool))
            {
                OverlayCanvas.Children.Add(CreateImageInsertDragPreview(start, current));
            }
            else if (CreateOverlayFromDrag(SelectedTool, start, current) is { } preview)
            {
                OverlayCanvas.Children.Add(SelectedTool == EditorTool.Magnifier
                    ? CreateMagnifierDragPreview(preview)
                    : CreateOverlayElement(preview with { Color = WpfColor.FromArgb(180, preview.Color.R, preview.Color.G, preview.Color.B) }, selected: false));
            }
        }
    }

    private UIElement CreateMagnifierDragPreview(EditorOverlay overlay)
    {
        var rect = RectBetween(DenormalizePoint(overlay.A), DenormalizePoint(overlay.B));
        return PositionShape(new System.Windows.Shapes.Rectangle
        {
            Width = rect.Width,
            Height = rect.Height,
            Stroke = new SolidColorBrush(Colors.MediumPurple),
            StrokeThickness = 2
        }, rect);
    }

    private UIElement CreateDestructiveDragPreview(EditorTool tool, WpfPoint start, WpfPoint current)
    {
        var rect = baseImage is null ? Rect.Empty : ClampRectToImage(RectBetween(DenormalizePoint(start), DenormalizePoint(current)));
        var color = tool switch
        {
            EditorTool.Crop => Colors.DodgerBlue,
            EditorTool.BlackRedact => Colors.Black,
            _ => WpfColor.FromArgb(180, DefaultInkColor.R, DefaultInkColor.G, DefaultInkColor.B)
        };

        return PositionShape(new System.Windows.Shapes.Rectangle
        {
            Width = rect.Width,
            Height = rect.Height,
            Stroke = new SolidColorBrush(color),
            StrokeThickness = 2
        }, rect);
    }

    private UIElement CreateImageInsertDragPreview(WpfPoint start, WpfPoint current)
    {
        var rect = baseImage is null ? Rect.Empty : ClampRectToImage(RectBetween(DenormalizePoint(start), DenormalizePoint(current)));
        return PositionShape(new System.Windows.Shapes.Rectangle
        {
            Width = rect.Width,
            Height = rect.Height,
            Stroke = new SolidColorBrush(Colors.Teal),
            StrokeThickness = 2
        }, rect);
    }
    private UIElement CreateOverlayElement(EditorOverlay overlay, bool selected)
    {
        var group = new Canvas { Width = OverlayCanvas.Width, Height = OverlayCanvas.Height, IsHitTestVisible = false };
        var a = DenormalizePoint(overlay.A);
        var b = DenormalizePoint(overlay.B);
        var rect = RectBetween(a, b);
        var brush = new SolidColorBrush(overlay.Color);
        var stroke = overlay.Kind == OverlayKind.HighlightBox
            ? new SolidColorBrush(WpfColor.FromArgb(153, overlay.Color.R, overlay.Color.G, overlay.Color.B))
            : brush;
        var strokeThickness = overlay.Kind == OverlayKind.FilledRectangle ? 0 : overlay.Width;

        switch (overlay.Kind)
        {
            case OverlayKind.Line:
                group.Children.Add(NewLine(a, b, stroke, strokeThickness));
                break;
            case OverlayKind.Arrow:
                group.Children.Add(NewLine(a, b, stroke, strokeThickness));
                foreach (var line in NewArrowHeadLines(a, b, stroke, strokeThickness))
                {
                    group.Children.Add(line);
                }
                break;
            case OverlayKind.Rectangle:
                group.Children.Add(PositionShape(new System.Windows.Shapes.Rectangle { Width = rect.Width, Height = rect.Height, Stroke = stroke, StrokeThickness = strokeThickness }, rect));
                break;
            case OverlayKind.FilledRectangle:
                group.Children.Add(PositionShape(new System.Windows.Shapes.Rectangle { Width = rect.Width, Height = rect.Height, Fill = brush }, rect));
                break;
            case OverlayKind.Ellipse:
                group.Children.Add(PositionShape(new Ellipse { Width = rect.Width, Height = rect.Height, Stroke = stroke, StrokeThickness = strokeThickness }, rect));
                break;
            case OverlayKind.HighlightBox:
                group.Children.Add(PositionShape(new System.Windows.Shapes.Rectangle { Width = rect.Width, Height = rect.Height, Fill = new SolidColorBrush(WpfColor.FromArgb(64, overlay.Color.R, overlay.Color.G, overlay.Color.B)), Stroke = stroke, StrokeThickness = 2 }, rect));
                break;
            case OverlayKind.Magnifier:
                group.Children.Add(PositionShape(new Ellipse { Width = rect.Width, Height = rect.Height, Fill = CreateMagnifierBrush(rect, overlay.MagnifyZoom), Stroke = new SolidColorBrush(WpfColor.FromArgb(51, 0, 0, 0)), StrokeThickness = Math.Max(2, overlay.Width) }, rect));
                break;
            case OverlayKind.Image:
            case OverlayKind.Text:
            case OverlayKind.TextOutline:
            case OverlayKind.TextBackground:
            case OverlayKind.SpeechBalloon:
            case OverlayKind.StepMarker:
            case OverlayKind.Sticker:
            case OverlayKind.CursorStamp:
                group.Children.Add(CreateDrawingElement(overlay, includeSelection: false));
                break;
        }

        if (selected)
        {
            var bounds = InflateRect(OverlayBounds(overlay), 4, 4);
            var selection = new System.Windows.Shapes.Rectangle
            {
                Width = bounds.Width,
                Height = bounds.Height,
                Stroke = new SolidColorBrush(Colors.DodgerBlue),
                StrokeThickness = 1.5,
                StrokeDashArray = [4, 3]
            };
            group.Children.Add(PositionShape(selection, bounds));
        }

        return group;
    }

    private void DrawOverlay(DrawingContext context, EditorOverlay overlay, bool includeSelection)
    {
        var a = DenormalizePoint(overlay.A);
        var b = DenormalizePoint(overlay.B);
        var rect = RectBetween(a, b);
        var brush = new SolidColorBrush(overlay.Color);
        var pen = overlay.Width > 0 ? CreateOverlayPen(overlay.Color, overlay.Width) : null;

        switch (overlay.Kind)
        {
            case OverlayKind.Line:
                context.DrawLine(pen, a, b);
                break;
            case OverlayKind.Arrow:
                context.DrawLine(pen, a, b);
                DrawOverlayArrowHead(context, a, b, pen!, overlay.Width);
                break;
            case OverlayKind.Rectangle:
                context.DrawRectangle(null, pen, rect);
                break;
            case OverlayKind.FilledRectangle:
                context.DrawRectangle(brush, null, rect);
                break;
            case OverlayKind.Ellipse:
                context.DrawEllipse(null, pen, new WpfPoint(rect.Left + (rect.Width / 2), rect.Top + (rect.Height / 2)), rect.Width / 2, rect.Height / 2);
                break;
            case OverlayKind.HighlightBox:
                context.DrawRectangle(new SolidColorBrush(WpfColor.FromArgb(64, overlay.Color.R, overlay.Color.G, overlay.Color.B)), CreateOverlayPen(WpfColor.FromArgb(153, overlay.Color.R, overlay.Color.G, overlay.Color.B), 2), rect);
                break;
            case OverlayKind.Magnifier:
                context.DrawEllipse(CreateMagnifierBrush(rect, overlay.MagnifyZoom), CreateOverlayPen(WpfColor.FromArgb(51, 0, 0, 0), Math.Max(2, overlay.Width)), new WpfPoint(rect.Left + (rect.Width / 2), rect.Top + (rect.Height / 2)), rect.Width / 2, rect.Height / 2);
                break;
            case OverlayKind.Image:
                DrawImageOverlay(context, overlay, rect);
                break;
            case OverlayKind.Text:
                DrawText(context, overlay, a);
                break;
            case OverlayKind.TextOutline:
                DrawTextOutline(context, overlay, a);
                break;
            case OverlayKind.TextBackground:
                DrawTextBackground(context, overlay, a);
                break;
            case OverlayKind.SpeechBalloon:
                DrawSpeechBalloon(context, overlay, a);
                break;
            case OverlayKind.StepMarker:
                DrawStepMarker(context, overlay, rect);
                break;
            case OverlayKind.Sticker:
                DrawSticker(context, overlay, a);
                break;
            case OverlayKind.CursorStamp:
                DrawCursorStamp(context, overlay, a);
                break;
        }

        if (includeSelection)
        {
            var bounds = InflateRect(OverlayBounds(overlay), 4, 4);
            context.DrawRectangle(null, new System.Windows.Media.Pen(new SolidColorBrush(Colors.DodgerBlue), 1.5) { DashStyle = DashStyles.Dash }, bounds);
        }
    }

    private ImageBrush CreateMagnifierBrush(Rect lens, double zoom)
    {
        var source = MagnifierSourceRect(lens, zoom);
        return new ImageBrush(baseImage)
        {
            ViewboxUnits = BrushMappingMode.Absolute,
            Viewbox = source,
            Stretch = Stretch.Fill
        };
    }

    private Rect MagnifierSourceRect(Rect lens, double zoom)
    {
        if (baseImage is null || lens.Width <= 0 || lens.Height <= 0)
        {
            return Rect.Empty;
        }

        var effectiveZoom = Math.Max(1.2, zoom);
        var sourceWidth = lens.Width / effectiveZoom;
        var sourceHeight = lens.Height / effectiveZoom;
        var left = lens.Left + (lens.Width / 2) - (sourceWidth / 2);
        var top = lens.Top + (lens.Height / 2) - (sourceHeight / 2);
        left = Math.Clamp(left, 0, Math.Max(0, baseImage.PixelWidth - sourceWidth));
        top = Math.Clamp(top, 0, Math.Max(0, baseImage.PixelHeight - sourceHeight));
        return new Rect(left, top, Math.Min(sourceWidth, baseImage.PixelWidth), Math.Min(sourceHeight, baseImage.PixelHeight));
    }

    private UIElement CreateDrawingElement(EditorOverlay overlay, bool includeSelection)
    {
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            DrawOverlay(context, overlay, includeSelection);
        }

        return new OverlayVisualHost(visual)
        {
            Width = OverlayCanvas.Width,
            Height = OverlayCanvas.Height,
            IsHitTestVisible = false
        };
    }


    private void DrawImageOverlay(DrawingContext context, EditorOverlay overlay, Rect rect)
    {
        if (overlay.Image is null || rect.Width <= 0 || rect.Height <= 0)
        {
            return;
        }

        var drawBounds = InflateRect(rect, -2, -2);
        if (drawBounds.Width <= 0 || drawBounds.Height <= 0)
        {
            drawBounds = rect;
        }

        var fit = AspectFitRect(overlay.Image.PixelWidth, overlay.Image.PixelHeight, drawBounds);
        context.PushOpacity(Math.Clamp(overlay.ImageAlpha, 0, 1));
        context.DrawImage(overlay.Image, fit);
        context.Pop();
    }

    private static Rect AspectFitRect(double sourceWidth, double sourceHeight, Rect bounds)
    {
        if (sourceWidth <= 0 || sourceHeight <= 0 || bounds.Width <= 0 || bounds.Height <= 0)
        {
            return bounds;
        }

        var scale = Math.Min(bounds.Width / sourceWidth, bounds.Height / sourceHeight);
        var width = sourceWidth * scale;
        var height = sourceHeight * scale;
        return new Rect(bounds.Left + ((bounds.Width - width) / 2), bounds.Top + ((bounds.Height - height) / 2), width, height);
    }
    private void DrawText(DrawingContext context, EditorOverlay overlay, WpfPoint anchor)
    {
        if (string.IsNullOrWhiteSpace(overlay.Text))
        {
            return;
        }

        context.DrawText(CreateFormattedText(overlay.Text, overlay.FontSize, overlay.Color, FontWeights.Normal), anchor);
    }

    private void DrawTextOutline(DrawingContext context, EditorOverlay overlay, WpfPoint anchor)
    {
        if (string.IsNullOrWhiteSpace(overlay.Text))
        {
            return;
        }

        var text = CreateFormattedText(overlay.Text, overlay.FontSize, overlay.Color, FontWeights.SemiBold);
        var geometry = text.BuildGeometry(anchor);
        var outlineColor = overlay.OutlineColor ?? DefaultInkColor;
        var outlineWidth = Math.Max(1.5, overlay.OutlineWidth);
        context.DrawGeometry(new SolidColorBrush(overlay.Color), CreateOverlayPen(outlineColor, outlineWidth), geometry);
    }

    private void DrawTextBackground(DrawingContext context, EditorOverlay overlay, WpfPoint anchor)
    {
        if (string.IsNullOrWhiteSpace(overlay.Text))
        {
            return;
        }

        var text = CreateFormattedText(overlay.Text, overlay.FontSize, overlay.Color, FontWeights.SemiBold);
        var pad = Math.Max(6, overlay.Padding);
        var body = new Rect(anchor.X, anchor.Y, Math.Ceiling(text.WidthIncludingTrailingWhitespace + (pad * 2)), Math.Ceiling(text.Height + (pad * 2)));
        var fill = new SolidColorBrush(overlay.FillColor ?? WpfColor.FromArgb(210, HighlightColor.R, HighlightColor.G, HighlightColor.B));
        var outline = overlay.OutlineColor is { } color && overlay.OutlineWidth > 0 ? CreateOverlayPen(color, overlay.OutlineWidth) : null;
        context.DrawRoundedRectangle(fill, outline, body, 6, 6);
        context.DrawText(text, new WpfPoint(anchor.X + pad, anchor.Y + pad));
    }
    private void DrawSpeechBalloon(DrawingContext context, EditorOverlay overlay, WpfPoint anchor)
    {
        if (string.IsNullOrWhiteSpace(overlay.Text))
        {
            return;
        }

        var text = CreateFormattedText(overlay.Text, overlay.FontSize, overlay.Color, FontWeights.SemiBold);
        var pad = Math.Max(8, overlay.Padding);
        var body = new Rect(anchor.X, anchor.Y, Math.Ceiling(text.WidthIncludingTrailingWhitespace + (pad * 2)), Math.Ceiling(text.Height + (pad * 2)));
        var fill = new SolidColorBrush(overlay.FillColor ?? WpfColor.FromArgb(191, DefaultInkColor.R, DefaultInkColor.G, DefaultInkColor.B));
        var outline = overlay.OutlineColor is { } color && overlay.OutlineWidth > 0 ? CreateOverlayPen(color, overlay.OutlineWidth) : null;
        context.DrawRoundedRectangle(fill, outline, body, 12, 12);

        var tail = new StreamGeometry();
        using (var geometry = tail.Open())
        {
            geometry.BeginFigure(new WpfPoint(body.Left + 18, body.Bottom - 1), isFilled: true, isClosed: true);
            geometry.LineTo(new WpfPoint(body.Left + 6, body.Bottom + 12), isStroked: true, isSmoothJoin: true);
            geometry.LineTo(new WpfPoint(body.Left + 34, body.Bottom - 1), isStroked: true, isSmoothJoin: true);
        }

        tail.Freeze();
        context.DrawGeometry(fill, outline, tail);
        context.DrawText(text, new WpfPoint(anchor.X + pad, anchor.Y + pad));
    }

    private void DrawStepMarker(DrawingContext context, EditorOverlay overlay, Rect rect)
    {
        if (rect.Width <= 0 || rect.Height <= 0)
        {
            return;
        }

        var center = new WpfPoint(rect.Left + (rect.Width / 2), rect.Top + (rect.Height / 2));
        context.DrawEllipse(new SolidColorBrush(overlay.Color), CreateOverlayPen(WpfColor.FromArgb(38, 0, 0, 0), Math.Max(2, overlay.Width)), center, rect.Width / 2, rect.Height / 2);

        var label = overlay.Text ?? string.Empty;
        var fontSize = Math.Max(12, Math.Min(overlay.FontSize, rect.Height * 0.6));
        var text = CreateFormattedText(label, fontSize, Colors.White, FontWeights.Bold);
        context.DrawText(text, new WpfPoint(center.X - (text.WidthIncludingTrailingWhitespace / 2), center.Y - (text.Height / 2)));
    }

    private void DrawSticker(DrawingContext context, EditorOverlay overlay, WpfPoint center)
    {
        if (string.IsNullOrWhiteSpace(overlay.Text))
        {
            return;
        }

        var text = CreateFormattedText(overlay.Text, overlay.FontSize, overlay.Color, FontWeights.Normal);
        context.DrawText(text, new WpfPoint(center.X - (text.WidthIncludingTrailingWhitespace / 2), center.Y - (text.Height / 2)));
    }

    private void DrawCursorStamp(DrawingContext context, EditorOverlay overlay, WpfPoint anchor)
    {
        var size = Math.Max(18, overlay.FontSize);
        var geometry = new StreamGeometry();
        using (var figure = geometry.Open())
        {
            figure.BeginFigure(anchor, isFilled: true, isClosed: true);
            figure.LineTo(new WpfPoint(anchor.X, anchor.Y + size), isStroked: true, isSmoothJoin: true);
            figure.LineTo(new WpfPoint(anchor.X + (size * 0.28), anchor.Y + (size * 0.72)), isStroked: true, isSmoothJoin: true);
            figure.LineTo(new WpfPoint(anchor.X + (size * 0.43), anchor.Y + size), isStroked: true, isSmoothJoin: true);
            figure.LineTo(new WpfPoint(anchor.X + (size * 0.56), anchor.Y + (size * 0.94)), isStroked: true, isSmoothJoin: true);
            figure.LineTo(new WpfPoint(anchor.X + (size * 0.42), anchor.Y + (size * 0.66)), isStroked: true, isSmoothJoin: true);
            figure.LineTo(new WpfPoint(anchor.X + (size * 0.75), anchor.Y + (size * 0.66)), isStroked: true, isSmoothJoin: true);
        }

        geometry.Freeze();
        var alpha = (byte)Math.Round(Math.Clamp(overlay.ImageAlpha, 0, 1) * 255);
        var fill = WpfColor.FromArgb(alpha, overlay.Color.R, overlay.Color.G, overlay.Color.B);
        context.DrawGeometry(new SolidColorBrush(fill), CreateOverlayPen(WpfColor.FromArgb(128, 255, 255, 255), Math.Max(1, overlay.Width * 0.2)), geometry);
    }

    private FormattedText CreateFormattedText(string text, double fontSize, WpfColor color, FontWeight weight)
    {
        return new FormattedText(
            text,
            CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface(new System.Windows.Media.FontFamily("Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal),
            fontSize,
            new SolidColorBrush(color),
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
    }

    private Rect TextRectAt(EditorOverlay overlay, WpfPoint anchor, bool centered)
    {
        if (string.IsNullOrWhiteSpace(overlay.Text))
        {
            return new Rect(anchor.X, anchor.Y, 0, 0);
        }

        var weight = overlay.Kind is OverlayKind.SpeechBalloon or OverlayKind.TextBackground ? FontWeights.SemiBold : FontWeights.Normal;
        var text = CreateFormattedText(overlay.Text, overlay.FontSize, overlay.Color, weight);
        var width = Math.Ceiling(text.WidthIncludingTrailingWhitespace);
        var height = Math.Ceiling(text.Height);
        var rect = centered ? new Rect(anchor.X - (width / 2), anchor.Y - (height / 2), width, height) : new Rect(anchor.X, anchor.Y, width, height);
        return overlay.Kind == OverlayKind.TextBackground ? InflateRect(rect, Math.Max(6, overlay.Padding), Math.Max(4, overlay.Padding)) : rect;
    }

    private Rect SpeechBalloonBounds(EditorOverlay overlay, WpfPoint anchor)
    {
        var textBounds = TextRectAt(overlay, anchor, centered: false);
        var pad = Math.Max(8, overlay.Padding);
        return new Rect(anchor.X, anchor.Y, Math.Ceiling(textBounds.Width + (pad * 2)), Math.Ceiling(textBounds.Height + (pad * 2) + 14));
    }

    private static WpfColor ContrastingTextColor(WpfColor background)
    {
        var luminance = ((0.299 * background.R) + (0.587 * background.G) + (0.114 * background.B)) / 255;
        return luminance > 0.55 ? Colors.Black : Colors.White;
    }

    private static System.Windows.Media.Pen CreateOverlayPen(WpfColor color, double width) => new(new SolidColorBrush(color), width)
    {
        StartLineCap = PenLineCap.Round,
        EndLineCap = PenLineCap.Round,
        LineJoin = PenLineJoin.Round
    };

    private static void DrawOverlayArrowHead(DrawingContext context, WpfPoint start, WpfPoint tip, System.Windows.Media.Pen pen, double width)
    {
        var dx = tip.X - start.X;
        var dy = tip.Y - start.Y;
        var length = Math.Max(1, Math.Sqrt((dx * dx) + (dy * dy)));
        var ux = dx / length;
        var uy = dy / length;
        var headLength = Math.Max(10, width * 3.0);
        const double angle = Math.PI / 7.0;
        var left = Rotate(-ux, -uy, angle);
        var right = Rotate(-ux, -uy, -angle);
        context.DrawLine(pen, tip, new WpfPoint(tip.X + (left.X * headLength), tip.Y + (left.Y * headLength)));
        context.DrawLine(pen, tip, new WpfPoint(tip.X + (right.X * headLength), tip.Y + (right.Y * headLength)));
    }

    private static IReadOnlyList<Line> NewArrowHeadLines(WpfPoint start, WpfPoint tip, System.Windows.Media.Brush stroke, double width)
    {
        var dx = tip.X - start.X;
        var dy = tip.Y - start.Y;
        var length = Math.Max(1, Math.Sqrt((dx * dx) + (dy * dy)));
        var ux = dx / length;
        var uy = dy / length;
        var headLength = Math.Max(10, width * 3.0);
        const double angle = Math.PI / 7.0;
        var left = Rotate(-ux, -uy, angle);
        var right = Rotate(-ux, -uy, -angle);
        return [
            NewLine(tip, new WpfPoint(tip.X + (left.X * headLength), tip.Y + (left.Y * headLength)), stroke, width),
            NewLine(tip, new WpfPoint(tip.X + (right.X * headLength), tip.Y + (right.Y * headLength)), stroke, width)
        ];
    }
    private static Line NewLine(WpfPoint start, WpfPoint end, System.Windows.Media.Brush stroke, double width) => new()
    {
        X1 = start.X,
        Y1 = start.Y,
        X2 = end.X,
        Y2 = end.Y,
        Stroke = stroke,
        StrokeThickness = width,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round
    };

    private static Shape PositionShape(Shape shape, Rect rect)
    {
        Canvas.SetLeft(shape, rect.Left);
        Canvas.SetTop(shape, rect.Top);
        return shape;
    }
    private void RefreshActiveInkPreview()
    {
        if (SelectedTool != EditorTool.Eraser || activeStrokePoints.Count < 2)
        {
            RedrawInkLayer();
            return;
        }

        var style = StyleForTool(EditorTool.Eraser);
        var preview = strokes.Concat([new EditorInkStroke([.. activeStrokePoints], style.Color, style.Width, style.Alpha, style.Mode, style.ArrowHead)]);
        InkLayerImage.Source = RenderInkLayerBitmap(preview);
    }

    private void RefreshActiveArrowHead()
    {
        RemoveActiveArrowHead();
        if (SelectedTool != EditorTool.FreehandArrow || activeStrokePoints.Count < 2)
        {
            return;
        }

        var style = StyleForTool(SelectedTool);
        var previous = DenormalizePoint(activeStrokePoints[^2]);
        var tip = DenormalizePoint(activeStrokePoints[^1]);
        var dx = tip.X - previous.X;
        var dy = tip.Y - previous.Y;
        var length = Math.Max(1, Math.Sqrt((dx * dx) + (dy * dy)));
        var ux = dx / length;
        var uy = dy / length;
        var headLength = Math.Max(10, style.Width * 2.5);
        const double angle = Math.PI / 7.0;
        var left = Rotate(-ux, -uy, angle);
        var right = Rotate(-ux, -uy, -angle);
        var brush = new SolidColorBrush(WpfColor.FromArgb((byte)Math.Round(255 * style.Alpha), style.Color.R, style.Color.G, style.Color.B));
        activeArrowLines.Add(AddLine(tip, new WpfPoint(tip.X + (left.X * headLength), tip.Y + (left.Y * headLength)), style.Width, brush));
        activeArrowLines.Add(AddLine(tip, new WpfPoint(tip.X + (right.X * headLength), tip.Y + (right.Y * headLength)), style.Width, brush));
    }

    private void RemoveActiveArrowHead()
    {
        foreach (var line in activeArrowLines)
        {
            InkCanvas.Children.Remove(line);
        }

        activeArrowLines.Clear();
    }

    private Line AddLine(WpfPoint start, WpfPoint end, double width, System.Windows.Media.Brush brush)
    {
        var line = new Line
        {
            X1 = start.X,
            Y1 = start.Y,
            X2 = end.X,
            Y2 = end.Y,
            Stroke = brush,
            StrokeThickness = width,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round
        };
        InkCanvas.Children.Add(line);
        return line;
    }

    private Polyline NewDisplayPolyline(InkStyle style) => new()
    {
        Stroke = new SolidColorBrush(WpfColor.FromArgb((byte)Math.Round(255 * style.Alpha), style.Color.R, style.Color.G, style.Color.B)),
        StrokeThickness = style.Width,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round,
        StrokeLineJoin = PenLineJoin.Round
    };

    private static bool IsInkTool(EditorTool tool) =>
        tool is EditorTool.Pen or EditorTool.FreehandArrow or EditorTool.Highlighter or EditorTool.Eraser;

    private static bool IsShapeOverlayTool(EditorTool tool) =>
        tool is EditorTool.Line or EditorTool.Arrow or EditorTool.Rectangle or EditorTool.FilledRectangle or EditorTool.Ellipse or EditorTool.HighlightBox or EditorTool.Magnifier;

    private static bool IsDestructiveRectTool(EditorTool tool) =>
        tool is EditorTool.Crop or EditorTool.Blur or EditorTool.Pixelate or EditorTool.BlackRedact;

    private static bool IsImageInsertTool(EditorTool tool) => tool is EditorTool.InsertImage or EditorTool.InsertScreenImage;

    private InkStyle StyleForTool(EditorTool tool) =>
        tool switch
        {
            EditorTool.Highlighter => new InkStyle(selectedInkColor, Math.Max(2, strokeWidth), HighlighterAlpha, InkMode.Draw, ArrowHead: false),
            EditorTool.FreehandArrow => new InkStyle(selectedInkColor, strokeWidth, Alpha: 1.0, InkMode.Draw, ArrowHead: true),
            EditorTool.Eraser => new InkStyle(selectedInkColor, Math.Max(2, strokeWidth * 3.0), Alpha: 1.0, InkMode.Erase, ArrowHead: false),
            _ => new InkStyle(selectedInkColor, strokeWidth, Alpha: 1.0, InkMode.Draw, ArrowHead: false)
        };

    private bool TryNormalizePoint(WpfPoint point, out WpfPoint normalized)
    {
        normalized = default;
        if (baseImage is null || point.X < 0 || point.Y < 0 || point.X > baseImage.PixelWidth || point.Y > baseImage.PixelHeight)
        {
            return false;
        }

        normalized = new WpfPoint(point.X / baseImage.PixelWidth, point.Y / baseImage.PixelHeight);
        return true;
    }

    private WpfPoint DenormalizePoint(WpfPoint point)
    {
        if (baseImage is null)
        {
            return point;
        }

        return DenormalizePoint(point, baseImage.PixelWidth, baseImage.PixelHeight);
    }

    private static WpfPoint DenormalizePoint(WpfPoint point, double pixelWidth, double pixelHeight) =>
        new(Math.Clamp(point.X, 0, 1) * pixelWidth, Math.Clamp(point.Y, 0, 1) * pixelHeight);

    private WpfPoint NormalizePointClamped(WpfPoint point)
    {
        if (baseImage is null)
        {
            return default;
        }

        return new WpfPoint(
            Math.Clamp(point.X, 0, baseImage.PixelWidth) / baseImage.PixelWidth,
            Math.Clamp(point.Y, 0, baseImage.PixelHeight) / baseImage.PixelHeight);
    }

    private Rect OverlayBounds(EditorOverlay overlay)
    {
        var a = DenormalizePoint(overlay.A);
        var b = DenormalizePoint(overlay.B);
        var rect = RectBetween(a, b);
        return overlay.Kind switch
        {
            OverlayKind.Line or OverlayKind.Arrow => InflateRect(rect, Math.Max(6, overlay.Width), Math.Max(6, overlay.Width)),
            OverlayKind.Image => rect,
            OverlayKind.Text or OverlayKind.TextOutline or OverlayKind.TextBackground => TextRectAt(overlay, a, centered: false),
            OverlayKind.SpeechBalloon => SpeechBalloonBounds(overlay, a),
            OverlayKind.StepMarker => rect,
            OverlayKind.Sticker => TextRectAt(overlay, a, centered: true),
            OverlayKind.CursorStamp => new Rect(a.X, a.Y, Math.Max(18, overlay.FontSize), Math.Max(18, overlay.FontSize)),
            _ => rect
        };
    }

    private int? HitTestOverlays(WpfPoint point)
    {
        for (var i = overlays.Count - 1; i >= 0; i--)
        {
            var overlay = overlays[i];
            if (overlay.Kind is OverlayKind.Line or OverlayKind.Arrow)
            {
                if (DistancePointToSegment(point, DenormalizePoint(overlay.A), DenormalizePoint(overlay.B)) <= Math.Max(6, overlay.Width + 2))
                {
                    return i;
                }
            }
            else if (InflateRect(OverlayBounds(overlay), 4, 4).Contains(point))
            {
                return i;
            }
        }

        return null;
    }


    private void MoveSelectedOverlay(WpfPoint point)
    {
        if (selectedOverlayIndex is not { } index || index < 0 || index >= overlays.Count || lastPointerMovePoint is not { } last)
        {
            lastPointerMovePoint = point;
            return;
        }

        var dx = point.X - last.X;
        var dy = point.Y - last.Y;
        if (Math.Abs(dx) < double.Epsilon && Math.Abs(dy) < double.Epsilon)
        {
            return;
        }

        if (!didRequestMoveUndo && Math.Sqrt((dx * dx) + (dy * dy)) > 0.001)
        {
            didRequestMoveUndo = true;
            PushUndoSnapshot();
        }

        overlays[index] = MoveOverlay(overlays[index], dx, dy);
        lastPointerMovePoint = point;
        RedrawOverlayCanvas();
        RefreshEditorState();
    }

    private static EditorOverlay MoveOverlay(EditorOverlay overlay, double dx, double dy) =>
        overlay with
        {
            A = new WpfPoint(Math.Clamp(overlay.A.X + dx, 0, 1), Math.Clamp(overlay.A.Y + dy, 0, 1)),
            B = new WpfPoint(Math.Clamp(overlay.B.X + dx, 0, 1), Math.Clamp(overlay.B.Y + dy, 0, 1))
        };

    private void DeleteSelectedOverlay()
    {
        if (selectedOverlayIndex is not { } index || index < 0 || index >= overlays.Count)
        {
            return;
        }

        PushUndoSnapshot();
        overlays.RemoveAt(index);
        selectedOverlayIndex = null;
        RedrawOverlayCanvas();
        RefreshEditorState();
    }

    private static Rect RectBetween(WpfPoint first, WpfPoint second) =>
        new(Math.Min(first.X, second.X), Math.Min(first.Y, second.Y), Math.Abs(first.X - second.X), Math.Abs(first.Y - second.Y));

    private Rect ClampRectToImage(Rect rect)
    {
        if (baseImage is null)
        {
            return rect;
        }

        var left = Math.Clamp(rect.Left, 0, baseImage.PixelWidth);
        var top = Math.Clamp(rect.Top, 0, baseImage.PixelHeight);
        var right = Math.Clamp(rect.Right, 0, baseImage.PixelWidth);
        var bottom = Math.Clamp(rect.Bottom, 0, baseImage.PixelHeight);
        return new Rect(new WpfPoint(Math.Min(left, right), Math.Min(top, bottom)), new WpfPoint(Math.Max(left, right), Math.Max(top, bottom)));
    }

    private static Rect InflateRect(Rect rect, double horizontal, double vertical)
    {
        rect.Inflate(horizontal, vertical);
        return rect;
    }

    private static bool CircleIntersectsRect(WpfPoint center, double radius, Rect rect)
    {
        var closestX = Math.Max(rect.Left, Math.Min(center.X, rect.Right));
        var closestY = Math.Max(rect.Top, Math.Min(center.Y, rect.Bottom));
        return Distance(center, new WpfPoint(closestX, closestY)) <= radius;
    }
    private EditorSnapshot CurrentSnapshot() =>
        new(baseImage, strokes.Select(CloneStroke).ToList(), overlays.ToList(), ZoomSlider.Value, nextStepNumber);

    private static EditorInkStroke CloneStroke(EditorInkStroke stroke) =>
        stroke with { Points = stroke.Points.ToList() };

    private void PushUndoSnapshot()
    {
        undoStack.Add(CurrentSnapshot());
        if (undoStack.Count > MaxUndoDepth)
        {
            undoStack.RemoveRange(0, undoStack.Count - MaxUndoDepth);
        }

        redoStack.Clear();
        RefreshEditorState();
    }

    private void Restore(EditorSnapshot snapshot)
    {
        activeStrokePoints.Clear();
        activePolyline = null;
        activeOverlayStart = null;
        activeOverlayCurrent = null;
        lastPointerMovePoint = null;
        selectedOverlayIndex = null;
        isDrawing = false;
        isDrawingOverlay = false;
        isSmartErasing = false;
        isMovingOverlay = false;
        didRequestSmartEraserUndo = false;
        didRequestMoveUndo = false;
        EditorSurface.ReleaseMouseCapture();

        if (snapshot.BaseImage is { } snapshotImage)
        {
            SetBaseImage(snapshotImage);
        }

        strokes.Clear();
        strokes.AddRange(snapshot.Strokes.Select(CloneStroke));
        overlays.Clear();
        overlays.AddRange(snapshot.Overlays);
        ZoomSlider.Value = snapshot.ZoomValue;
        nextStepNumber = snapshot.NextStepNumber;
        RedrawInkCanvas();
        RedrawOverlayCanvas();
        RefreshEditorState();
    }

    private static double Distance(WpfPoint first, WpfPoint second)
    {
        var dx = first.X - second.X;
        var dy = first.Y - second.Y;
        return Math.Sqrt((dx * dx) + (dy * dy));
    }

    private void InkColorBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (InkColorBox?.SelectedItem is ComboBoxItem item && item.Tag is string tag)
        {
            selectedInkColor = ColorFromTag(tag);
        }
    }

    private static WpfColor ColorFromTag(string tag) => tag switch
    {
        "Yellow" => Colors.Yellow,
        "DodgerBlue" => Colors.DodgerBlue,
        "LimeGreen" => Colors.LimeGreen,
        "Black" => Colors.Black,
        "White" => Colors.White,
        _ => Colors.Red
    };
    private double MagnifierZoomForFilterStrength() =>
        Math.Clamp(filterStrength / 10.0, 1.2, 6.0);

    private void StrokeWidthSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        strokeWidth = Math.Clamp(e.NewValue, 1, 30);
        UpdateStyleText();
    }

    private void FontSizeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        fontSize = Math.Clamp(e.NewValue, 10, 72);
        UpdateStyleText();
    }

    private void FilterStrengthSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        filterStrength = Math.Clamp(e.NewValue, 2, 60);
        UpdateStyleText();
    }

    private void ResetSteps_Click(object sender, RoutedEventArgs e)
    {
        if (nextStepNumber == 1)
        {
            return;
        }

        PushUndoSnapshot();
        nextStepNumber = 1;
        RefreshEditorState();
    }

    private void SetSticker_Click(object sender, RoutedEventArgs e)
    {
        var value = PromptEditorText("Sticker", "Enter sticker text (emoji or short label).", multiLine: false, initialValue: stickerText);
        if (value is null)
        {
            return;
        }

        stickerText = value.Trim();
        RefreshEditorState();
    }
    private void RefreshEditorState()
    {
        if (UndoButton is not null)
        {
            UndoButton.IsEnabled = undoStack.Count > 0;
        }

        if (RedoButton is not null)
        {
            RedoButton.IsEnabled = redoStack.Count > 0;
        }

        var filterEnabled = SelectedTool is EditorTool.Blur or EditorTool.Pixelate or EditorTool.Magnifier;
        if (FilterStrengthSlider is not null)
        {
            FilterStrengthSlider.IsEnabled = filterEnabled;
        }

        if (EditorSurface is not null)
        {
            EditorSurface.Cursor = SelectedTool switch
            {
                EditorTool.SmartEraser => System.Windows.Input.Cursors.Cross,
                _ when IsInkTool(SelectedTool) => System.Windows.Input.Cursors.Pen,
                _ when IsShapeOverlayTool(SelectedTool) || IsDestructiveRectTool(SelectedTool) || IsImageInsertTool(SelectedTool) => System.Windows.Input.Cursors.Cross,
                _ => System.Windows.Input.Cursors.Arrow
            };
        }
    }

    private void CancelActiveInteraction()
    {
        if (!isDrawing && !isDrawingOverlay && !isSmartErasing && !isMovingOverlay)
        {
            return;
        }

        activeStrokePoints.Clear();
        activePolyline = null;
        activeOverlayStart = null;
        activeOverlayCurrent = null;
        lastPointerMovePoint = null;
        selectedOverlayIndex = null;
        isDrawing = false;
        isDrawingOverlay = false;
        isSmartErasing = false;
        isMovingOverlay = false;
        didRequestSmartEraserUndo = false;
        didRequestMoveUndo = false;
        EditorSurface.ReleaseMouseCapture();
        RedrawInkCanvas();
        RedrawOverlayCanvas();
    }

    private async void Window_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var modifiers = Keyboard.Modifiers;
        var hasControl = modifiers.HasFlag(ModifierKeys.Control);
        var hasShift = modifiers.HasFlag(ModifierKeys.Shift);

        if (hasControl && e.Key == Key.Z)
        {
            if (hasShift)
            {
                RedoAction();
            }
            else
            {
                UndoAction();
            }

            e.Handled = true;
            return;
        }

        if (hasControl && (e.Key == Key.OemPlus || e.Key == Key.Add))
        {
            ZoomSlider.Value = Math.Min(ZoomSlider.Maximum, ZoomSlider.Value + 25);
            e.Handled = true;
            return;
        }

        if (hasControl && (e.Key == Key.OemMinus || e.Key == Key.Subtract))
        {
            ZoomSlider.Value = Math.Max(ZoomSlider.Minimum, ZoomSlider.Value - 25);
            e.Handled = true;
            return;
        }

        if ((e.Key == Key.Delete || e.Key == Key.Back) && SelectedTool == EditorTool.Pointer)
        {
            DeleteSelectedOverlay();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape)
        {
            CancelActiveInteraction();
            selectedOverlayIndex = null;
            RedrawOverlayCanvas();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Return)
        {
            await SaveAndUploadAsync().ConfigureAwait(true);
            e.Handled = true;
        }
    }

    private void ZoomSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        var scale = ZoomSlider.Value / 100.0;
        ImageScale.ScaleX = scale;
        ImageScale.ScaleY = scale;
        UpdateZoomText();
    }

    private void UpdateZoomText()
    {
        if (ZoomText is not null)
        {
            ZoomText.Text = Math.Round(ZoomSlider.Value) + "%";
        }
    }

    private enum InkMode
    {
        Draw,
        Erase
    }



    private enum ImageTransform
    {
        RotateLeft,
        RotateRight,
        FlipHorizontal,
        FlipVertical
    }
    private enum PixelFilter
    {
        Blur,
        Pixelate,
        BlackRedact
    }
    private enum OverlayKind
    {
        Line,
        Arrow,
        Rectangle,
        FilledRectangle,
        Ellipse,
        HighlightBox,
        Magnifier,
        Image,
        Text,
        TextOutline,
        TextBackground,
        SpeechBalloon,
        StepMarker,
        Sticker,
        CursorStamp
    }

    private sealed class OverlayVisualHost : FrameworkElement
    {
        private readonly Visual visual;

        public OverlayVisualHost(Visual visual)
        {
            this.visual = visual;
            AddVisualChild(visual);
            AddLogicalChild(visual);
        }

        protected override int VisualChildrenCount => 1;

        protected override Visual GetVisualChild(int index) => index == 0 ? visual : throw new ArgumentOutOfRangeException(nameof(index));
    }
    private sealed record EditorInkStroke(IReadOnlyList<WpfPoint> Points, WpfColor Color, double Width, double Alpha, InkMode Mode, bool ArrowHead);

    private sealed record InkStyle(WpfColor Color, double Width, double Alpha, InkMode Mode, bool ArrowHead);

    private sealed record EditorOverlay(OverlayKind Kind, WpfPoint A, WpfPoint B, WpfColor Color, double Width, double MagnifyZoom = DefaultMagnifierZoom, string? Text = null, double FontSize = DefaultFontSize, WpfColor? FillColor = null, WpfColor? OutlineColor = null, double OutlineWidth = 0, double Padding = 0, double ImageAlpha = 1.0, BitmapSource? Image = null);

    private sealed record EditorSnapshot(BitmapSource? BaseImage, IReadOnlyList<EditorInkStroke> Strokes, IReadOnlyList<EditorOverlay> Overlays, double ZoomValue, int NextStepNumber);
}




















