namespace GitReview.VS.ToolWindows;

/// <summary>
/// One side of a diff the panel asks the host to open.
///
/// <paramref name="Ref"/> null means "the file in the working tree"; a ref (<c>HEAD</c>,
/// <c>abc1234^</c>) means the blob at that ref. <paramref name="Path"/> null means the
/// side does not exist at all — the change adds the file, or deletes it — and the viewer
/// gets an empty pane rather than a diff against itself.
/// </summary>
public sealed record DiffSide(string? Ref, string? Path, string Label);

/// <summary>One file, two sides, as the host's comparison window wants it.</summary>
public sealed record DiffRequest(string Title, DiffSide Left, DiffSide Right);

/// <summary>
/// The half of the action matrix only the IDE can do. Everything else — which CLI verb
/// an action maps to, its confirmation, the staleness re-check — lives in
/// <see cref="ActionDispatcher"/>, which is why this is a bag of optional callbacks
/// rather than an interface: the standalone build supplies none of them and the
/// dispatcher still answers for every wire.
/// </summary>
public sealed class PanelHost
{
    /// <summary>The single git root the review runs in, or null when there isn't one.</summary>
    public Func<string?>? Cwd { get; init; }

    /// <summary>Opens a working-tree file, given its path relative to <see cref="Cwd"/>.</summary>
    public Func<string, Task>? OpenEntryFile { get; init; }

    /// <summary>Opens one or more comparison windows.</summary>
    public Func<IReadOnlyList<DiffRequest>, Task>? OpenDiffs { get; init; }

    /// <summary>Shows text as a read-only scratch document (the why, a preview diff).</summary>
    public Func<string, Task>? OpenText { get; init; }

    /// <summary>
    /// Opens an absolute path — the walkthrough sidecar, the reviewer's draft. Returns
    /// false when it could not be shown, which the draft flow reports so the reviewer
    /// still learns where the file is.
    /// </summary>
    public Func<string, Task<bool>>? OpenPath { get; init; }

    /// <summary>
    /// Flushes the editor's unsaved buffer for an absolute path. The draft is validated
    /// by reading it off disk, and an IDE only saves on focus loss — which is exactly
    /// what does not happen while a modal wizard is driving.
    /// </summary>
    public Func<string, Task>? SavePath { get; init; }

    /// <summary>`git review preview [--stat]` as a document.</summary>
    public Func<bool, Task>? PreviewEdits { get; init; }

    /// <summary>The stored default for the wizard's origin step ("remote" when unset).</summary>
    public Func<string?>? DefaultSource { get; init; }

    /// <summary>
    /// Announces a mutation that is running, and returns the handle that ends it. The
    /// panel greys its buttons out while the CLI works, but the reviewer who started a
    /// finish from the menu is not necessarily looking at the panel -- VS Code raises a
    /// notification and IntelliJ a background task for exactly that. Null in the
    /// standalone build, where there is no shell to report into.
    /// </summary>
    public Func<string, IDisposable>? Progress { get; init; }

    /// <summary>
    /// Brings the panel into view WITHOUT taking focus. Only the mutations the
    /// canonical lists under <c>reveals:</c> use it, and only through
    /// <see cref="PanelReveal"/> — never called straight from an action.
    /// Null in the standalone build, where there is no shell to bring anything
    /// forward.
    /// </summary>
    public Action? RevealPanel { get; init; }
}
