using CraftyCannon.Core;

namespace CraftyCannon.Ocr;

public static class RedactionImageRenderer
{
    public static int ApplyToBgra32(
        byte[] pixels,
        int width,
        int height,
        IReadOnlyList<RedactionFinding> findings,
        SmartRedactionRenderMode mode,
        int pixelateBlockSize = 14)
    {
        if (width <= 0 || height <= 0 || pixels.Length < width * height * 4 || findings.Count == 0)
        {
            return 0;
        }

        var applied = 0;
        foreach (var finding in findings)
        {
            var bounds = PixelBounds(finding, width, height);
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                continue;
            }

            if (mode == SmartRedactionRenderMode.BlackBox)
            {
                FillBlack(pixels, width, height, bounds);
            }
            else
            {
                PixelateRegion(pixels, width, height, bounds, Math.Max(2, pixelateBlockSize));
            }

            applied++;
        }

        return applied;
    }

    public static PixelBounds PixelBounds(RedactionFinding finding, int imageWidth, int imageHeight)
    {
        var left = Math.Clamp((int)Math.Floor(finding.X * imageWidth), 0, imageWidth);
        var top = Math.Clamp((int)Math.Floor(finding.Y * imageHeight), 0, imageHeight);
        var right = Math.Clamp((int)Math.Ceiling((finding.X + finding.Width) * imageWidth), 0, imageWidth);
        var bottom = Math.Clamp((int)Math.Ceiling((finding.Y + finding.Height) * imageHeight), 0, imageHeight);
        return new PixelBounds(left, top, Math.Max(0, right - left), Math.Max(0, bottom - top));
    }

    private static void FillBlack(byte[] pixels, int width, int height, PixelBounds bounds)
    {
        var right = Math.Min(width, bounds.X + bounds.Width);
        var bottom = Math.Min(height, bounds.Y + bounds.Height);
        for (var y = bounds.Y; y < bottom; y++)
        {
            var offset = (y * width + bounds.X) * 4;
            for (var x = bounds.X; x < right; x++)
            {
                pixels[offset] = 0;
                pixels[offset + 1] = 0;
                pixels[offset + 2] = 0;
                pixels[offset + 3] = 255;
                offset += 4;
            }
        }
    }

    private static void PixelateRegion(byte[] pixels, int width, int height, PixelBounds bounds, int blockSize)
    {
        var right = Math.Min(width, bounds.X + bounds.Width);
        var bottom = Math.Min(height, bounds.Y + bounds.Height);
        for (var y = bounds.Y; y < bottom; y += blockSize)
        {
            for (var x = bounds.X; x < right; x += blockSize)
            {
                var blockRight = Math.Min(right, x + blockSize);
                var blockBottom = Math.Min(bottom, y + blockSize);
                var b = 0;
                var g = 0;
                var r = 0;
                var a = 0;
                var count = 0;
                for (var py = y; py < blockBottom; py++)
                {
                    var offset = (py * width + x) * 4;
                    for (var px = x; px < blockRight; px++)
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

                FillRegion(pixels, width, height, new PixelBounds(x, y, blockRight - x, blockBottom - y), (byte)(b / count), (byte)(g / count), (byte)(r / count), (byte)(a / count));
            }
        }
    }

    private static void FillRegion(byte[] pixels, int width, int height, PixelBounds bounds, byte b, byte g, byte r, byte a)
    {
        var right = Math.Min(width, bounds.X + bounds.Width);
        var bottom = Math.Min(height, bounds.Y + bounds.Height);
        for (var y = bounds.Y; y < bottom; y++)
        {
            var offset = (y * width + bounds.X) * 4;
            for (var x = bounds.X; x < right; x++)
            {
                pixels[offset] = b;
                pixels[offset + 1] = g;
                pixels[offset + 2] = r;
                pixels[offset + 3] = a;
                offset += 4;
            }
        }
    }
}

public readonly record struct PixelBounds(int X, int Y, int Width, int Height);
