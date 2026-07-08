using System.Drawing;

namespace CraftyCannon.Core;

public static class CaptureRegionGeometry
{
    public static Rectangle NormalizeDrag(Point start, Point current) =>
        Rectangle.FromLTRB(
            Math.Min(start.X, current.X),
            Math.Min(start.Y, current.Y),
            Math.Max(start.X, current.X),
            Math.Max(start.Y, current.Y));

    public static Rectangle ApplySnap(Point start, Point current, Size bounds, IReadOnlyList<CaptureSnapSize>? snapSizes, bool snapEnabled)
    {
        if (!snapEnabled || snapSizes is not { Count: > 0 })
        {
            return ClampToBounds(NormalizeDrag(start, current), bounds);
        }

        var width = Math.Abs(current.X - start.X);
        var height = Math.Abs(current.Y - start.Y);
        var best = CaptureSnapSize.NormalizeList(snapSizes)
            .OrderBy(size => Math.Abs(size.Width - width) + Math.Abs(size.Height - height))
            .FirstOrDefault();
        if (!best.IsValid)
        {
            return ClampToBounds(NormalizeDrag(start, current), bounds);
        }

        var directionX = current.X < start.X ? -1 : 1;
        var directionY = current.Y < start.Y ? -1 : 1;
        var availableWidth = directionX < 0 ? start.X : bounds.Width - start.X;
        var availableHeight = directionY < 0 ? start.Y : bounds.Height - start.Y;
        var snappedWidth = Math.Max(1, Math.Min(best.Width, availableWidth));
        var snappedHeight = Math.Max(1, Math.Min(best.Height, availableHeight));
        var end = new Point(start.X + directionX * snappedWidth, start.Y + directionY * snappedHeight);
        return ClampToBounds(NormalizeDrag(start, end), bounds);
    }

    public static Rectangle ClampToBounds(Rectangle value, Size bounds)
    {
        var left = Math.Clamp(value.Left, 0, Math.Max(0, bounds.Width));
        var top = Math.Clamp(value.Top, 0, Math.Max(0, bounds.Height));
        var right = Math.Clamp(value.Right, left, Math.Max(left, bounds.Width));
        var bottom = Math.Clamp(value.Bottom, top, Math.Max(top, bounds.Height));
        return Rectangle.FromLTRB(left, top, right, bottom);
    }
}