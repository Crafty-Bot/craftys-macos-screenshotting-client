using System.Globalization;
using System.Text.Json.Serialization;

namespace CraftyCannon.Core;

public sealed record RgbaColor(double Red, double Green, double Blue, double Alpha = 1.0)
{
    public static RgbaColor Rgb255(int red, int green, int blue, double alpha = 1.0) =>
        new(red / 255.0, green / 255.0, blue / 255.0, alpha);

    [JsonIgnore]
    public RgbaColor Normalized => new(
        ClampColor(Red),
        ClampColor(Green),
        ClampColor(Blue),
        ClampColor(double.IsNaN(Alpha) ? 1.0 : Alpha));

    public string ToHexRgba()
    {
        var color = Normalized;
        return string.Create(CultureInfo.InvariantCulture, $"#{ToByte(color.Red):X2}{ToByte(color.Green):X2}{ToByte(color.Blue):X2}{ToByte(color.Alpha):X2}");
    }

    public static bool TryParseHex(string? value, out RgbaColor color)
    {
        color = Rgb255(0, 0, 0);
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var text = value.Trim();
        if (text.StartsWith('#'))
        {
            text = text[1..];
        }

        if (text.Length is not (6 or 8) || !int.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var packed))
        {
            return false;
        }

        var red = text.Length == 6 ? (packed >> 16) & 0xFF : (packed >> 24) & 0xFF;
        var green = text.Length == 6 ? (packed >> 8) & 0xFF : (packed >> 16) & 0xFF;
        var blue = text.Length == 6 ? packed & 0xFF : (packed >> 8) & 0xFF;
        var alpha = text.Length == 6 ? 0xFF : packed & 0xFF;
        color = Rgb255(red, green, blue, alpha / 255.0).Normalized;
        return true;
    }

    private static double ClampColor(double value) => Math.Clamp(double.IsNaN(value) ? 0 : value, 0, 1);

    private static int ToByte(double value) => (int)Math.Round(Math.Clamp(value, 0, 1) * 255, MidpointRounding.AwayFromZero);
}

public sealed record UiPaletteData(
    RgbaColor WindowGradientA,
    RgbaColor WindowGradientB,
    RgbaColor WindowGradientC,
    RgbaColor WindowRadialSpot,
    RgbaColor RailPanelAccent,
    RgbaColor ContextPanelAccent,
    RgbaColor CaptureAccent,
    RgbaColor UploadAccent,
    RgbaColor WorkflowsAccent,
    RgbaColor ToolsAccent,
    RgbaColor AfterCaptureAccent,
    RgbaColor AfterUploadAccent,
    RgbaColor DestinationsAccent,
    RgbaColor SettingsAccent,
    RgbaColor HistoryAccent)
{
    public UiPaletteData Normalized(UiPaletteData? fallback = null)
    {
        var seed = fallback ?? UiPaletteCatalog.DefaultCustomSeed();
        return new UiPaletteData(
            NormalizeColor(WindowGradientA, seed.WindowGradientA),
            NormalizeColor(WindowGradientB, seed.WindowGradientB),
            NormalizeColor(WindowGradientC, seed.WindowGradientC),
            NormalizeColor(WindowRadialSpot, seed.WindowRadialSpot),
            NormalizeColor(RailPanelAccent, seed.RailPanelAccent),
            NormalizeColor(ContextPanelAccent, seed.ContextPanelAccent),
            NormalizeColor(CaptureAccent, seed.CaptureAccent),
            NormalizeColor(UploadAccent, seed.UploadAccent),
            NormalizeColor(WorkflowsAccent, seed.WorkflowsAccent),
            NormalizeColor(ToolsAccent, seed.ToolsAccent),
            NormalizeColor(AfterCaptureAccent, seed.AfterCaptureAccent),
            NormalizeColor(AfterUploadAccent, seed.AfterUploadAccent),
            NormalizeColor(DestinationsAccent, seed.DestinationsAccent),
            NormalizeColor(SettingsAccent, seed.SettingsAccent),
            NormalizeColor(HistoryAccent, seed.HistoryAccent));
    }

    private static RgbaColor NormalizeColor(RgbaColor? value, RgbaColor fallback) => (value ?? fallback).Normalized;
}

public sealed record UiPalette(string Id, string DisplayName, UiPaletteData Data);

public static class UiPaletteCatalog
{
    public const string ClassicId = "classic";
    public const string CustomId = "custom";

    public static IReadOnlyList<UiPalette> Presets =>
    [
        new(ClassicId, "Classic", Classic),
        new("nord", "Nord", Nord),
        new("gruvbox", "Gruvbox", Gruvbox),
        new("mono", "Mono", Mono),
        new("megaDark", "Mega Dark", MegaDark),
        new("oledBlack", "OLED Black", OledBlack),
        new("rainbow", "Rainbow", Rainbow)
    ];

    public static UiPaletteData DefaultCustomSeed() => Classic;

    public static string NormalizeId(string? selected)
    {
        if (string.Equals(selected, CustomId, StringComparison.OrdinalIgnoreCase))
        {
            return CustomId;
        }

        return Presets.Any(preset => string.Equals(preset.Id, selected, StringComparison.OrdinalIgnoreCase))
            ? Presets.First(preset => string.Equals(preset.Id, selected, StringComparison.OrdinalIgnoreCase)).Id
            : ClassicId;
    }

    public static UiPalette Resolve(string? selected, UiPaletteData? custom)
    {
        var id = NormalizeId(selected);
        if (id == CustomId)
        {
            return new UiPalette(CustomId, "Custom", (custom ?? DefaultCustomSeed()).Normalized(DefaultCustomSeed()));
        }

        return Presets.FirstOrDefault(preset => string.Equals(preset.Id, id, StringComparison.OrdinalIgnoreCase)) ?? Presets[0];
    }

    private static readonly UiPaletteData Classic = new(
        RgbaColor.Rgb255(26, 115, 242),
        RgbaColor.Rgb255(64, 217, 179),
        RgbaColor.Rgb255(250, 199, 56),
        RgbaColor.Rgb255(242, 77, 89),
        RgbaColor.Rgb255(26, 115, 242),
        RgbaColor.Rgb255(64, 217, 179),
        RgbaColor.Rgb255(242, 140, 51),
        RgbaColor.Rgb255(38, 179, 217),
        RgbaColor.Rgb255(64, 199, 115),
        RgbaColor.Rgb255(242, 77, 89),
        RgbaColor.Rgb255(250, 199, 56),
        RgbaColor.Rgb255(89, 217, 179),
        RgbaColor.Rgb255(64, 166, 140),
        RgbaColor.Rgb255(140, 153, 179),
        RgbaColor.Rgb255(64, 115, 242));

    private static readonly UiPaletteData Nord = new(
        RgbaColor.Rgb255(46, 52, 64), RgbaColor.Rgb255(94, 129, 172), RgbaColor.Rgb255(163, 190, 140), RgbaColor.Rgb255(191, 97, 106), RgbaColor.Rgb255(94, 129, 172), RgbaColor.Rgb255(136, 192, 208), RgbaColor.Rgb255(208, 135, 112), RgbaColor.Rgb255(136, 192, 208), RgbaColor.Rgb255(163, 190, 140), RgbaColor.Rgb255(191, 97, 106), RgbaColor.Rgb255(235, 203, 139), RgbaColor.Rgb255(143, 188, 187), RgbaColor.Rgb255(129, 161, 193), RgbaColor.Rgb255(229, 233, 240), RgbaColor.Rgb255(94, 129, 172));

    private static readonly UiPaletteData Gruvbox = new(
        RgbaColor.Rgb255(251, 73, 52), RgbaColor.Rgb255(184, 187, 38), RgbaColor.Rgb255(250, 189, 47), RgbaColor.Rgb255(211, 134, 155), RgbaColor.Rgb255(250, 189, 47), RgbaColor.Rgb255(131, 165, 152), RgbaColor.Rgb255(251, 73, 52), RgbaColor.Rgb255(131, 165, 152), RgbaColor.Rgb255(184, 187, 38), RgbaColor.Rgb255(211, 134, 155), RgbaColor.Rgb255(250, 189, 47), RgbaColor.Rgb255(142, 192, 124), RgbaColor.Rgb255(254, 128, 25), RgbaColor.Rgb255(213, 196, 161), RgbaColor.Rgb255(131, 165, 152));

    private static readonly UiPaletteData Mono = new(
        RgbaColor.Rgb255(90, 90, 92), RgbaColor.Rgb255(140, 140, 145), RgbaColor.Rgb255(200, 200, 205), RgbaColor.Rgb255(120, 120, 125), RgbaColor.Rgb255(110, 110, 115), RgbaColor.Rgb255(150, 150, 155), RgbaColor.Rgb255(210, 210, 214), RgbaColor.Rgb255(190, 190, 194), RgbaColor.Rgb255(170, 170, 175), RgbaColor.Rgb255(155, 155, 160), RgbaColor.Rgb255(200, 200, 205), RgbaColor.Rgb255(180, 180, 185), RgbaColor.Rgb255(160, 160, 165), RgbaColor.Rgb255(140, 140, 145), RgbaColor.Rgb255(120, 120, 125));

    private static readonly UiPaletteData MegaDark = new(
        RgbaColor.Rgb255(2, 3, 6), RgbaColor.Rgb255(6, 9, 15), RgbaColor.Rgb255(10, 14, 22), RgbaColor.Rgb255(24, 18, 42), RgbaColor.Rgb255(36, 40, 58), RgbaColor.Rgb255(42, 52, 74), RgbaColor.Rgb255(255, 106, 61), RgbaColor.Rgb255(0, 230, 255), RgbaColor.Rgb255(97, 255, 170), RgbaColor.Rgb255(255, 64, 184), RgbaColor.Rgb255(255, 214, 64), RgbaColor.Rgb255(118, 114, 255), RgbaColor.Rgb255(189, 111, 255), RgbaColor.Rgb255(150, 161, 186), RgbaColor.Rgb255(76, 180, 255));

    private static readonly UiPaletteData OledBlack = new(
        RgbaColor.Rgb255(0, 0, 0), RgbaColor.Rgb255(0, 0, 0), RgbaColor.Rgb255(0, 0, 0), RgbaColor.Rgb255(0, 0, 0), RgbaColor.Rgb255(20, 24, 28), RgbaColor.Rgb255(18, 22, 26), RgbaColor.Rgb255(255, 126, 65), RgbaColor.Rgb255(45, 212, 255), RgbaColor.Rgb255(70, 255, 174), RgbaColor.Rgb255(255, 78, 174), RgbaColor.Rgb255(255, 219, 82), RgbaColor.Rgb255(134, 125, 255), RgbaColor.Rgb255(198, 118, 255), RgbaColor.Rgb255(185, 195, 214), RgbaColor.Rgb255(92, 188, 255));

    private static readonly UiPaletteData Rainbow = new(
        RgbaColor.Rgb255(255, 64, 64), RgbaColor.Rgb255(255, 184, 48), RgbaColor.Rgb255(76, 220, 120), RgbaColor.Rgb255(122, 92, 255), RgbaColor.Rgb255(255, 64, 64), RgbaColor.Rgb255(76, 220, 120), RgbaColor.Rgb255(255, 106, 61), RgbaColor.Rgb255(63, 197, 255), RgbaColor.Rgb255(92, 235, 156), RgbaColor.Rgb255(255, 76, 187), RgbaColor.Rgb255(255, 214, 64), RgbaColor.Rgb255(97, 113, 255), RgbaColor.Rgb255(177, 92, 255), RgbaColor.Rgb255(147, 160, 255), RgbaColor.Rgb255(0, 215, 255));
}
