namespace GitReview.Domain;

/// <summary>Loading thresholds (match vscode-extension panelHtml.ts).</summary>
public static class PanelLayoutTiming
{
    public const long SkeletonDelayMs = 120;
    public const long WhyCeilingMs = 800;
}

public enum Emphasis
{
    Primary,
    Secondary,
    Link,
    Icon,
}

public static class EmphasisExt
{
    public static string Id(this Emphasis e) => e switch
    {
        Emphasis.Primary => "primary",
        Emphasis.Secondary => "secondary",
        Emphasis.Link => "link",
        Emphasis.Icon => "icon",
        _ => throw new ArgumentOutOfRangeException(nameof(e)),
    };
}

/// <summary>Closed set of 25 control ids: 20 body + 5 title bar.</summary>
public enum ControlId
{
    OpenEntry,
    OpenChange,
    ShowWhy,
    Next,
    Prev,
    InstallCli,
    CopyCliInstall,
    OutOfRangeHelp,
    ContinueReview,
    StartReview,
    SetBase,
    SetRemote,
    UndoFinish,
    ResumeFinish,
    DiscardInventory,
    // BODY controls: their subject is a row or section, not a product action, so
    // none of them enter the action matrix, the Tools menu or the .vsct — the
    // canonical's fixed count of 27 does not move for any of them.
    OpenDraft,
    CopyDraftPrompt,
    StartFromDraft,
    DiscardDraft,
    OpenGuide,
    CreateGuide,
    DiscardGuide,
    OpenWalkthrough,
    CopyWalkthroughPrompt,
    DiscardFixes,
    // DiscardAllFixes acts on the whole section, not one row. Runs clean
    // --fixes-only with NO branch, which by clean's own design never touches
    // review/* (Housekeeping.cs).
    DiscardAllFixes,
    CleanReview,
    CompareReview,
    WalkthroughInit,
    WalkthroughBuild,
    OpenSupport,
    Refresh,
    FinishReview,
    SaveReview,
    AbortReview,
    PreviewEdits,
}

public static class ControlIdExt
{
    public static string Wire(this ControlId id) => id switch
    {
        ControlId.OpenEntry => "openEntry",
        ControlId.OpenChange => "openChange",
        ControlId.ShowWhy => "showWhy",
        ControlId.Next => "next",
        ControlId.Prev => "prev",
        ControlId.InstallCli => "installCli",
        ControlId.CopyCliInstall => "copyCliInstall",
        ControlId.OutOfRangeHelp => "outOfRangeHelp",
        ControlId.ContinueReview => "continueReview",
        ControlId.StartReview => "startReview",
        ControlId.SetBase => "setBase",
        ControlId.SetRemote => "setRemote",
        ControlId.UndoFinish => "undoFinish",
        ControlId.ResumeFinish => "resumeFinish",
        ControlId.DiscardInventory => "discardInventory",
        ControlId.OpenDraft => "openDraft",
        ControlId.CopyDraftPrompt => "copyDraftPrompt",
        ControlId.StartFromDraft => "startFromDraft",
        ControlId.DiscardDraft => "discardDraft",
        ControlId.OpenGuide => "openGuide",
        ControlId.OpenWalkthrough => "openWalkthrough",
        ControlId.CopyWalkthroughPrompt => "copyWalkthroughPrompt",
        ControlId.CreateGuide => "createGuide",
        ControlId.DiscardGuide => "discardGuide",
        ControlId.DiscardFixes => "discardFixes",
        ControlId.DiscardAllFixes => "discardAllFixes",
        ControlId.CleanReview => "cleanReview",
        ControlId.CompareReview => "compareReview",
        ControlId.WalkthroughInit => "walkthroughInit",
        ControlId.WalkthroughBuild => "walkthroughBuild",
        ControlId.OpenSupport => "openSupport",
        ControlId.Refresh => "refresh",
        ControlId.FinishReview => "finishReview",
        ControlId.SaveReview => "saveReview",
        ControlId.AbortReview => "abortReview",
        ControlId.PreviewEdits => "previewEdits",
        _ => throw new ArgumentOutOfRangeException(nameof(id)),
    };

    public static ControlId? FromWire(string id) =>
        Enum.GetValues(typeof(ControlId)).Cast<ControlId?>().FirstOrDefault(c => c!.Value.Wire() == id);
}

public sealed record Control
{
    /// <summary>
    /// Enforced here rather than in the builder's <c>Ctrl</c> factory, because this
    /// record is what the panel actually renders: a label-less control must carry
    /// ICON emphasis, and an icon control needs a non-empty accessible name to be
    /// reachable.
    /// </summary>
    public Control(
        ControlId id,
        string? label,
        string accessibleName,
        Emphasis emphasis,
        bool enabled = true,
        string? tooltip = null,
        int? index = null,
        string? supportLinkId = null)
    {
        if (label is null)
        {
            if (emphasis != Emphasis.Icon)
                throw new ArgumentException($"Control {id.Wire()}: null label requires ICON emphasis");
            if (string.IsNullOrEmpty(accessibleName))
                throw new ArgumentException($"Control {id.Wire()}: icon controls need a non-empty accessibleName");
        }
        Id = id;
        Label = label;
        AccessibleName = accessibleName;
        Emphasis = emphasis;
        Enabled = enabled;
        Tooltip = tooltip;
        Index = index;
        SupportLinkId = supportLinkId;
    }

    public ControlId Id { get; init; }
    public string? Label { get; init; }
    public string AccessibleName { get; init; }
    public Emphasis Emphasis { get; init; }
    public bool Enabled { get; init; }
    public string? Tooltip { get; init; }
    public int? Index { get; init; }
    public string? SupportLinkId { get; init; }
}

public sealed record FileRow(string Display, int Index, bool LastOpened);

/// <summary>
/// A row of the draft block: the branch, the CLI's own progress count, and the
/// controls acting on THAT row. The view splits this one list by emphasis:
/// labelled controls render as the button pair underneath, Icon ones in the
/// header beside the progress. Order inside each half is the order here.
/// </summary>
public sealed record DraftRow
{
    /// <summary>
    /// Same rule as <see cref="InventoryRow"/>, for the same reason: a draft
    /// control is routed back to its row by index, so one without an index is a
    /// button that acts on no draft in particular.
    /// </summary>
    public DraftRow(string name, string meta, IReadOnlyList<Control> controls)
    {
        foreach (var c in controls)
        {
            if (c.Index is null)
                throw new ArgumentException($"Draft control {c.Id.Wire()} must carry an index");
        }
        Name = name;
        Meta = meta;
        Controls = controls;
    }

    public string Name { get; init; }
    public string Meta { get; init; }
    public IReadOnlyList<Control> Controls { get; init; }
}

/// <summary>
/// A row of the authoring-guide block: which guide it is, the CLI's badge for
/// its state, and the controls that act on THAT row. Same two-place shape as
/// <see cref="DraftRow"/>, and both guide rows carry the same controls
/// regardless of state — except Discard, which only the reviewer's own row
/// has: the shared guide is a tracked file, so removing it is `git rm` plus a
/// commit.
/// </summary>
public sealed record GuideRow
{
    public GuideRow(string name, string badge, IReadOnlyList<Control> controls)
    {
        foreach (var c in controls)
        {
            if (c.Index is null)
                throw new ArgumentException($"Guide control {c.Id.Wire()} must carry an index");
        }
        Name = name;
        Badge = badge;
        Controls = controls;
    }

    public string Name { get; init; }
    public string Badge { get; init; }
    public IReadOnlyList<Control> Controls { get; init; }
}

public sealed record InventoryRow
{
    /// <summary>
    /// An inventory control is routed back to its row by index; one without an
    /// index acts on no review in particular. <see cref="PanelLayout"/> checks
    /// the reverse direction — an index is only legal here.
    /// </summary>
    public InventoryRow(
        string name,
        IReadOnlyList<string> badges,
        string meta,
        IReadOnlyList<Control> controls,
        string? helpTooltip = null)
    {
        foreach (var c in controls)
        {
            if (c.Index is null)
                throw new ArgumentException($"Inventory control {c.Id.Wire()} must carry an index");
        }
        Name = name;
        Badges = badges;
        Meta = meta;
        Controls = controls;
        HelpTooltip = helpTooltip;
    }

    public string Name { get; init; }
    public IReadOnlyList<string> Badges { get; init; }
    public string Meta { get; init; }
    public IReadOnlyList<Control> Controls { get; init; }
    public string? HelpTooltip { get; init; }
}

public enum SkeletonShape
{
    Pos,
    Num,
    Title,
    WhyLine,
    Bar,
}

public abstract record Block
{
    public sealed record IdentityBar(
        string Mode,
        bool Draft,
        string Name,
        string? Tip = null,
        int? Position = null,
        int? Total = null,
        bool IsSkeleton = false) : Block;

    public sealed record Note(string Text) : Block;

    public sealed record Paragraph(string Text, bool Muted = false, bool Separated = false) : Block;

    public sealed record Heading(string Text) : Block;

    public sealed record Banner(IReadOnlyList<string> Paragraphs, Row ControlsRow) : Block;

    public sealed record CodeCommand(string Command, Control Copy) : Block;

    public sealed record EntryHead(
        int Position,
        string? Identifier = null,
        string? Author = null,
        string? Badge = null,
        bool IsSkeleton = false) : Block;

    public sealed record EntryTitle(string Text, bool Muted = false, bool IsSkeleton = false) : Block;

    public sealed record Why(WhyState State, string? Text = null, bool Uncovered = false) : Block;

    public sealed record Row : Block
    {
        public IReadOnlyList<Control> Controls { get; }

        public Row(IReadOnlyList<Control> controls)
        {
            if (controls.Count is < 1 or > 2)
                throw new ArgumentException($"Row must have 1 or 2 controls, got {controls.Count}");
            Controls = controls;
        }
    }

    public sealed record FileRows(IReadOnlyList<FileRow> Rows) : Block;

    public sealed record InventoryRows(IReadOnlyList<InventoryRow> Rows) : Block;
    public sealed record DraftRows(IReadOnlyList<DraftRow> Rows) : Block;

    public sealed record GuideRows(IReadOnlyList<GuideRow> Rows) : Block;

    /// <summary>
    /// The branches of edits a finish left behind, one row each. Reuses
    /// <see cref="GuideRow"/>'s shape (name, badge, controls) since nothing
    /// about a fixes row falls outside it.
    /// </summary>
    public sealed record FixesRows(IReadOnlyList<GuideRow> Rows) : Block;

    /// <summary>
    /// The author's own walkthrough, one row above the guides. Drawn only when
    /// the CLI reports the record — against an older CLI it does not arrive and
    /// the block disappears, same degradation as the guides and drafts blocks.
    /// </summary>
    public sealed record WalkthroughRow(GuideRow Entry) : Block;

    public sealed record ToolsSection : Block
    {
        public string Title { get; init; }
        public IReadOnlyList<Block> NestedBlocks { get; init; }

        /// <summary>
        /// A section is a flat group of rows under a title. Nesting another one
        /// (or a banner) inside would render a heading no client draws and give
        /// the same control two homes in <c>CollectControls</c>.
        /// </summary>
        public ToolsSection(string title, IReadOnlyList<Block> nestedBlocks)
        {
            if (nestedBlocks.Any(b => b is ToolsSection or Banner))
                throw new ArgumentException("ToolsSection cannot nest Banner/ToolsSection");
            Title = title;
            NestedBlocks = nestedBlocks;
        }
    }

    public sealed record Stderr(string Text) : Block;

    public sealed record EmptyMessage(string Text, Control? Control = null, string? StderrText = null) : Block;

    public sealed record Skeleton(SkeletonShape Shape) : Block;
}

public sealed class PanelLayout
{
    public Situation Situation { get; }
    public IReadOnlyList<Block> Blocks { get; }
    public IReadOnlyList<Control> TitleActions { get; }
    public bool FillsHeight { get; }

    public PanelLayout(
        Situation situation,
        IReadOnlyList<Block> blocks,
        IReadOnlyList<Control> titleActions,
        bool fillsHeight = false)
    {
        Situation = situation;
        Blocks = blocks;
        TitleActions = titleActions;
        FillsHeight = fillsHeight;

        var controls = CollectControls();
        // One PRIMARY per situation, counted over non-row controls only: a row
        // control repeats once per row ("the obvious thing for THIS draft"), so
        // counting it here would make the rule depend on how many drafts the
        // reviewer happens to have, which is not a property of the layout.
        var primaries = controls.Count(c => c.Emphasis == Emphasis.Primary && c.Index is null);
        if (primaries > 1)
            throw new ArgumentException($"At most one PRIMARY control per situation, found {primaries}");
        foreach (var c in controls)
        {
            if (c.Index is not null && !HostedByInventory(blocks, c))
                throw new ArgumentException($"index only allowed on InventoryRows controls ({c.Id.Wire()})");
        }
    }

    public IReadOnlyList<Control> CollectControls()
    {
        var list = new List<Control>();
        Walk(Blocks, list);
        list.AddRange(TitleActions);
        return list;
    }

    private static void Walk(IReadOnlyList<Block> blocks, List<Control> outList)
    {
        foreach (var b in blocks)
        {
            switch (b)
            {
                case Block.Row r: outList.AddRange(r.Controls); break;
                case Block.Banner bn: outList.AddRange(bn.ControlsRow.Controls); break;
                case Block.CodeCommand cc: outList.Add(cc.Copy); break;
                case Block.EmptyMessage em when em.Control is not null: outList.Add(em.Control); break;
                case Block.InventoryRows ir:
                    foreach (var row in ir.Rows) outList.AddRange(row.Controls);
                    break;
                case Block.DraftRows dr:
                    foreach (var row in dr.Rows) outList.AddRange(row.Controls);
                    break;
                case Block.GuideRows gr:
                    foreach (var row in gr.Rows) outList.AddRange(row.Controls);
                    break;
                case Block.FixesRows fr:
                    foreach (var row in fr.Rows) outList.AddRange(row.Controls);
                    break;
                case Block.WalkthroughRow wr: outList.AddRange(wr.Entry.Controls); break;
                case Block.ToolsSection ts: Walk(ts.NestedBlocks, outList); break;
            }
        }
    }

    private static bool HostedByInventory(IReadOnlyList<Block> blocks, Control c) =>
        blocks.Any(b => b switch
        {
            Block.InventoryRows ir => ir.Rows.Any(r => r.Controls.Any(x => ReferenceEquals(x, c) || x == c)),
            Block.DraftRows dr => dr.Rows.Any(r => r.Controls.Any(x => ReferenceEquals(x, c) || x == c)),
            Block.GuideRows gr => gr.Rows.Any(r => r.Controls.Any(x => ReferenceEquals(x, c) || x == c)),
            Block.FixesRows fr => fr.Rows.Any(r => r.Controls.Any(x => ReferenceEquals(x, c) || x == c)),
            Block.WalkthroughRow wr => wr.Entry.Controls.Any(x => ReferenceEquals(x, c) || x == c),
            Block.ToolsSection ts => HostedByInventory(ts.NestedBlocks, c),
            _ => false,
        });
}

public static class PanelLayoutBuilder
{
    // StartReview no esta: el asistente ya pregunta cuatro cosas y `start` no
    // destruye nada -- se niega solo con el arbol sucio, y una review empezada
    // se cancela con un boton del panel. Ver el canonico, bloque no-review.
    private static readonly HashSet<ControlId> ConfirmingIds = new()
    {
        ControlId.ContinueReview,
        ControlId.DiscardInventory,
        ControlId.DiscardDraft,
        ControlId.DiscardGuide,
        ControlId.DiscardFixes,
        ControlId.DiscardAllFixes,
        ControlId.CleanReview,
        ControlId.UndoFinish,
        ControlId.CompareReview,
        ControlId.WalkthroughInit,
        ControlId.WalkthroughBuild,
        ControlId.SaveReview,
        ControlId.AbortReview,
    };

    public static bool RequiresConfirmation(ControlId id) => ConfirmingIds.Contains(id);

    /// <summary>
    /// The mutations that bring the panel into view (`reveals:` in the
    /// canonical). Deliberately short: only mutations whose answer is a block
    /// that was not there before — a panel that jumps on every mutation stops
    /// meaning that something happened. See CLAUDE.md, "La copy de los paneles".
    /// </summary>
    private static readonly HashSet<ControlId> RevealingIds = new()
    {
        ControlId.StartReview,
        ControlId.StartFromDraft,
        ControlId.ContinueReview,
        ControlId.FinishReview,
    };

    public static bool RevealsPanel(ControlId id) => RevealingIds.Contains(id);

    private static Control Ctrl(
        ControlId id,
        string? label,
        Emphasis emphasis,
        bool enabled = true,
        string? accessibleName = null,
        string? tooltip = null,
        int? index = null,
        string? supportLinkId = null)
    {
        // The two rules live on the record itself; this only fills in the name a
        // labelled control gets for free.
        var name = accessibleName ?? label ?? id.Wire();
        return new Control(id, label, name, emphasis, enabled, tooltip, index, supportLinkId);
    }

    private static string? TipShort(string? tip) =>
        tip is null ? null : tip.Length <= 7 ? tip : tip.Substring(0, 7);

    private static string? EntryBadge(PanelEntry entry, ReviewMode? mode)
    {
        if (entry.Essential) return "key";
        if (mode == ReviewMode.Walk && !entry.Annotated) return "not covered";
        if (entry.Banked) return "edits";
        return null;
    }

    private static string InventoryMeta(PanelReview r)
    {
        if (r.Orphan) return "details are gone";
        if (r.Position is not null && r.Total is not null)
            return $"{(r.Mode?.Id() ?? "?")} · {r.Position}/{r.Total}";
        if (r.Mode is not null) return r.Mode.Value.Id();
        return "details are gone";
    }

    private static string InventoryHelp(PanelReview r)
    {
        var finish = r.Finish;
        if (finish is not null)
        {
            var source = r.Name.StartsWith("review/", StringComparison.Ordinal)
                ? r.Name["review/".Length..]
                : r.Name;
            return finish.State == "pending"
                ? $"Finish waiting on {(finish.Onto ? source : $"review-fixes/{source}")} — use Undo above."
                : "Finish stopped mid-conflict — switch to this branch to resolve or undo.";
        }
        return "Still active — switch to this branch to work on it.";
    }

    private static List<Block> Notes(PanelModel model)
    {
        var outList = new List<Block>();
        if (model.Readonly)
            outList.Add(new Block.Note("Read-only compare: finish is not available. Use Cancel when done."));
        if (model.KeysOnly)
            outList.Add(new Block.Note("Keys-only: reading order is restricted to walkthrough entries marked key."));
        if (model.BaseMoved)
            outList.Add(new Block.Note("The base moved: fewer entries remain in range than when the review started."));
        if (model.Degraded)
            outList.Add(new Block.Note("The walkthrough does not cover the review's current range; showing the full range diff."));
        if (model.Base is not null)
            outList.Add(new Block.Note($"Range built against {model.Base}."));
        return outList;
    }

    private static Block.IdentityBar IdentityBar(PanelModel model, bool skeleton = false)
    {
        var name = model.Source ?? model.Branch ?? "?";
        var displayName = model.RepoLabel is not null ? $"{name} · {model.RepoLabel}" : name;
        return new Block.IdentityBar(
            Mode: model.Mode?.Id() ?? "?",
            Draft: model.Draft,
            Name: displayName,
            Tip: TipShort(model.Tip),
            Position: skeleton ? null : model.Position,
            Total: skeleton ? null : model.Total,
            IsSkeleton: skeleton);
    }

    private static Block.Row OpenRow(PanelModel model, bool enabled) =>
        model.Mode == ReviewMode.Step
            ? new Block.Row(new[] { Ctrl(ControlId.OpenChange, "Diff", Emphasis.Secondary, enabled) })
            : new Block.Row(new[]
            {
                Ctrl(ControlId.OpenEntry, "File", Emphasis.Secondary, enabled),
                Ctrl(ControlId.OpenChange, "Diff", Emphasis.Secondary, enabled),
            });

    private static Block.Row NavRow(PanelModel model, bool enabled)
    {
        var baseEnabled = enabled && !model.Busy;
        return new Block.Row(new[]
        {
            Ctrl(ControlId.Prev, null, Emphasis.Icon, baseEnabled && !model.AtFirst, accessibleName: "Previous entry"),
            Ctrl(ControlId.Next, null, Emphasis.Icon, baseEnabled && !model.AtLast, accessibleName: "Next entry"),
        });
    }

    private static Block.Why WhyBlock(PanelWhy why, PanelEntry? entry, ReviewMode? mode)
    {
        var uncovered = mode == ReviewMode.Walk && entry?.Annotated == false;
        return why.State switch
        {
            WhyState.Present => new Block.Why(WhyState.Present, why.Text, Uncovered: false),
            WhyState.Absent => new Block.Why(
                WhyState.Absent,
                uncovered
                    ? "This file changes in the review and the walkthrough does not annotate it."
                    : "This entry has no explanation.",
                Uncovered: uncovered),
            WhyState.Failed => new Block.Why(WhyState.Failed, "Could not read the why for this entry."),
            WhyState.Loading => new Block.Why(WhyState.Loading),
            _ => new Block.Why(WhyState.Loading),
        };
    }

    private static List<Block> EntryBlocks(PanelModel model, bool enabled, bool includeNav)
    {
        var current = model.Current;
        if (current is null)
            return new List<Block> { new Block.EmptyMessage("The cursor does not point at any entry in the sequence.") };

        var outList = new List<Block>();
        var named = model.Mode == ReviewMode.Step && current.Subject is not null;
        outList.Add(new Block.EntryHead(
            current.Position,
            Identifier: named ? current.Display : null,
            Author: named ? current.Author : null,
            Badge: EntryBadge(current, model.Mode)));

        if (named && current.Subject == "")
            outList.Add(new Block.EntryTitle("This commit has no subject.", Muted: true));
        else
            outList.Add(new Block.EntryTitle(named ? current.Subject! : current.Display));

        if (model.Mode == ReviewMode.Walk)
        {
            var why = model.Why;
            if (why is not null)
            {
                outList.Add(WhyBlock(why, current, model.Mode));
                if (why.State == WhyState.Present)
                {
                    outList.Add(new Block.Row(new[]
                    {
                        Ctrl(ControlId.ShowWhy, "open in editor", Emphasis.Link, enabled),
                    }));
                }
            }
        }

        outList.Add(OpenRow(model, enabled));
        if (model.Mode == ReviewMode.Step)
            outList.AddRange(FileInventoryBlocks(model, enabled, "commit"));
        if (includeNav && !model.NavigationLocked)
            outList.Add(NavRow(model, enabled));
        return outList;
    }

    /// <summary>
    /// Whole is just the file inventory. An "open every change at once" button
    /// is deliberately absent: <c>IVsDifferenceService</c> only opens one
    /// comparison window per file pair, so that button would open a window per
    /// changed file — a cap on that is still an avalanche. The file rows below
    /// open each diff on demand instead. Declared as <c>not_in: [visualstudio]</c>
    /// in <c>contracts/client-product-surface.yaml</c>.
    /// </summary>
    private static List<Block> WholeBlocks(PanelModel model, bool enabled) =>
        FileInventoryBlocks(model, enabled, "review");

    private static List<Block> FileInventoryBlocks(
        PanelModel model,
        bool enabled,
        string unit)
    {
        if (model.FilesList.Count == 0)
        {
            var empty = unit == "commit"
                ? "This commit changes no files."
                : "This review's range does not touch any files.";
            return new List<Block> { new Block.EmptyMessage(empty) };
        }

        var n = model.FilesList.Count;
        var heading = n == 1 ? $"1 file in this {unit}" : $"{n} files in this {unit}";
        var outList = new List<Block> { new Block.Heading(heading) };
        outList.Add(new Block.FileRows(
            model.FilesList.Select(f => new FileRow(f.Display, f.Position, f.Display == model.LastOpened)).ToList()));
        return outList;
    }

    private static Block.Banner FinishConflictBanner(bool enabled) =>
        new(
            new[]
            {
                "This finish stopped at a conflict. Resolve the markers, then continue — or undo it to go back to editing.",
            },
            new Block.Row(new[]
            {
                Ctrl(ControlId.UndoFinish, "Undo", Emphasis.Secondary, enabled),
                Ctrl(ControlId.ResumeFinish, "Continue", Emphasis.Secondary, enabled),
            }));

    private static List<Block> FinishPendingBlocks(PanelModel model)
    {
        var pending = model.PendingFinish;
        var source = "this branch";
        var destination = "review-fixes/...";
        if (pending is not null)
        {
            source = pending.Branch.StartsWith("review/", StringComparison.Ordinal)
                ? pending.Branch["review/".Length..]
                : pending.Branch;
            destination = pending.Onto ? source : $"review-fixes/{source}";
        }
        var enabled = !model.Busy;
        return new List<Block>
        {
            new Block.Banner(
                new[]
                {
                    $"Your edits are on {destination}, staged and ready to commit.",
                    "Commit and push them from Source Control. You can still undo this finish.",
                },
                new Block.Row(new[]
                {
                    Ctrl(ControlId.CleanReview, "Keep edits & remove Undo", Emphasis.Primary, enabled),
                    Ctrl(ControlId.UndoFinish, "Undo Finish", Emphasis.Secondary, enabled),
                })),
        };
    }

    private static List<Block> CliBlocks(PanelModel model, bool missing)
    {
        var title = missing
            ? $"The git-review CLI ({CliVersion.MinCliVersion} or newer) was not found."
            : $"The installed git-review CLI is older than {CliVersion.MinCliVersion}.";
        var hint = missing ? "Install with npm (recommended):" : "Update with npm (recommended):";
        var cmd = missing ? InstallHint.NpmInstallCmd : InstallHint.NpmUpdateCmd;
        var outList = new List<Block>
        {
            new Block.Paragraph(title),
            new Block.Paragraph(hint, Muted: true),
            new Block.CodeCommand(
                cmd,
                Ctrl(ControlId.CopyCliInstall, "Copy", Emphasis.Secondary,
                    accessibleName: "Copy install command",
                    tooltip: "Copy to clipboard")),
            new Block.Paragraph(
                "Reload the window after installing, or wait — the panel checks again every few seconds.",
                Muted: true),
            new Block.Row(new[] { Ctrl(ControlId.InstallCli, "Other install options", Emphasis.Link) }),
        };
        if (!string.IsNullOrWhiteSpace(model.Stderr))
            outList.Add(new Block.Stderr(model.Stderr!));
        return outList;
    }

    private static List<Block> SetupBlocks(PanelModel model)
    {
        var remote = model.ConfiguredRemote ?? "origin";
        var enabled = !model.Busy;
        return new List<Block>
        {
            new Block.Paragraph("Which branch do pull requests land on in this repo?"),
            new Block.Row(new[] { Ctrl(ControlId.SetBase, "Choose the branch", Emphasis.Primary, enabled) }),
            new Block.Paragraph(
                "Reviews compare the branch you are reading against it. Usually main or develop."),
            new Block.Paragraph($"Remote: {remote} (optional)."),
            new Block.Row(new[] { Ctrl(ControlId.SetRemote, "Change remote", Emphasis.Secondary, enabled) }),
        };
    }

    private static Block.InventoryRows InventoryRows(PanelModel model)
    {
        var enabled = !model.Busy;
        var rows = model.ReviewsList.Select((r, index) =>
        {
            var badges = new List<string>();
            if (r.Current) badges.Add("current");
            if (r.Orphan) badges.Add("broken");
            var canDiscard = r.Saved || r.Orphan;
            var controls = new List<Control>();
            if (canDiscard)
            {
                if (r.Saved)
                {
                    string? tip = null;
                    if (!r.Resumable)
                        tip = r.Orphan
                            ? "This review cannot be resumed — its details are gone"
                            : "You are already reviewing this branch";
                    controls.Add(Ctrl(
                        ControlId.ContinueReview, "Continue", Emphasis.Secondary,
                        enabled: enabled && r.Resumable, tooltip: tip, index: index));
                }
                var discardLabel = r.Orphan ? "Delete leftover" : "Delete";
                var discardTip = r.Saved
                    ? "Delete this paused review and its edits"
                    : "Delete this leftover branch";
                controls.Add(Ctrl(
                    ControlId.DiscardInventory, discardLabel, Emphasis.Secondary,
                    enabled: enabled, tooltip: discardTip, index: index));
            }
            return new InventoryRow(
                r.Name,
                badges,
                InventoryMeta(r),
                controls,
                !canDiscard && !r.Current ? InventoryHelp(r) : null);
        }).ToList();
        return new Block.InventoryRows(rows);
    }

    /// <summary>
    /// The draft rows whose Spent is <paramref name="spent"/> — reading orders
    /// the reviewer started and has not paused. Unlike the setup gate (no base
    /// configured), this is additive over the normal empty-state body, not a
    /// replacement: a half-written reading order does not block the rest of the
    /// panel. The index passed to the host is from the FULL list, so it still
    /// resolves the right file after the split into two blocks.
    /// </summary>
    private static Block.DraftRows DraftRows(PanelModel model, bool spent = false)
    {
        var enabled = !model.Busy;
        var rows = model.DraftsList
            .Select((d, index) => (Draft: d, Index: index))
            .Where(x => x.Draft.Spent == spent)
            .Select(x =>
        {
            var d = x.Draft;
            var index = x.Index;
            // The ORDER of controls is fixed regardless of state: moving the
            // click target as the row's state changes would slide it under the
            // cursor.
            //
            // Total == 0 means "this file declares no entry at all", never
            // "complete": the CLI reports 0/0 both for an emptied draft and for
            // one an agent is writing right now (the watcher fires on the first
            // Changed, before the first "## N." heading lands). Without the
            // Total > 0 check the row reads as finished and disables Copy for
            // agent — the one control the state most needs.
            var filled = d.Total > 0 && d.Annotated >= d.Total;
            var controls = new List<Control>();
            // A spent row skips the labelled pair: writing the order and
            // starting the review both already happened. The two icon controls
            // below stay either way, so a spent row can still be opened or
            // discarded.
            if (!spent)
            {
                controls.Add(Ctrl(
                    ControlId.CopyDraftPrompt, "Copy for agent",
                    filled ? Emphasis.Secondary : Emphasis.Primary,
                    enabled: true, tooltip: "Copy an instruction naming this file", index: index));
                // StartFromDraft is gated on two independent things: Startable
                // (the file lost its header and cannot be checked at all) and
                // filled (every entry the skeleton counts, including the
                // heads-up placeholder, must be written or build fails on
                // drift). Known cost: the count comes off disk, so unsaved edits
                // keep this gray until Ctrl+S — the host's directory watcher
                // refreshes the panel once they are saved.
                controls.Add(Ctrl(
                    ControlId.StartFromDraft, "Validate and start",
                    filled ? Emphasis.Primary : Emphasis.Secondary,
                    enabled: enabled && d.Startable && filled,
                    tooltip: !d.Startable
                        ? "This file lost its header, so it cannot be checked. Delete it and write a new one."
                        : filled
                            ? "Check the order, then start reading"
                            : "Every file still needs a number and a line saying why it matters",
                    index: index));
            }
            // Open/Discard render as icon glyphs rather than a third boxed
            // button: a box-less button among boxed ones reads as disabled. With
            // no visible label the accessible name IS the control's name ("Open"
            // alone would repeat once per draft).
            controls.Add(Ctrl(
                ControlId.OpenDraft, null, Emphasis.Icon,
                enabled: true,
                accessibleName: "Open the reading order",
                tooltip: "Open the reading order for editing",
                index: index));
            controls.Add(Ctrl(
                ControlId.DiscardDraft, null, Emphasis.Icon,
                enabled: enabled,
                accessibleName: "Discard the reading order",
                tooltip: "Delete this reading order",
                index: index));
            return new DraftRow(d.Branch, $"{d.Annotated}/{d.Total}", controls);
        }).ToList();
        return new Block.DraftRows(rows);
    }

    /// <summary>
    /// The rows of "Edits you extracted": branch, badge, and the one control
    /// that makes sense here — committing and pushing are Source Control's,
    /// which is where finish already sends you.
    ///
    /// The row you are standing on renders without the control: the CLI skips
    /// it ("skipping, currently checked out"), so offering the button would
    /// promise something that will not happen. Hiding the row would be worse —
    /// it is a branch that exists and no other surface names.
    /// </summary>
    private static Block.FixesRows FixesRowsBlock(PanelModel model)
    {
        var enabled = !model.Busy;
        var rows = model.FixesList.Select((f, index) => new GuideRow(
            f.Name,
            f.Badge,
            new[]
            {
                Ctrl(
                    ControlId.DiscardFixes, null, Emphasis.Icon,
                    enabled: enabled && !f.Current,
                    accessibleName: "Discard the extracted edits",
                    tooltip: f.Current
                        ? "You are on this branch; switch away first"
                        : "Delete this branch of edits",
                    index: index),
            })).ToList();
        return new Block.FixesRows(rows);
    }

    /// <summary>
    /// The authoring-guide block, inside the Walkthrough section. Both rows
    /// always draw, whether or not the file exists — only each control's
    /// enabled state changes, never the rows' presence. Discard is the one
    /// exception: the shared guide is a tracked file, so removing it is `git
    /// rm` plus a commit, not this button's call (the CLI agrees, refusing
    /// `--delete --team`).
    /// </summary>
    private static Block.GuideRows GuideRowsBlock(PanelModel model)
    {
        var enabled = !model.Busy;
        var rows = model.GuidesList.Select((g, index) =>
        {
            var controls = new List<Control>
            {
                Ctrl(
                    ControlId.CreateGuide, "Create", Emphasis.Secondary,
                    enabled: enabled && !g.Exists,
                    tooltip: g.Exists
                        ? "It already exists; open it and edit it"
                        : "Create it empty, then write the conventions into it",
                    index: index),
                // With no visible label the accessible name IS the name of the
                // control, and it names the row: "Open" on its own repeats once
                // per guide.
                Ctrl(
                    ControlId.OpenGuide, null, Emphasis.Icon,
                    enabled: g.Exists,
                    accessibleName: "Open the guide",
                    tooltip: g.Exists ? g.Path : "There is no guide yet",
                    index: index),
            };
            if (g.Kind == GuideKind.Own)
            {
                controls.Add(Ctrl(
                    ControlId.DiscardGuide, null, Emphasis.Icon,
                    enabled: enabled && g.Discardable,
                    accessibleName: "Discard the guide",
                    tooltip: "Delete your guide",
                    index: index));
            }
            return new GuideRow(g.Label, g.Badge, controls);
        }).ToList();
        return new Block.GuideRows(rows);
    }

    /// <summary>
    /// The author's walkthrough row, first of the section, above the guides.
    /// Same two-place shape as the guide rows, but also owns two VERBS (init,
    /// build) that a guide row leaves to the section title — their subject is
    /// the file this row names, exactly as Create is each guide's. Labels carry
    /// no "Walkthrough" prefix here (the section title already says it); the
    /// menu and Tools submenu keep the prefix, where no section gives context.
    ///
    /// The badge says "may be out of date", not "out of date": the CLI's
    /// refresh-time comparison is cheap and approximate (has the range moved
    /// since the file was written); the exact answer is build's.
    ///
    /// Copy for agent copies a POINTER to the file, never the brief — that lives
    /// in the walkthrough's own top comment, where it stays current on its own.
    /// </summary>
    private static Block.WalkthroughRow WalkthroughRowBlock(PanelWalkthrough w, bool enabled)
    {
        var controls = new List<Control>
        {
            // The same verb creates and updates; the label follows the CLI's
            // reported state ("Init" over a file full of prose would promise
            // what the verb no longer does). Index is always 0: one walkthrough
            // row per panel.
            Ctrl(
                ControlId.WalkthroughInit,
                w.ActionLabel switch
                {
                    "Update" => "Update",
                    "Start over" => "Start over",
                    _ => "Init",
                },
                Emphasis.Secondary,
                enabled: enabled,
                index: 0),
            Ctrl(ControlId.WalkthroughBuild, "Build", Emphasis.Secondary, enabled: enabled, index: 0),
            Ctrl(
                ControlId.CopyWalkthroughPrompt, "Copy for agent", Emphasis.Secondary,
                enabled: w.Exists,
                tooltip: w.Exists
                    ? "Copy a pointer to the file; the instructions are inside it"
                    : "Create the walkthrough first, then hand it to an agent",
                index: 0),
            Ctrl(
                ControlId.OpenWalkthrough, null, Emphasis.Icon,
                enabled: w.Exists,
                accessibleName: "Open the walkthrough",
                tooltip: w.Exists ? w.Path : "There is no walkthrough to open yet",
                index: 0),
        };
        var progress = w.Exists && w.Total > 0 ? $"  {w.Annotated}/{w.Total}" : "";
        return new Block.WalkthroughRow(new GuideRow(w.Label + progress, w.Badge, controls));
    }

    private static List<Block> NoReviewReadyBlocks(PanelModel model)
    {
        var enabled = !model.Busy;
        var outList = new List<Block>();
        // Only the FRESH ones. A draft whose review is over survives (clean
        // never touches hand-written prose; discarding it is forget), but it is
        // no longer pending work, so it drops to its own collapsed footer
        // section with only the controls it still has use for.
        var freshDrafts = model.DraftsList.Count(d => !d.Spent);
        if (freshDrafts > 0)
        {
            outList.Add(new Block.Heading("Reading orders you started"));
            outList.Add(DraftRows(model));
        }
        if (model.ReviewsList.Count > 0)
        {
            outList.Add(new Block.Heading("Reviews in this repository"));
            outList.Add(InventoryRows(model));
        }
        outList.Add(new Block.Paragraph(
            "No active review on this branch.",
            Separated: model.ReviewsList.Count > 0 || freshDrafts > 0));
        outList.Add(new Block.Row(new[]
        {
            Ctrl(ControlId.StartReview, "Start a review", Emphasis.Primary, enabled),
        }));
        // Everything about the walkthrough together: the author's file (init,
        // build, Copy for agent on its row) and the two authoring guides. All
        // hang off the same CLI verb, so they get their own section rather than
        // sharing "Other actions" with Compare.
        var walkthroughKids = new List<Block>();
        if (model.Walkthrough is not null)
        {
            walkthroughKids.Add(WalkthroughRowBlock(model.Walkthrough, enabled));
        }
        if (model.GuidesList.Count > 0)
        {
            walkthroughKids.Add(GuideRowsBlock(model));
        }
        outList.Add(new Block.ToolsSection("Walkthrough", walkthroughKids));
        // Collapsed, not hidden: a file that exists with no surface naming it is
        // a state this panel disallows elsewhere, and hiding the row would take
        // the one control that discards it without spelling its branch.
        if (model.DraftsList.Any(d => d.Spent))
        {
            outList.Add(new Block.ToolsSection(
                "Reading orders you finished with",
                new List<Block>
                {
                    new Block.Paragraph("Their review is over; the files are still here"),
                    DraftRows(model, spent: true),
                }));
        }
        // Behind the spent reading orders on purpose: both are leftovers of
        // reviews already done, but this one may still be pending work on
        // ANOTHER screen (Source Control), not this one.
        //
        // "Discard all" runs clean --fixes-only with NO branch, which by
        // clean's design never touches review/* (other branches' live
        // sessions). Still behind a confirmation with full detail — this is
        // hand-written work, not machine litter — with the rows below as the
        // default path for deciding branch by branch.
        if (model.FixesList.Count > 0)
        {
            outList.Add(new Block.ToolsSection(
                "Edits you extracted",
                new List<Block>
                {
                    new Block.Paragraph(
                        "One branch per finish; commit and push them from Source Control, or drop them here"),
                    new Block.Row(new[] { Ctrl(ControlId.DiscardAllFixes, "Discard all", Emphasis.Secondary, enabled) }),
                    FixesRowsBlock(model),
                }));
        }
        // Compare goes last of the three footer sections: it is the only one
        // that mounts something OUTSIDE the review at hand (any two revisions,
        // no review to start), so it sits below everything that IS about that
        // review.
        outList.Add(new Block.ToolsSection(
            "Compare",
            new Block[]
            {
                new Block.Row(new[] { Ctrl(ControlId.CompareReview, "Compare revisions", Emphasis.Secondary, enabled) }),
            }));
        var settingsKids = new List<Block>();
        if (model.ConfiguredBase is not null)
        {
            settingsKids.Add(new Block.Paragraph($"Base: {model.ConfiguredBase}."));
            settingsKids.Add(new Block.Row(new[]
            {
                Ctrl(ControlId.SetBase, "Change the base branch", Emphasis.Secondary, enabled),
            }));
        }
        if (model.ConfiguredRemote is not null)
        {
            settingsKids.Add(new Block.Paragraph($"Remote: {model.ConfiguredRemote}."));
            settingsKids.Add(new Block.Row(new[]
            {
                Ctrl(ControlId.SetRemote, "Change remote", Emphasis.Secondary, enabled),
            }));
        }
        outList.Add(new Block.ToolsSection("Settings", settingsKids));
        outList.Add(new Block.ToolsSection(
            "Support",
            new Block[]
            {
                new Block.Row(new[]
                {
                    Ctrl(ControlId.OpenSupport, "Star on GitHub", Emphasis.Secondary,
                        supportLinkId: SupportLinks.Star),
                    Ctrl(ControlId.OpenSupport, "Report a bug", Emphasis.Secondary,
                        supportLinkId: SupportLinks.Bug),
                }),
            }));
        return outList;
    }

    private static List<Block> DiagnosticBlocks(PanelModel model, bool outOfRange)
    {
        var text = outOfRange
            ? "The cursor is out of range: the base moved."
            : "Something went wrong reading the review state.";
        var outList = new List<Block>
        {
            new Block.Paragraph(text),
            new Block.Row(new[] { Ctrl(ControlId.OutOfRangeHelp, "How to fix it", Emphasis.Primary) }),
        };
        if (!string.IsNullOrWhiteSpace(model.Stderr))
            outList.Add(new Block.Stderr(model.Stderr!));
        return outList;
    }

    private static List<Block> SkeletonBody(PanelModel model)
    {
        var outList = new List<Block> { IdentityBar(model, skeleton: true) };
        outList.AddRange(Notes(model));
        outList.Add(new Block.EntryHead(model.Position ?? 0, IsSkeleton: true));
        outList.Add(new Block.EntryTitle("", IsSkeleton: true));
        if (model.Mode == ReviewMode.Walk)
            outList.Add(new Block.Why(WhyState.Loading));
        outList.Add(OpenRow(model, enabled: false));
        if (model.Mode == ReviewMode.Step)
            outList.AddRange(FileInventoryBlocks(model, enabled: false, "commit"));
        if (!model.NavigationLocked)
            outList.Add(NavRow(model, enabled: false));
        return outList;
    }

    public static IReadOnlyList<Control> TitleBarActions(PanelModel model)
    {
        var outList = new List<Control>
        {
            Ctrl(ControlId.Refresh, "Refresh", Emphasis.Secondary, enabled: true),
        };
        var busy = model.Busy;
        var sit = model.Situation;
        if (sit == Situation.Review && !model.Readonly && !busy)
            outList.Add(Ctrl(ControlId.FinishReview, "Finish", Emphasis.Secondary, enabled: true));
        if (sit == Situation.Review && !busy)
            outList.Add(Ctrl(ControlId.SaveReview, "Save", Emphasis.Secondary, enabled: true));
        if ((sit is Situation.Review or Situation.FinishConflict) && !busy)
            outList.Add(Ctrl(ControlId.AbortReview, "Cancel", Emphasis.Secondary, enabled: true));
        if ((sit is Situation.Review or Situation.FinishConflict) && !busy)
            outList.Add(Ctrl(ControlId.PreviewEdits, "Preview edits", Emphasis.Secondary, enabled: true));
        return outList;
    }

    /// <summary>
    /// Pure layout projection. When loading is true, returns the skeleton silhouette
    /// for review-readable situations (controls disabled).
    /// </summary>
    public static PanelLayout PanelLayout(PanelModel model, bool loading = false)
    {
        var title = TitleBarActions(model);
        if (loading && SituationIds.IsReviewReadable(model.Situation) && model.Mode != ReviewMode.Whole)
        {
            return new PanelLayout(
                model.Situation,
                SkeletonBody(model),
                title.Select(t => t with { Enabled = false }).ToList(),
                fillsHeight: false);
        }

        List<Block> blocks;
        var fills = false;
        switch (model.Situation)
        {
            case Situation.CliMissing:
                blocks = CliBlocks(model, missing: true);
                break;
            case Situation.CliOutdated:
                blocks = CliBlocks(model, missing: false);
                break;
            case Situation.OutOfRange:
                blocks = DiagnosticBlocks(model, outOfRange: true);
                break;
            case Situation.Error:
                blocks = DiagnosticBlocks(model, outOfRange: false);
                break;
            case Situation.FinishPending:
                blocks = FinishPendingBlocks(model);
                break;
            case Situation.NoReview:
                if (model.NoBaseConfigured)
                {
                    blocks = SetupBlocks(model);
                }
                else
                {
                    blocks = NoReviewReadyBlocks(model);
                    fills = true;
                }
                break;
            case Situation.Review:
            case Situation.FinishConflict:
            {
                var enabled = !model.Busy;
                var outList = new List<Block> { IdentityBar(model) };
                if (model.Situation == Situation.FinishConflict)
                    outList.Add(FinishConflictBanner(enabled));
                outList.AddRange(Notes(model));
                if (model.Mode == ReviewMode.Whole)
                    outList.AddRange(WholeBlocks(model, enabled));
                else
                {
                    outList.AddRange(EntryBlocks(
                        model,
                        enabled,
                        includeNav: model.Situation == Situation.Review));
                }
                blocks = outList;
                break;
            }
            default:
                blocks = new List<Block>();
                break;
        }

        return new PanelLayout(model.Situation, blocks, title, fills);
    }
}
