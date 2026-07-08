namespace CraftyCannon.Core;

public sealed record PostUploadExecutionStep(
    PostUploadActionKind Kind,
    string Value,
    bool Succeeded);

public sealed class PostUploadActionExecutor(
    IClipboardService clipboard,
    IShellLauncher shell,
    IEditorLauncher editor)
{
    public IReadOnlyList<PostUploadExecutionStep> Execute(IEnumerable<PostUploadAction> actions)
    {
        var steps = new List<PostUploadExecutionStep>();
        foreach (var action in actions)
        {
            var succeeded = action.Kind switch
            {
                PostUploadActionKind.CopyImage => clipboard.TrySetImage(action.Value),
                PostUploadActionKind.CopyText => clipboard.TrySetText(action.Value),
                PostUploadActionKind.OpenUrl => shell.TryOpenUrl(action.Value),
                PostUploadActionKind.OpenEditor => editor.TryOpenRecord(action.Value),
                _ => false
            };

            steps.Add(new PostUploadExecutionStep(action.Kind, action.Value, succeeded));
        }

        return steps;
    }
}
