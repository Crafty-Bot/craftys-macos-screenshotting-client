namespace CraftyCannon.Editor;

public enum EditorTool
{
    Pointer,
    Pen,
    FreehandArrow,
    Highlighter,
    Eraser,
    SmartEraser,
    Line,
    Arrow,
    Rectangle,
    FilledRectangle,
    Ellipse,
    Text,
    TextOutline,
    TextBackground,
    SpeechBalloon,
    StepMarker,
    HighlightBox,
    Magnifier,
    InsertImage,
    InsertScreenImage,
    Sticker,
    CursorStamp,
    Crop,
    Blur,
    Pixelate,
    BlackRedact
}

public sealed record EditorSession(string ImagePath, IReadOnlyList<EditorTool> AvailableTools);

public interface IImageEditor
{
    EditorSession Open(string imagePath);
}
