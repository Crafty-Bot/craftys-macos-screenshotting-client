namespace CraftyCannon.Ocr;

public readonly record struct BarcodePoint(double X, double Y);

public static class BarcodeRedactionGeometry
{
    public static RedactionFinding FindingFromPoints(
        string preview,
        int imageWidth,
        int imageHeight,
        IReadOnlyList<BarcodePoint> points,
        double confidence = 1.0)
    {
        if (imageWidth <= 0 || imageHeight <= 0 || points.Count == 0)
        {
            return new RedactionFinding(RedactionDetectorType.Barcode, confidence, 0, 0, 1, 1, string.Empty);
        }

        var minX = points.Min(point => point.X);
        var maxX = points.Max(point => point.X);
        var minY = points.Min(point => point.Y);
        var maxY = points.Max(point => point.Y);
        var padX = Math.Max(2.0, (maxX - minX) * 0.08);
        var padY = Math.Max(2.0, (maxY - minY) * 0.08);
        var left = Math.Clamp((minX - padX) / imageWidth, 0, 1);
        var top = Math.Clamp((minY - padY) / imageHeight, 0, 1);
        var right = Math.Clamp((maxX + padX) / imageWidth, 0, 1);
        var bottom = Math.Clamp((maxY + padY) / imageHeight, 0, 1);
        return new RedactionFinding(
            RedactionDetectorType.Barcode,
            Math.Clamp(confidence, 0, 1),
            left,
            top,
            Math.Max(0, right - left),
            Math.Max(0, bottom - top),
            string.Empty);
    }
}