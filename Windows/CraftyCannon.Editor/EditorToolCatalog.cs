namespace CraftyCannon.Editor;

public static class EditorToolCatalog
{
    public static IReadOnlyList<EditorTool> ParityTools { get; } =
    [
        EditorTool.Pointer,
        EditorTool.Pen,
        EditorTool.FreehandArrow,
        EditorTool.Highlighter,
        EditorTool.Eraser,
        EditorTool.SmartEraser,
        EditorTool.Line,
        EditorTool.Arrow,
        EditorTool.Rectangle,
        EditorTool.FilledRectangle,
        EditorTool.Ellipse,
        EditorTool.Text,
        EditorTool.TextOutline,
        EditorTool.TextBackground,
        EditorTool.SpeechBalloon,
        EditorTool.StepMarker,
        EditorTool.HighlightBox,
        EditorTool.Magnifier,
        EditorTool.InsertImage,
        EditorTool.InsertScreenImage,
        EditorTool.Sticker,
        EditorTool.CursorStamp,
        EditorTool.Crop,
        EditorTool.Blur,
        EditorTool.Pixelate,
        EditorTool.BlackRedact
    ];
}
