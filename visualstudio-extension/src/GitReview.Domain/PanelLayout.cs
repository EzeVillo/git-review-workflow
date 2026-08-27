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
    // Draft block (012): four BODY controls, not product actions. They are not
    // in the action matrix, not in the Tools menu, not in the .vsct, and the
    // canonical's fixed count of 27 does not move.
    OpenDraft,
    CopyDraftPrompt,
    StartFromDraft,
    DiscardDraft,
    OpenGuide,
    CreateGuide,
    DiscardGuide,
    // The author's walkthrough row: two BODY controls, same rule as the four
    // above — without the row that draws them they have no subject, so the fixed
    // count of 27 does not move.
    OpenWalkthrough,
    CopyWalkthroughPrompt,
    // The "Edits you extracted" section: one BODY control, row -> index, same
    // rule as the ones above — the fixed count of 27 does not move.
    DiscardFixes,
    // The bulk of that same section: no index, subject is the whole section and
    // not one row, but same treatment as OpenSupport — a BODY control outside
    // the fixed count of 27. Runs clean --fixes-only with NO branch, which by
    // clean's own design never touches review/* (see Housekeeping.cs).
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
    /// The two rules a control cannot break, checked here and not in the factory:
    /// a label-less control is an icon button and an icon button is unreachable
    /// without a name to read out. Callers inside the builder go through
    /// <c>Ctrl</c>, but the record is what the panel renders, so this is where
    /// the rule has to hold — same as the <c>init</c> block on the Kotlin side.
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
/// A row of the draft block: the branch, the progress exactly as the CLI
/// reports it, and the controls that act on THAT row.
///
/// One list, two places on the row: the labelled controls are the button pair
/// underneath, and the Icon ones are drawn in the header beside the progress —
/// the pair names their subject, and neither of them moves the flow along. The
/// view splits on the emphasis; the order inside each half is this one.
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
/// A row of the authoring-guide block: which guide it is, the state the CLI
/// reported as a badge, and the controls that act on THAT row.
///
/// Same two-place shape as <see cref="DraftRow"/>: the labelled control is the
/// button underneath and the Icon ones are drawn in the header beside the badge.
/// And the same rule about presence — both rows carry the same controls whatever
/// their state, except Discard, which only the reviewer's own row has at all:
/// the shared guide is a tracked file, so removing it is `git rm` plus a commit.
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
    /// An inventory control is routed back to its row by index, so a control
    /// without one is a button that acts on nothing in particular — the panel
    /// falls back to asking which review, which is not what the reviewer clicked.
    /// <see cref="PanelLayout"/> checks the other direction (an index is only
    /// legal here); this is the forward one.
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
    /// <see cref="GuideRow"/> — name, badge and the controls of that row — the
    /// same way <see cref="WalkthroughRow"/> does: the shape is what a row of
    /// this panel is, and there is nothing about a fixes row the shape does not
    /// already cover.
    /// </summary>
    public sealed record FixesRows(IReadOnlyList<GuideRow> Rows) : Block;

    /// <summary>
    /// The author's own walkthrough, one row, above the guides in the same
    /// section. Drawn only when the CLI reported the record — against an older
    /// version it does not arrive and the block disappears, the same degradation
    /// the guides and the drafts have.
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
        // One PRIMARY per situation, counted over the controls that are NOT row
        // controls. A row control is a per-row affordance repeated as many times
        // as there are rows — "the obvious thing to do with THIS draft" — so
        // counting them here would make the rule depend on how many drafts the
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
        ControlId.StartFromDraft,
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
    /// Whole is the file inventory, and nothing else. The other two clients put an
    /// "open every change at once" button here — VS Code has a multi-diff editor
    /// (<c>vscode.changes</c>) and IntelliJ a <c>DiffRequestChain</c>, so in both it is
    /// one window. Visual Studio's <c>IVsDifferenceService</c> only opens one comparison
    /// window per pair of files, so the same button would open a window per changed file;
    /// a cap on that is still an avalanche. The file rows below open each diff on demand,
    /// which is the same information in the only shape this host can give it well.
    /// Deliberate, and recorded as <c>not_in: [visualstudio]</c> in
    /// <c>contracts/client-product-surface.yaml</c> — reponerlo es editar el contrato.
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
                    "Commit and push them from Source Control. Until you clean up, this is still undoable.",
                },
                new Block.Row(new[]
                {
                    Ctrl(ControlId.CleanReview, "Done, clean up", Emphasis.Primary, enabled),
                    Ctrl(ControlId.UndoFinish, "Undo", Emphasis.Secondary, enabled),
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
    /// The draft block: reading orders the reviewer started and has not paused,
    /// each with its four controls. First block of the empty state, with the
    /// usual body whole underneath — it is not a sub-layout that replaces, the
    /// way the setup gate is: with no base configured there is nothing else to
    /// do in this panel, with a half-written reading order there is.
    /// </summary>
    /// <summary>
    /// The draft rows whose Spent is <paramref name="spent"/>. The index that
    /// travels to the host is the one in the FULL list — it is what resolves
    /// which file is being talked about — so it survives the split into the two
    /// blocks.
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
            // One emphatic control per row, and the progress picks which: while
            // entries are missing the next step is writing the order, and only
            // once it is complete is it starting the review. The ORDER is fixed
            // — moving the click target as the state changes slides it under
            // the cursor.
            //
            // Total == 0 means "this file declares no entry at all", never
            // "complete": the CLI reports 0/0 both for an emptied draft and for
            // the one an agent is writing right now (the watcher fires on the
            // first Changed, before the first "## N." heading lands). Without
            // the Total > 0 the row is drawn as finished and the emphasis goes
            // to Validate and start, which there is usually disabled too
            // (source and range unknown) — the one emphatic control of the row
            // cannot even be clicked, in the very state that most needs Copy
            // for agent to lead.
            var filled = d.Total > 0 && d.Annotated >= d.Total;
            var controls = new List<Control>();
            // A row whose review is over stops here for the pair with labels:
            // they are the flow of writing the order and starting the review,
            // and both already happened. Copy for agent would ask an agent to
            // complete what is complete, and Validate and start would offer to
            // reread a range that closed. The two glyphs below stay in both
            // kinds of row, which is what keeps the collapsed section able to
            // open and to discard.
            if (!spent)
            {
                controls.Add(Ctrl(
                    ControlId.CopyDraftPrompt, "Copy for agent",
                    filled ? Emphasis.Secondary : Emphasis.Primary,
                    enabled: true, tooltip: "Copy an instruction naming this file", index: index));
                // Always drawn, switched off for two different reasons,
                // each of which says its own thing. The flags come first: with
                // no instruction block the build fails on drift however
                // complete the order is, so filling it in is not the next step
                // there.
                //
                // Off by progress is what makes the pair honest. The skeleton
                // leaves a placeholder per entry AND one for the heads-up, the
                // pair counts all of them, and build refuses on any of them
                // alike — left on, the one emphatic control of the row offered
                // a start that died on "the heads-up placeholder is still
                // there". The known cost: the count comes off the disk, so a
                // draft open with unsaved edits keeps the control gray until
                // Ctrl+S (the host watches the draft's directory, so saving
                // refreshes the panel on its own), and in exchange nobody
                // starts over a half-written reading order.
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
                // The two controls of the ROW, and that is why they leave the
                // button pair: they move nothing along, they are used once in a
                // while, and their subject is the file the progress pair just
                // named. They are drawn as glyphs beside that pair, which
                // leaves two controls below in two columns and a single line.
                // With all four together the row was twice as tall and the
                // irreversible one shared box and weight with the one that
                // starts the review — dropping its fill lowered it a step, but
                // a box-less button among boxed buttons reads as disabled. An
                // icon does not.
                //
                // With no visible label the accessible name IS the name of the
                // control, and it names the row: "Open" on its own repeats once
                // per draft.
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
    /// The authoring-guide block, inside the Walkthrough section. Two rows,
    /// always both, whether or not either file exists: what the state changes is
    /// the enabled of each control, never its presence — two rows that build
    /// different button sets do not line up with each other, the same rule the
    /// draft rows follow.
    ///
    /// Discard is the one exception, and it is not forgotten symmetry: the shared
    /// guide is a tracked file, so removing it is `git rm` plus a commit — a
    /// decision about what goes into the PR, which is not this button's to make.
    /// The CLI says the same from its side, refusing `--delete --team`.
    /// </summary>
    /// <summary>
    /// The rows of "Edits you extracted": the branch, its badge and the one
    /// control that makes sense from here. Committing and pushing are Source
    /// Control's, which is where finish already sends you.
    ///
    /// The row you are standing on is drawn just the same and without the
    /// control: the CLI skips it with "skipping (currently checked out)", so
    /// offering the button would promise something that will not happen. Hiding
    /// the row would be worse — it is a branch that exists and no other surface
    /// names.
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
    /// The author's walkthrough row, the first of the section and above the
    /// guides.
    ///
    /// Same two-place shape as the guide rows: the labelled controls underneath,
    /// the icon one in the header beside the badge. What it has that they do not
    /// is the two VERBS — init and build live here and not loose above the row,
    /// because their subject is the file this row names, exactly as Create is
    /// each guide's. Loose, the word "Walkthrough" was said three times running
    /// (the section title, the two prefixed labels and the row's name) without
    /// any of the three adding a fact; hence the labels without a prefix and the
    /// row named after its branch. In the menu and the Tools submenu they keep
    /// the prefix, which is where no section gives context.
    ///
    /// The badge says "may be out of date" and not "out of date" on purpose —
    /// what the CLI compares on every refresh is cheap and approximate (has the
    /// range moved since the file was written), and the exact answer is build's,
    /// which is what the button beside it runs.
    ///
    /// Copy for agent copies a POINTER to the file, never the brief: that lives
    /// inside the walkthrough itself, in the comment at the top, which is where
    /// it keeps itself current.
    /// </summary>
    private static Block.WalkthroughRow WalkthroughRowBlock(PanelWalkthrough w, bool enabled)
    {
        var controls = new List<Control>
        {
            // The same verb creates and updates, so the label follows the state
            // the CLI reported: "Init" over a file full of prose promised what
            // that verb precisely no longer does. Both carry the row's index like
            // every other control of a row — there is exactly one walkthrough
            // row, so it is always 0.
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
        // Only the FRESH ones. A draft whose review is over survives — clean
        // does not touch hand-written prose, and discarding one is the forget
        // verb — but it is no longer pending work, so it drops to its own
        // collapsed section in the footer with the two controls it still has
        // use for.
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
        // Everything about the walkthrough together: the author's file — with
        // init, build and Copy for agent hanging off its row — and the two
        // authoring guides. It shared an "Other actions" section with Compare
        // and split off when the guides arrived: four controls about the same
        // noun plus one unrelated is not a list of other actions, it is a
        // drawer. Grouped this way the panel says what the CLI says, where all
        // four hang off the walkthrough verb.
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
        // The spent drafts. Collapsed and not hidden: a file that exists and no
        // surface names is the state this panel does not let past anywhere else,
        // and hiding the row would take with it the one control that can throw
        // the file away without spelling its branch.
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
        // The branches of edits a finish left behind. Collapsed and behind the
        // spent reading orders: both sections are leftovers of reviews that
        // already happened, and this one goes last because what it holds may
        // still be pending work on ANOTHER screen (committing and pushing are
        // Source Control's), not on this one.
        //
        // "Discard all" runs clean --fixes-only with NO branch: by clean's own
        // design that never touches review/* (live sessions of other branches),
        // so it does not have the reach problem that used to block this button.
        // It is still behind a confirmation with the full detail, because what
        // this holds is hand-written work and not machine litter; the rows below
        // remain the default path for deciding branch by branch.
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
        // Compare, last of the three footer sections that do something with
        // the repo. It is the only one that mounts something OUTSIDE the
        // review you are about to do -- any two revisions, no review to start
        // and no reading order to write -- so it sits below everything that is
        // about that review. It used to be called "Other actions" and came
        // first: a title that did not name its contents, above the two
        // sections that do.
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
