namespace GitReview.Domain;

public enum WhyState
{
    Loading,
    Present,
    Absent,
    Failed,
}

public static class WhyStateExt
{
    public static string Id(this WhyState s) => s switch
    {
        WhyState.Loading => "loading",
        WhyState.Present => "present",
        WhyState.Absent => "absent",
        WhyState.Failed => "failed",
        _ => throw new ArgumentOutOfRangeException(nameof(s)),
    };
}

public sealed record PanelWhy(WhyState State, string? Text = null);

public sealed record PanelEntry(
    int Position,
    string Display,
    bool Essential,
    bool Annotated,
    bool Banked,
    string? Subject = null,
    string? Author = null);

public sealed record PanelReview(
    string Name,
    bool Saved,
    bool Current,
    bool Orphan,
    ReviewMode? Mode,
    int? Position,
    int? Total,
    bool Resumable,
    BranchFinish? Finish = null);

/// <summary>
/// A row of the empty state's draft block: a reading order the reviewer started and
/// has not paused. Flat projection — progress and path both come from the CLI, nothing
/// derived here.
///
/// Startable says whether "Validate and start" can be <em>invoked</em>: only when the
/// CLI knows the origin and range the draft was generated with. With Unknown (the
/// instruction block was deleted by hand) invoking with the defaults would fail with a
/// drift error every time. The control is drawn either way but switched off — it still
/// can't be invoked, but unlike an absent control it can say why in its tooltip, and
/// the row keeps its four cells so it doesn't change shape with its state.
///
/// Spent says whether its review is over. A draft outlives the review it was written
/// for — clean doesn't touch hand-written prose — but it stops being work in progress,
/// so it moves to a collapsed section with just open and discard. The CLI decides it;
/// nothing is inferred here.
/// </summary>
public sealed record PanelDraft(
    string Branch,
    string Path,
    int Annotated,
    int Total,
    bool Startable,
    bool Spent);

/// <summary>
/// A row of the authoring-guide block: prose about the CONTENT of a walkthrough, not
/// its format.
///
/// BOTH rows are always drawn, whether or not either file exists — state changes the
/// controls' enabled, never their presence, same rule as the draft rows and for the
/// same reason: two rows with different button sets don't line up.
///
/// Name and badge are derived here since they're panel copy; Path comes from the CLI,
/// which the client opens and never rebuilds.
///
/// Discardable is yours only: the shared guide is a tracked file, so removing it is
/// `git rm` plus a commit — a decision about what goes into the PR, not this button's
/// to make. The CLI refuses `--delete --team` for the same reason.
/// </summary>
public sealed record PanelGuide(
    GuideKind Kind,
    string Label,
    string Path,
    GuideState State,
    string Badge,
    bool Exists,
    bool Discardable);

/// <summary>
/// A row of the "Edits you extracted" section: a review-fixes/ branch a finish
/// left behind (<c>fixes</c> record of <c>list --porcelain</c>).
///
/// Flat projection, not one derivation: how much dropping it costs is answered
/// by the CLI, which is the one that can ask git. Current is the branch you are
/// on -- clean skips it, so no control is offered. Session says review/&lt;x&gt;
/// still exists, and it changes the confirmation copy, never the argv.
/// </summary>
public sealed record PanelFixes(
    string Name,
    bool Current,
    bool Session,
    FixesState State,
    string Badge);

/// <summary>
/// The author's own walkthrough row: what state it is in, how much of it is
/// written, and what can be done with it without leaving the panel.
///
/// It exists because a walkthrough is written once, when the PR is finished, and
/// then the PR keeps moving. The row is the only surface that says so without
/// anybody remembering to ask, which is why the badge is deliberately cautious:
/// "may be out of date" and not "out of date". The exact answer is build's,
/// which is what the button beside it runs.
///
/// Label, Badge and ActionLabel are panel copy and are derived here; Path comes
/// from the CLI, and the client opens it, never rebuilds it.
/// </summary>
public sealed record PanelWalkthrough(
    string Label,
    string Path,
    WalkthroughState State,
    string Badge,
    int Annotated,
    int Total,
    bool Exists,
    /// <summary>
    /// What the control that invokes `walkthrough init` is called — the same verb
    /// creates AND updates, so the only thing that changes is its name.
    /// </summary>
    string ActionLabel);

public sealed record PanelModel(
    Situation Situation,
    bool Busy,
    string? RepoLabel = null,
    IReadOnlyList<PanelReview>? Reviews = null,
    /// <summary>
    /// Only populated in NoReview, empty otherwise: a review in progress is the most
    /// important thing the panel has to say, and another branch's draft does not
    /// compete for the body.
    /// </summary>
    IReadOnlyList<PanelDraft>? Drafts = null,
    /// <summary>
    /// Both authoring guides, in the CLI's order (shared, yours). Only in NoReview:
    /// inside a review the panel has more urgent things to say, and creating the
    /// shared one there is refused by the CLI anyway.
    /// </summary>
    IReadOnlyList<PanelGuide>? Guides = null,
    /// <summary>
    /// The branches of edits a finish left behind, in the CLI's order. Only in
    /// NoReview, where the footer section lives.
    /// </summary>
    IReadOnlyList<PanelFixes>? Fixes = null,
    /// <summary>
    /// The author's walkthrough, when the CLI reported its row. Null against a
    /// CLI older than the record, and then the block is not drawn.
    /// </summary>
    PanelWalkthrough? Walkthrough = null,
    PendingFinish? PendingFinish = null,
    bool NoBaseConfigured = false,
    string? ConfiguredBase = null,
    string? ConfiguredRemote = null,
    ReviewMode? Mode = null,
    string? Branch = null,
    string? Source = null,
    string? Tip = null,
    string? Base = null,
    int? Position = null,
    int? Total = null,
    bool BaseMoved = false,
    bool AtFirst = false,
    bool AtLast = false,
    bool NavigationLocked = false,
    bool Degraded = false,
    bool Readonly = false,
    bool KeysOnly = false,
    bool Draft = false,
    PanelEntry? Current = null,
    int EntryCount = 0,
    IReadOnlyList<PanelEntry>? Files = null,
    string? LastOpened = null,
    PanelWhy? Why = null,
    string? Stderr = null)
{
    public IReadOnlyList<PanelReview> ReviewsList => Reviews ?? Array.Empty<PanelReview>();
    public IReadOnlyList<PanelDraft> DraftsList => Drafts ?? Array.Empty<PanelDraft>();
    public IReadOnlyList<PanelGuide> GuidesList => Guides ?? Array.Empty<PanelGuide>();
    public IReadOnlyList<PanelFixes> FixesList => Fixes ?? Array.Empty<PanelFixes>();
    public IReadOnlyList<PanelEntry> FilesList => Files ?? Array.Empty<PanelEntry>();
}

public sealed record PendingFinish(string Branch, bool Onto);

public sealed record PanelInputs(
    bool Busy,
    string? RepoLabel = null,
    PanelWhy? Why = null,
    string? LastOpened = null);

public sealed record PickLabel(string Label, string Description);

public static class PanelModelBuilder
{
    private static string DisplayOf(object id) => id switch
    {
        PathRef pr => pr.Display,
        string s => s,
        _ => id.ToString() ?? "",
    };

    private static PanelEntry ToPanelEntry(
        EntryRecord entry,
        IReadOnlyDictionary<int, string>? subjects,
        IReadOnlyDictionary<int, string>? authors) =>
        new(
            entry.Position,
            DisplayOf(entry.Id),
            entry.Essential == true,
            entry.Annotated != false,
            entry.Banked == true,
            subjects is not null && subjects.TryGetValue(entry.Position, out var subj) ? subj : null,
            authors is not null && authors.TryGetValue(entry.Position, out var auth) ? auth : null);

    private static string Pad(int position) =>
        position < 10 ? $"0{position}" : position.ToString();

    public static PickLabel EntryPickLabel(EntryRecord entry, int? position, string? subject)
    {
        var marks = new List<string>();
        if (entry.Position == position) marks.Add("current");
        if (entry.Essential == true) marks.Add("key");
        if (entry.Annotated == false) marks.Add("not covered");
        if (entry.Banked == true) marks.Add("saved edits");
        var id = DisplayOf(entry.Id);
        var label = !string.IsNullOrEmpty(subject)
            ? $"{Pad(entry.Position)}  {id}  {subject}"
            : $"{Pad(entry.Position)}  {id}";
        return new PickLabel(label, string.Join(" · ", marks));
    }

    public static EntryRecord? CurrentEntry(IReadOnlyList<EntryRecord> entries, int? position)
    {
        if (position is null) return null;
        return entries.FirstOrDefault(e => e.Position == position);
    }

    private static IReadOnlyList<PanelReview> ToPanelReviews(IReadOnlyList<BranchRecord> branches)
    {
        var active = branches.Where(b => !b.Saved).Select(Porcelain.SourceOf).ToHashSet();
        return branches.Select(branch => new PanelReview(
            Name: branch.Name,
            Saved: branch.Saved,
            Current: branch.Current,
            Orphan: branch.Orphan,
            Mode: branch.Mode,
            Position: branch.Position is not null && branch.Total is not null ? branch.Position : null,
            Total: branch.Position is not null && branch.Total is not null ? branch.Total : null,
            Resumable: branch.Saved && !branch.Orphan && !active.Contains(Porcelain.SourceOf(branch)),
            Finish: branch.Finish)).ToList();
    }

    /// <summary>
    /// Projects the `draft` records of `config --porcelain`, one to one and in
    /// the CLI's order. A paused review's draft never gets here — the CLI does
    /// not report it, because save moved its file to the archived namespace.
    /// </summary>
    public static IReadOnlyList<PanelDraft> ToPanelDrafts(IReadOnlyList<DraftRecord> drafts)
    {
        var out_ = new List<PanelDraft>(drafts.Count);
        foreach (var d in drafts)
        {
            out_.Add(new PanelDraft(
                Branch: d.Src,
                Path: d.Path,
                Annotated: d.Annotated,
                Total: d.Total,
                Startable: d.Source != DraftSource.Unknown && d.Range != DraftRange.Unknown,
                Spent: d.State == DraftState.Reviewed));
        }
        return out_;
    }

    /// <summary>
    /// The badge of a fixes row: what dropping it costs, one phrase per state, none
    /// folding into another — checked against the canonical contract.
    /// </summary>
    public static string FixesBadge(FixesState state) => state switch
    {
        FixesState.Empty => "empty",
        FixesState.Merged => "merged",
        FixesState.Unmerged => "unmerged",
        _ => "unknown",
    };

    public static IReadOnlyList<PanelFixes> ToPanelFixes(IReadOnlyList<FixesRecord> fixes)
    {
        var out_ = new List<PanelFixes>(fixes.Count);
        foreach (var f in fixes)
        {
            out_.Add(new PanelFixes(
                Name: f.Name,
                Current: f.Current,
                Session: f.Session,
                State: f.State,
                Badge: FixesBadge(f.State)));
        }
        return out_;
    }

    /// <summary>The row at index of the fixes section, or null (same guard as GuideAt).</summary>
    public static FixesRecord? FixesAt(IReadOnlyList<FixesRecord> fixes, object? index)
    {
        if (index is not int i) return null;
        if (i < 0 || i >= fixes.Count) return null;
        return fixes[i];
    }

    /// <summary>
    /// The badge for each state: two are the CLI's values; `absent` reads
    /// "none", because "empty" and "absent" look like synonyms at a glance and are
    /// not -- `empty` is "the file is there, it says nothing" and `absent` is "there
    /// is no file", which is what decides whether the button beside it opens or
    /// creates.
    /// </summary>
    private static string GuideBadge(GuideState state) => state switch
    {
        GuideState.InForce => "in force",
        GuideState.Empty => "empty",
        _ => "none",
    };

    private static string GuideLabel(GuideKind kind) =>
        kind == GuideKind.Team ? "Repository guide" : "Your guide";

    /// <summary>
    /// Projects the `guide` records, one to one and in the CLI's order, without
    /// filling in a missing one: a record that did not arrive is a row that is
    /// not drawn. Against a CLI that does not know the record none arrive and the
    /// whole block disappears, the same degradation the draft block has.
    /// </summary>
    public static IReadOnlyList<PanelGuide> ToPanelGuides(IReadOnlyList<GuideRecord> guides)
    {
        var out_ = new List<PanelGuide>(guides.Count);
        foreach (var g in guides)
        {
            out_.Add(new PanelGuide(
                Kind: g.Kind,
                Label: GuideLabel(g.Kind),
                Path: g.Path,
                State: g.State,
                Badge: GuideBadge(g.State),
                Exists: g.State != GuideState.Absent,
                Discardable: g.Kind == GuideKind.Own && g.State != GuideState.Absent));
        }
        return out_;
    }

    private static string WalkthroughBadge(WalkthroughState state) => state switch
    {
        WalkthroughState.InSync => "up to date",
        WalkthroughState.Stale => "may be out of date",
        WalkthroughState.Superseded => "from a merged PR",
        WalkthroughState.Unknown => "state unknown",
        _ => "none",
    };

    /// <summary>
    /// Projects the `walkthrough` record. One row, ALWAYS: init and build are this
    /// row's buttons, so drawing it only sometimes would leave them without a
    /// surface. With no record — malformed, or a CLI too old for it — the row
    /// arrives as Unknown, the state the CLI defines as "the question has no
    /// answer": no badge, no path invented.
    ///
    /// Named after the BRANCH it annotates, not "Walkthrough": the section already
    /// has that name, and saying it twice adds nothing.
    ///
    /// Everything pressable comes from the CLI-reported state. The action label
    /// isn't keyed on staleness (see field doc above) — "Create" over a file full
    /// of prose would be a promise the CLI doesn't keep.
    /// </summary>
    public static PanelWalkthrough ToPanelWalkthrough(WalkthroughRecord? record)
    {
        // Empty path also turns off the two controls that need a file.
        var state = record?.State ?? WalkthroughState.Unknown;
        return new PanelWalkthrough(
            Label: record?.Branch ?? "Walkthrough",
            Path: record?.Path ?? string.Empty,
            State: state,
            Badge: WalkthroughBadge(state),
            Annotated: record?.Annotated ?? 0,
            Total: record?.Total ?? 0,
            Exists: record is not null && state != WalkthroughState.Absent,
            // Three labels for one verb. Superseded isn't a flavour of "fell behind":
            // the file belongs to another PR, and the CLI starts over on its own
            // there — so the button says what will happen rather than promising a
            // reconciliation that won't occur. With no record at all, the button
            // keeps the verb's default name.
            ActionLabel: record is null
                ? "Create"
                : state switch
                {
                    WalkthroughState.Absent => "Create",
                    WalkthroughState.Superseded => "Start over",
                    _ => "Update",
                });
    }

    /// <summary>
    /// The guide row at index, resolved against the HOST's state. Same role as
    /// DraftAt: what ends up in the CLI does not come from the panel.
    /// </summary>
    public static GuideRecord? GuideAt(IReadOnlyList<GuideRecord> guides, object? index)
    {
        if (index is not int i) return null;
        if (i < 0 || i >= guides.Count) return null;
        return guides[i];
    }

    /// <summary>The draft row at index, resolved against the HOST's state — same role as GuideAt.</summary>
    public static DraftRecord? DraftAt(IReadOnlyList<DraftRecord> drafts, object? index)
    {
        if (index is not int i) return null;
        if (i < 0 || i >= drafts.Count) return null;
        return drafts[i];
    }

    public static string? ResumableSourceAt(IReadOnlyList<BranchRecord> branches, object? index)
    {
        if (index is not int i) return null;
        if (i < 0 || i >= branches.Count) return null;
        var branch = branches[i];
        var reviews = ToPanelReviews(branches);
        if (i >= reviews.Count) return null;
        if (!reviews[i].Resumable) return null;
        return Porcelain.SourceOf(branch);
    }

    public static PanelModel BuildPanelModel(ReviewState state, PanelInputs inputs)
    {
        var model = new PanelModel(
            Situation: state.Situation,
            Busy: inputs.Busy,
            Reviews: state.Situation == Situation.NoReview
                ? ToPanelReviews(state.BranchesList)
                : Array.Empty<PanelReview>(),
            Drafts: state.Situation == Situation.NoReview
                ? ToPanelDrafts(state.DraftsList)
                : Array.Empty<PanelDraft>(),
            // Only outside a review: the footer is where they are drawn, and a review
            // has no footer (see CLAUDE.md, "Una review no tiene pie").
            Guides: ToPanelGuides(state.GuidesList),
            // Only in NoReview, like the rest of the footer. One by one, in the CLI's
            // order, with nothing filtered or reordered — not even Current, the one
            // row that can't be deleted: hiding it would leave a branch with no
            // surface naming it, exactly what this section exists to fix.
            Fixes: state.Situation == Situation.NoReview
                ? ToPanelFixes(state.FixesList)
                : Array.Empty<PanelFixes>(),
            // Only in NoReview. Built even when the record is missing — see
            // ToPanelWalkthrough.
            Walkthrough: state.Situation == Situation.NoReview
                ? ToPanelWalkthrough(state.Walkthrough)
                : null,
            NoBaseConfigured: state.Situation == Situation.NoReview
                && state.Config is not null
                && state.Config.Base is null,
            NavigationLocked: state.Situation == Situation.FinishConflict,
            RepoLabel: inputs.RepoLabel,
            Stderr: string.IsNullOrWhiteSpace(state.Stderr) ? null : state.Stderr);

        if (state.Situation == Situation.NoReview && state.Config is not null)
        {
            model = model with
            {
                ConfiguredRemote = state.Config.Remote,
                ConfiguredBase = state.Config.Base,
            };
        }

        if (state.Situation == Situation.FinishPending)
        {
            var pending = state.BranchesList.FirstOrDefault(b => b.Finish?.State == "pending");
            if (pending?.Finish is not null)
            {
                model = model with
                {
                    PendingFinish = new PendingFinish(pending.Name, pending.Finish.Onto),
                };
            }
        }

        var review = state.State;
        if ((state.Situation is not Situation.Review and not Situation.FinishConflict) || review is null)
            return model;

        model = model with
        {
            Mode = review.Mode,
            Branch = review.Branch,
            Source = review.Source,
            Tip = review.Tip,
            Degraded = review.Walkthrough == WalkthroughStatus.Degraded,
            Readonly = state.Readonly == true,
            KeysOnly = state.KeysOnly == true,
            Draft = state.Draft == true,
            EntryCount = state.EntriesList.Count,
        };

        if (review.Mode == ReviewMode.Whole)
        {
            var files = state.EntriesList.Select(e => ToPanelEntry(e, state.Subjects, state.Authors)).ToList();
            var lastOpened = inputs.LastOpened is not null && files.Any(f => f.Display == inputs.LastOpened)
                ? inputs.LastOpened
                : null;
            return model with
            {
                Base = state.Base,
                Files = files,
                LastOpened = lastOpened,
            };
        }

        var atFirst = review.Position is not null && review.Position <= 1;
        var atLast = review.Position is not null && review.Total is not null && review.Position >= review.Total;
        if (model.NavigationLocked)
        {
            atFirst = false;
            atLast = false;
        }

        var current = CurrentEntry(state.EntriesList, review.Position);
        var stepFiles = review.Mode == ReviewMode.Step
            ? state.FilesList.Select(e => ToPanelEntry(e, state.Subjects, state.Authors)).ToList()
            : (IReadOnlyList<PanelEntry>)Array.Empty<PanelEntry>();
        var stepLastOpened = review.Mode == ReviewMode.Step && inputs.LastOpened is not null
                             && stepFiles.Any(f => f.Display == inputs.LastOpened)
            ? inputs.LastOpened
            : null;

        model = model with
        {
            Position = review.Position,
            Total = review.Total,
            BaseMoved = review.Recorded is not null && review.Total is not null && review.Total < review.Recorded,
            AtFirst = atFirst,
            AtLast = atLast,
            Current = current is not null ? ToPanelEntry(current, state.Subjects, state.Authors) : null,
            Files = stepFiles,
            LastOpened = stepLastOpened,
            Why = review.Mode == ReviewMode.Walk && current is not null
                ? inputs.Why ?? new PanelWhy(WhyState.Loading)
                : null,
        };
        return model;
    }
}
