using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace CraftyCannon.Capture;

internal sealed class WindowSelectionOverlay : Form
{
    private readonly Rectangle virtualBounds;
    private readonly IReadOnlyList<CandidateWindow> windows;
    private readonly Bitmap? background;
    private int selectedIndex = -1;

    private WindowSelectionOverlay(Rectangle virtualBounds, IReadOnlyList<CandidateWindow> windows, Bitmap? background)
    {
        this.virtualBounds = virtualBounds;
        this.windows = windows;
        this.background = background;
        Bounds = virtualBounds;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;
        KeyPreview = true;
        Cursor = Cursors.Hand;
        BackColor = Color.Black;
    }

    public static ScreenRect? Select(Rectangle virtualBounds, Bitmap? background = null)
    {
        var windows = EnumerateCandidateWindows(virtualBounds);
        if (windows.Count == 0)
        {
            return null;
        }

        using var overlay = new WindowSelectionOverlay(virtualBounds, windows, background);
        return overlay.ShowDialog() == DialogResult.OK && overlay.SelectedWindow is { } selected
            ? new ScreenRect(selected.Bounds.X, selected.Bounds.Y, selected.Bounds.Width, selected.Bounds.Height)
            : null;
    }

    private CandidateWindow? SelectedWindow =>
        selectedIndex >= 0 && selectedIndex < windows.Count ? windows[selectedIndex] : null;

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Activate();
        Focus();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (background is not null)
        {
            e.Graphics.DrawImage(background, ClientRectangle);
        }

        using var overlayBrush = new SolidBrush(Color.FromArgb(120, Color.Black));
        e.Graphics.FillRectangle(overlayBrush, ClientRectangle);

        for (var i = windows.Count - 1; i >= 0; i--)
        {
            DrawCandidate(e.Graphics, i, i == selectedIndex);
        }

        DrawPrompt(e.Graphics);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var previous = selectedIndex;
        selectedIndex = HitTest(e.Location);
        if (previous != selectedIndex)
        {
            Invalidate();
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Right)
        {
            Cancel();
        }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left)
        {
            return;
        }

        selectedIndex = HitTest(e.Location);
        if (SelectedWindow is null)
        {
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
    }

    private void Cancel()
    {
        DialogResult = DialogResult.Cancel;
        Close();
    }

    private int HitTest(Point clientPoint)
    {
        var screenPoint = new Point(clientPoint.X + virtualBounds.X, clientPoint.Y + virtualBounds.Y);
        for (var i = 0; i < windows.Count; i++)
        {
            if (windows[i].Bounds.Contains(screenPoint))
            {
                return i;
            }
        }

        return -1;
    }

    private void DrawCandidate(Graphics graphics, int index, bool selected)
    {
        var candidate = windows[index];
        var rect = ToClientRect(candidate.Bounds);
        if (rect.Width <= 0 || rect.Height <= 0)
        {
            return;
        }

        if (selected && background is not null)
        {
            graphics.DrawImage(background, rect, rect, GraphicsUnit.Pixel);
        }
        else if (selected)
        {
            using var fill = new SolidBrush(Color.FromArgb(80, Color.White));
            graphics.FillRectangle(fill, rect);
        }

        using var pen = new Pen(selected ? Color.FromArgb(255, 66, 153, 225) : Color.FromArgb(180, 215, 220, 226), selected ? 3 : 1);
        graphics.DrawRectangle(pen, rect);
        if (selected)
        {
            DrawWindowLabel(graphics, rect, candidate.Title);
        }
    }

    private void DrawPrompt(Graphics graphics)
    {
        const string text = "Click a window to capture. Press Esc to cancel.";
        using var font = new Font(FontFamily.GenericSansSerif, 14, FontStyle.Bold);
        var size = graphics.MeasureString(text, font);
        var x = Math.Max(16, (ClientSize.Width - size.Width) / 2);
        var y = Math.Max(16, ClientSize.Height - size.Height - 32);
        using var backgroundBrush = new SolidBrush(Color.FromArgb(220, 32, 36, 43));
        using var foreground = new SolidBrush(Color.White);
        graphics.FillRectangle(backgroundBrush, x - 12, y - 8, size.Width + 24, size.Height + 16);
        graphics.DrawString(text, font, foreground, x, y);
    }

    private static void DrawWindowLabel(Graphics graphics, Rectangle rect, string title)
    {
        var text = string.IsNullOrWhiteSpace(title) ? "Window" : title;
        using var font = new Font(FontFamily.GenericSansSerif, 10, FontStyle.Bold);
        var size = graphics.MeasureString(text, font);
        var labelWidth = Math.Min(rect.Width, (int)Math.Ceiling(size.Width + 12));
        var label = new RectangleF(rect.Left, Math.Max(0, rect.Top - size.Height - 8), labelWidth, size.Height + 6);
        using var backgroundBrush = new SolidBrush(Color.FromArgb(230, 32, 36, 43));
        using var foreground = new SolidBrush(Color.White);
        graphics.FillRectangle(backgroundBrush, label);
        graphics.DrawString(text, font, foreground, label.Left + 6, label.Top + 3);
    }

    private Rectangle ToClientRect(Rectangle screenRect) =>
        new(screenRect.X - virtualBounds.X, screenRect.Y - virtualBounds.Y, screenRect.Width, screenRect.Height);

    private static IReadOnlyList<CandidateWindow> EnumerateCandidateWindows(Rectangle virtualBounds)
    {
        var result = new List<CandidateWindow>();
        var currentProcessId = Environment.ProcessId;
        EnumWindows((hwnd, _) =>
        {
            if (!IsCandidateWindow(hwnd, currentProcessId, virtualBounds, out var candidate))
            {
                return true;
            }

            result.Add(candidate);
            return true;
        }, nint.Zero);
        return result;
    }

    private static bool IsCandidateWindow(nint hwnd, int currentProcessId, Rectangle virtualBounds, out CandidateWindow candidate)
    {
        candidate = default;
        if (hwnd == nint.Zero || !IsWindowVisible(hwnd) || IsIconic(hwnd))
        {
            return false;
        }

        GetWindowThreadProcessId(hwnd, out var processId);
        if (processId == currentProcessId)
        {
            return false;
        }

        var className = WindowClassName(hwnd);
        if (IgnoredWindowClasses.Contains(className) || className.StartsWith("tooltips_class", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var exStyle = GetWindowLongPtr(hwnd, GwlExStyle).ToInt64();
        if ((exStyle & WsExToolWindow) != 0)
        {
            return false;
        }

        if (DwmGetWindowAttributeInt(hwnd, DwmwaCloaked, out var cloaked, Marshal.SizeOf<int>()) == 0 && cloaked != 0)
        {
            return false;
        }

        if (!TryGetWindowBounds(hwnd, out var bounds))
        {
            return false;
        }

        if (bounds.Width < 32 || bounds.Height < 32 || !bounds.IntersectsWith(virtualBounds))
        {
            return false;
        }

        var title = WindowTitle(hwnd);
        if (string.IsNullOrWhiteSpace(title))
        {
            return false;
        }

        candidate = new CandidateWindow(hwnd, bounds, title);
        return true;
    }

    private static bool TryGetWindowBounds(nint hwnd, out Rectangle bounds)
    {
        if (DwmGetWindowAttributeRect(hwnd, DwmwaExtendedFrameBounds, out var dwmRect, Marshal.SizeOf<NativeRect>()) == 0)
        {
            bounds = Rectangle.FromLTRB(dwmRect.Left, dwmRect.Top, dwmRect.Right, dwmRect.Bottom);
            if (bounds.Width > 0 && bounds.Height > 0)
            {
                return true;
            }
        }

        if (GetWindowRect(hwnd, out var nativeRect))
        {
            bounds = Rectangle.FromLTRB(nativeRect.Left, nativeRect.Top, nativeRect.Right, nativeRect.Bottom);
            return bounds.Width > 0 && bounds.Height > 0;
        }

        bounds = Rectangle.Empty;
        return false;
    }

    private static string WindowTitle(nint hwnd)
    {
        var length = GetWindowTextLength(hwnd);
        if (length <= 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(length + 1);
        _ = GetWindowText(hwnd, builder, builder.Capacity);
        return builder.ToString().Trim();
    }

    private static string WindowClassName(nint hwnd)
    {
        var builder = new StringBuilder(256);
        _ = GetClassName(hwnd, builder, builder.Capacity);
        return builder.ToString();
    }

    private readonly record struct CandidateWindow(nint Hwnd, Rectangle Bounds, string Title);

    private static readonly HashSet<string> IgnoredWindowClasses = new(StringComparer.Ordinal)
    {
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "DV2ControlHost",
        "MsgrIMEWindowClass"
    };

    private const int GwlExStyle = -20;
    private const long WsExToolWindow = 0x00000080L;
    private const int DwmwaExtendedFrameBounds = 9;
    private const int DwmwaCloaked = 14;

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, nint lParam);

    private delegate bool EnumWindowsProc(nint hWnd, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(nint hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(nint hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(nint hWnd, out NativeRect lpRect);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(nint hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hWnd, out int lpdwProcessId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint hWnd, int nIndex);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int DwmGetWindowAttributeRect(nint hwnd, int dwAttribute, out NativeRect pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
    private static extern int DwmGetWindowAttributeInt(nint hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativeRect
    {
        public readonly int Left;
        public readonly int Top;
        public readonly int Right;
        public readonly int Bottom;
    }
}
