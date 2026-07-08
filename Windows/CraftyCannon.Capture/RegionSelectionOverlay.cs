using System.Drawing;
using System.Windows.Forms;
using CraftyCannon.Core;

namespace CraftyCannon.Capture;

internal sealed class RegionSelectionOverlay : Form
{
    private readonly Rectangle virtualBounds;
    private readonly Bitmap? frozenBackground;
    private readonly bool showOverlayInfo;
    private readonly IReadOnlyList<CaptureSnapSize> snapSizes;
    private Point dragStart;
    private Point pointer;
    private Rectangle selection;
    private bool dragging;
    private bool snappedSelection;

    private RegionSelectionOverlay(Rectangle virtualBounds, Bitmap? frozenBackground, bool showOverlayInfo, IReadOnlyList<CaptureSnapSize>? snapSizes)
    {
        this.virtualBounds = virtualBounds;
        this.frozenBackground = frozenBackground;
        this.showOverlayInfo = showOverlayInfo;
        this.snapSizes = CaptureSnapSize.NormalizeList(snapSizes);
        Bounds = virtualBounds;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;
        KeyPreview = true;
        Cursor = Cursors.Cross;
        BackColor = Color.Black;
    }

    public static ScreenRect? Select(Rectangle virtualBounds, Bitmap? frozenBackground = null, bool showOverlayInfo = true, IReadOnlyList<CaptureSnapSize>? snapSizes = null)
    {
        using var overlay = new RegionSelectionOverlay(virtualBounds, frozenBackground, showOverlayInfo, snapSizes);
        if (overlay.ShowDialog() != DialogResult.OK)
        {
            return null;
        }

        var bounds = overlay.virtualBounds;
        var selected = overlay.selection;
        return new ScreenRect(
            bounds.X + selected.X,
            bounds.Y + selected.Y,
            selected.Width,
            selected.Height);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Activate();
        Focus();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (frozenBackground is not null)
        {
            e.Graphics.DrawImage(frozenBackground, ClientRectangle);
        }

        using var overlayBrush = new SolidBrush(Color.FromArgb(110, Color.Black));
        e.Graphics.FillRectangle(overlayBrush, ClientRectangle);

        if (selection.Width <= 0 || selection.Height <= 0)
        {
            DrawPrompt(e.Graphics);
            return;
        }

        if (frozenBackground is not null)
        {
            e.Graphics.DrawImage(frozenBackground, selection, selection, GraphicsUnit.Pixel);
        }
        else
        {
            using var clearBrush = new SolidBrush(Color.FromArgb(95, Color.White));
            e.Graphics.FillRectangle(clearBrush, selection);
        }

        using var borderPen = new Pen(Color.FromArgb(255, 66, 153, 225), 2);
        e.Graphics.DrawRectangle(borderPen, selection);
        DrawCrosshairGuides(e.Graphics);
        if (showOverlayInfo)
        {
            DrawDimensions(e.Graphics);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Right)
        {
            Cancel();
            return;
        }

        if (e.Button != MouseButtons.Left)
        {
            return;
        }

        dragging = true;
        dragStart = e.Location;
        pointer = e.Location;
        selection = Rectangle.Empty;
        snappedSelection = false;
        Invalidate();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        pointer = e.Location;
        if (dragging)
        {
            UpdateSelection(e.Location);
        }

        Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (!dragging || e.Button != MouseButtons.Left)
        {
            return;
        }

        dragging = false;
        UpdateSelection(e.Location);
        if (selection.Width < 3 || selection.Height < 3)
        {
            selection = Rectangle.Empty;
            Invalidate();
            return;
        }

        DialogResult = DialogResult.OK;
        Close();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.KeyCode == Keys.Escape)
        {
            Cancel();
        }
        else if (dragging && e.KeyCode == Keys.ShiftKey)
        {
            UpdateSelection(pointer);
            Invalidate();
        }
    }

    protected override void OnKeyUp(KeyEventArgs e)
    {
        base.OnKeyUp(e);
        if (dragging && e.KeyCode == Keys.ShiftKey)
        {
            UpdateSelection(pointer);
            Invalidate();
        }
    }

    private void Cancel()
    {
        DialogResult = DialogResult.Cancel;
        Close();
    }

    private void DrawPrompt(Graphics graphics)
    {
        var text = snapSizes.Count > 0
            ? "Drag to capture a region. Hold Shift for snap sizes. Press Esc to cancel."
            : "Drag to capture a region. Press Esc to cancel.";
        using var font = new Font(FontFamily.GenericSansSerif, 14, FontStyle.Bold);
        var size = graphics.MeasureString(text, font);
        var x = Math.Max(16, (ClientSize.Width - size.Width) / 2);
        var y = Math.Max(16, (ClientSize.Height - size.Height) / 2);
        using var shadow = new SolidBrush(Color.FromArgb(180, Color.Black));
        using var foreground = new SolidBrush(Color.White);
        graphics.DrawString(text, font, shadow, x + 1, y + 1);
        graphics.DrawString(text, font, foreground, x, y);
    }

    private void DrawDimensions(Graphics graphics)
    {
        var text = snappedSelection ? $"{selection.Width} x {selection.Height} snap" : $"{selection.Width} x {selection.Height}";
        using var font = new Font(FontFamily.GenericSansSerif, 10, FontStyle.Bold);
        var size = graphics.MeasureString(text, font);
        var label = new RectangleF(selection.Left, Math.Max(0, selection.Top - size.Height - 8), size.Width + 12, size.Height + 6);
        using var background = new SolidBrush(Color.FromArgb(220, 32, 36, 43));
        using var foreground = new SolidBrush(Color.White);
        graphics.FillRectangle(background, label);
        graphics.DrawString(text, font, foreground, label.Left + 6, label.Top + 3);
    }

    private void DrawCrosshairGuides(Graphics graphics)
    {
        if (!dragging)
        {
            return;
        }

        using var pen = new Pen(Color.FromArgb(100, 255, 255, 255), 1);
        graphics.DrawLine(pen, pointer.X, 0, pointer.X, ClientSize.Height);
        graphics.DrawLine(pen, 0, pointer.Y, ClientSize.Width, pointer.Y);
    }

    private void UpdateSelection(Point current)
    {
        pointer = current;
        snappedSelection = snapSizes.Count > 0 && (ModifierKeys & Keys.Shift) == Keys.Shift;
        selection = CaptureRegionGeometry.ApplySnap(
            dragStart,
            current,
            ClientSize,
            snapSizes,
            snappedSelection);
    }
}