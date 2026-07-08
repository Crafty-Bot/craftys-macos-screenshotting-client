using CraftyCannon.Core;

namespace CraftyCannon.App;

public sealed class NoOpEditorLauncher : IEditorLauncher
{
    public bool TryOpenRecord(string recordId) => false;
}
