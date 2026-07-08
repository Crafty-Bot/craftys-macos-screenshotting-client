namespace CraftyCannon.Core;

public sealed record WindowsPortSection(string Name, IReadOnlyList<string> Items);

public static class WindowsPortSections
{
    public static IReadOnlyList<WindowsPortSection> Default { get; } =
    [
        new("Capture",
        [
            "Region",
            "Frozen region",
            "Window",
            "Full screen",
            "Top taskbar",
            "Fixed region",
            "Screen recording"
        ]),
        new("Upload",
        [
            "Clipboard image/file/folder/URL/text",
            "File picker",
            "Folder picker",
            "URL entry",
            "Text upload",
            "Expiring uploads"
        ]),
        new("Workflows",
        [
            "Capture, edit, upload",
            "Capture, redact, upload",
            "Upload, mirror, shorten"
        ]),
        new("Tools",
        [
            "Color picker",
            "QR code",
            "Hash checker",
            "Directory indexer",
            "Pin clipboard image",
            "Pin image file"
        ]),
        new("After capture tasks",
        [
            "Open editor",
            "Keep local copy",
            "Mirror to screenshots folder"
        ]),
        new("After upload tasks",
        [
            "Copy URL",
            "Copy image",
            "Open URL",
            "Discord paste-target override"
        ]),
        new("Destinations",
        [
            "Zipline v4",
            "S3-compatible",
            "Secondary S3 mirror",
            "Extension routing",
            "Content-kind routing"
        ]),
        new("Settings",
        [
            "Hotkeys",
            "Clipboard rules",
            "File naming",
            "Themes",
            "Cloudflare allowlist",
            "Smart redaction",
            "OCR indexing",
            "Watch folders"
        ]),
        new("History",
        [
            "Search",
            "OCR text search",
            "Copy/open/shorten URL",
            "Reveal local file",
            "Reupload",
            "Edit",
            "Delete managed local copy"
        ])
    ];
}


