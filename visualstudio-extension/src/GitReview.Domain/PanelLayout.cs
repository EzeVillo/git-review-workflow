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
        string? supportLinkId = null,
        bool separated = false)
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
        Separated = separated;
    }

    public ControlId Id { get; init; }
    public string? Label { get; init; }
    public string AccessibleName { get; init; }
    public Emphasis Emphasis { get; init; }
    public bool Enabled { get; init; }
    public string? Tooltip { get; init; }
    public int? Index { get; init; }
    public string? SupportLinkId { get; init; }

    /// <summary>
    /// A gap wider than the one between controls, before this one. The only
    /// irreversible control of a row carries it so that it does not share an
    /// edge with the one that commits; the canonical declares it as
    /// <c>separated: true</c>.
    /// </summary>
    public bool Separated { get; init; }
}

public sealed record FileRow(string Display, int Index, bool LastOpened);

/// <summary>
/// A row of the draft block: the branch, the progress exactly as the CLI
/// reports it, and the controls that act on THAT row.
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
                case Block.ToolsSection ts: Walk(ts.NestedBlocks, outList); break;
            }
        }
    }

    private static bool HostedByInventory(IReadOnlyList<Block> blocks, Control c) =>
        blocks.Any(b => b switch
        {
            Block.InventoryRows ir => ir.Rows.Any(r => r.Controls.Any(x => ReferenceEquals(x, c) || x == c)),
            Block.DraftRows dr => dr.Rows.Any(r => r.Controls.Any(x => ReferenceEquals(x, c) || x == c)),
            Block.ToolsSection ts => HostedByInventory(ts.NestedBlocks, c),
            _ => false,
        });
}

public static class PanelLayoutBuilder
{
    private static readonly HashSet<ControlId> ConfirmingIds = new()
    {
        ControlId.StartReview,
        ControlId.ContinueReview,
        ControlId.DiscardInventory,
        ControlId.StartFromDraft,
        ControlId.DiscardDraft,
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
        string? supportLinkId = null,
        bool separated = false)
    {
        // The two rules live on the record itself; this only fills in the name a
        // labelled control gets for free.
        var name = accessibleName ?? label ?? id.Wire();
        return new Control(id, label, name, emphasis, enabled, tooltip, index, supportLinkId, separated);
    }

    private static string? TipShort(string? tip) =>
        tip is null ? null : tip.Length <= 7 ? tip : tip.Substring(0, 7);

    private static string? EntryBadge(PanelEntry entry, ReviewMode? mode)
    {
        if (entry.Essential) return "key";
        if (mode == ReviewMode.Walk && !entry.Annotated) return "uncovered";
        if (entry.Banked) return "edits";
        return null;
    }

    private static string InventoryMeta(PanelReview r)
    {
        if (r.Orphan) return "no metadata";
        if (r.Position is not null && r.Total is not null)
            return $"{(r.Mode?.Id() ?? "?")} · {r.Position}/{r.Total}";
        if (r.Mode is not null) return r.Mode.Value.Id();
        return "no metadata";
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
                    $"Finished. Your edits are staged on {destination}.",
                    "Commit and push them from Source Control. The review branch is kept so you can undo with git review finish --abort, or clean --keep-fixes when you no longer need the undo.",
                },
                new Block.Row(new[]
                {
                    Ctrl(ControlId.CleanReview, "Clean", Emphasis.Primary, enabled),
                    Ctrl(ControlId.UndoFinish, "Undo finish", Emphasis.Secondary, enabled),
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
            new Block.Paragraph("Configure git review for this repository."),
            new Block.Row(new[] { Ctrl(ControlId.SetBase, "Set the base branch", Emphasis.Primary, enabled) }),
            new Block.Paragraph(
                "The base is where PRs land in this repo (main, develop, …). Full reviews compare the branch under review against it."),
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
            if (r.Orphan) badges.Add("orphan");
            var canDiscard = r.Saved || r.Orphan;
            var controls = new List<Control>();
            if (canDiscard)
            {
                if (r.Saved)
                {
                    string? tip = null;
                    if (!r.Resumable)
                        tip = r.Orphan
                            ? "This branch has no review metadata — use Discard"
                            : "A review of this branch is already active";
                    controls.Add(Ctrl(
                        ControlId.ContinueReview, "Continue", Emphasis.Secondary,
                        enabled: enabled && r.Resumable, tooltip: tip, index: index));
                }
                var discardLabel = r.Orphan ? "Discard orphan" : "Discard";
                var discardTip = r.Saved
                    ? "git review forget --saved (with confirmation)"
                    : "git review clean (with confirmation)";
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
    private static Block.DraftRows DraftRows(PanelModel model)
    {
        var enabled = !model.Busy;
        var rows = model.DraftsList.Select((d, index) =>
        {
            // One emphatic control per row, and the progress picks which: while
            // entries are missing the next step is writing the order, and only
            // once it is complete is it starting the review. The ORDER is fixed
            // — moving the click target as the state changes slides it under
            // the cursor.
            var filled = d.Annotated >= d.Total;
            var controls = new List<Control>
            {
                Ctrl(
                    ControlId.CopyDraftPrompt, "Copy for agent",
                    filled ? Emphasis.Secondary : Emphasis.Primary,
                    enabled: true, tooltip: "Copy an instruction naming this file", index: index),
                // Always drawn, switched off when the CLI does not know the
                // origin and range the draft was generated with: invoking with
                // the defaults would fail with a drift error every time. Off
                // says as little about the flags as absent did, and unlike
                // absent it can say why. Never disabled by the progress: the
                // count comes off the disk and the draft can be open with
                // unsaved edits, which the client saves before it validates.
                Ctrl(
                    ControlId.StartFromDraft, "Validate and start",
                    filled ? Emphasis.Primary : Emphasis.Secondary,
                    enabled: enabled && d.Startable,
                    tooltip: d.Startable
                        ? "git review walkthrough draft --build, then start"
                        : "This draft has no instruction block, so the CLI cannot tell how it was generated",
                    index: index),
                // An icon: the draft lives outside the versioned tree and this
                // control is the one surface that opens it, but its label was
                // what forced the row to wrap.
                Ctrl(
                    ControlId.OpenDraft, null, Emphasis.Icon,
                    enabled: true,
                    accessibleName: "Open the reading order",
                    tooltip: "Open the reading order for editing",
                    index: index),
            };
            controls.Add(Ctrl(
                ControlId.DiscardDraft, "Discard", Emphasis.Secondary,
                enabled: enabled,
                tooltip: "git review forget --draft (with confirmation)",
                index: index,
                separated: true));
            return new DraftRow(d.Branch, $"{d.Annotated}/{d.Total}", controls);
        }).ToList();
        return new Block.DraftRows(rows);
    }

    private static List<Block> NoReviewReadyBlocks(PanelModel model)
    {
        var enabled = !model.Busy;
        var outList = new List<Block>();
        if (model.DraftsList.Count > 0)
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
            Separated: model.ReviewsList.Count > 0 || model.DraftsList.Count > 0));
        outList.Add(new Block.Row(new[]
        {
            Ctrl(ControlId.StartReview, "Start a review", Emphasis.Primary, enabled),
        }));
        outList.Add(new Block.ToolsSection(
            "Other actions",
            new Block[]
            {
                new Block.Row(new[] { Ctrl(ControlId.CompareReview, "Compare revisions", Emphasis.Secondary, enabled) }),
                new Block.Row(new[]
                {
                    Ctrl(ControlId.WalkthroughInit, "Walkthrough: Init", Emphasis.Secondary, enabled),
                    Ctrl(ControlId.WalkthroughBuild, "Walkthrough: Build", Emphasis.Secondary, enabled),
                }),
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
