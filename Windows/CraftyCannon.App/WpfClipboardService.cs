using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Media.Imaging;
using CraftyCannon.Core;
using WpfClipboard = System.Windows.Clipboard;
using WpfTextDataFormat = System.Windows.TextDataFormat;

namespace CraftyCannon.App;

public sealed class WpfClipboardService(AppStoragePaths paths) : IClipboardService
{
    public ClipboardSnapshot ReadSnapshot() => OnUiThread(ReadSnapshotCore);

    public bool TrySetText(string text) => OnUiThread(() => TrySetTextCore(text));

    public bool TrySetImage(string imagePath) => OnUiThread(() => TrySetImageCore(imagePath));

    private ClipboardSnapshot ReadSnapshotCore()
    {
        EnsureStaThread();

        if (WpfClipboard.ContainsImage())
        {
            return new ClipboardSnapshot(true, TryMaterializeImage(), [], null);
        }

        if (WpfClipboard.ContainsFileDropList())
        {
            var files = WpfClipboard.GetFileDropList()
                .Cast<string>()
                .Where(path => !string.IsNullOrWhiteSpace(path))
                .Select(path => new ClipboardFileItem(path, Directory.Exists(path)))
                .ToArray();

            if (files.Length > 0)
            {
                return new ClipboardSnapshot(false, null, files, null);
            }
        }

        var text = WpfClipboard.ContainsText(WpfTextDataFormat.UnicodeText)
            ? WpfClipboard.GetText(WpfTextDataFormat.UnicodeText)
            : null;
        return new ClipboardSnapshot(false, null, [], text);
    }

    private bool TrySetTextCore(string text)
    {
        EnsureStaThread();
        try
        {
            WpfClipboard.SetText(text, WpfTextDataFormat.UnicodeText);
            return true;
        }
        catch (ExternalException)
        {
            return false;
        }
    }

    private bool TrySetImageCore(string imagePath)
    {
        EnsureStaThread();
        if (!File.Exists(imagePath))
        {
            return false;
        }

        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new System.Uri(Path.GetFullPath(imagePath), System.UriKind.Absolute);
            image.EndInit();
            image.Freeze();
            WpfClipboard.SetImage(image);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (ExternalException)
        {
            return false;
        }
    }

    private string? TryMaterializeImage()
    {
        try
        {
            var image = WpfClipboard.GetImage();
            if (image is null)
            {
                return null;
            }

            paths.EnsureCreated();
            var filePath = Path.Combine(paths.TempRoot, $"clipboard-{DateTimeOffset.UtcNow:yyyyMMddHHmmssfff}-{Guid.NewGuid():N}.png");
            using var stream = File.Create(filePath);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            encoder.Save(stream);
            return filePath;
        }
        catch (IOException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
        catch (ExternalException)
        {
            return null;
        }
    }

    private static T OnUiThread<T>(Func<T> action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            return dispatcher.Invoke(action);
        }

        return action();
    }

    private static void EnsureStaThread()
    {
        if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
        {
            throw new InvalidOperationException("Windows clipboard access must run on the WPF STA thread.");
        }
    }
}

