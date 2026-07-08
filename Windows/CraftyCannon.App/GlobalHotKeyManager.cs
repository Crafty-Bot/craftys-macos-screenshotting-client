using System.Runtime.InteropServices;
using System.Windows.Interop;
using CraftyCannon.Core;

namespace CraftyCannon.App;

public sealed class GlobalHotKeyManager : IDisposable
{
    private const int WmHotKey = 0x0312;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModWin = 0x0008;
    private const uint ModNoRepeat = 0x4000;

    private readonly HwndSource source;
    private readonly Dictionary<int, GlobalHotKeyAction> registered = new();

    public GlobalHotKeyManager(Action<GlobalHotKeyAction> onAction)
    {
        source = new HwndSource(new HwndSourceParameters("CraftyCannonHotKeys")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0x800000
        });
        source.AddHook((nint hwnd, int msg, nint wParam, nint lParam, ref bool handled) =>
        {
            if (msg == WmHotKey && registered.TryGetValue(wParam.ToInt32(), out var action))
            {
                handled = true;
                onAction(action);
            }

            return nint.Zero;
        });
    }

    public void ApplyBindings(HotKeyBindings bindings)
    {
        Clear();
        var normalized = bindings.Normalized;
        Register(GlobalHotKeyAction.CaptureRegionUpload, normalized.CaptureRegionUpload);
        Register(GlobalHotKeyAction.CaptureRegionUploadExpiring, normalized.CaptureRegionUploadExpiring);
        Register(GlobalHotKeyAction.CaptureRegionUploadFrozen, normalized.CaptureRegionUploadFrozen);
        Register(GlobalHotKeyAction.UploadClipboard, normalized.UploadClipboard);
    }

    public void Dispose()
    {
        Clear();
        source.Dispose();
    }

    private void Register(GlobalHotKeyAction action, HotKeyShortcut shortcut)
    {
        var normalized = shortcut.Normalized;
        if (!TryVirtualKey(normalized.Key, out var virtualKey))
        {
            return;
        }

        var id = (int)action + 1;
        var modifiers = ModNoRepeat;
        if (normalized.Control) modifiers |= ModControl;
        if (normalized.Shift) modifiers |= ModShift;
        if (normalized.Alt) modifiers |= ModAlt;
        if (normalized.Windows) modifiers |= ModWin;

        if (RegisterHotKey(source.Handle, id, modifiers, virtualKey))
        {
            registered[id] = action;
        }
    }

    private void Clear()
    {
        foreach (var id in registered.Keys.ToArray())
        {
            UnregisterHotKey(source.Handle, id);
        }

        registered.Clear();
    }

    private static bool TryVirtualKey(string key, out uint virtualKey)
    {
        virtualKey = 0;
        if (string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        var c = char.ToUpperInvariant(key[0]);
        if (c is >= 'A' and <= 'Z' or >= '0' and <= '9')
        {
            virtualKey = c;
            return true;
        }

        return false;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(nint hWnd, int id);
}