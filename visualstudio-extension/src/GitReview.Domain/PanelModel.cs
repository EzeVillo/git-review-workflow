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
/// A row of the empty state's draft block: a reading order the reviewer started
/// and has not paused. Flat projection, with nothing derived — the progress is
/// counted by the CLI and the path is resolved by the CLI.
///
/// Startable says whether "Validate and start" can be offered: only when the
/// CLI knows the origin and range the draft was generated with. With Unknown
/// (the instruction block was deleted by hand) invoking with the defaults would
/// fail with a drift error every time, so one control fewer beats one that
/// guesses.
/// </summary>
public sealed record PanelDraft(
    string Branch,
    string Path,
    int Annotated,
    int Total,
    bool Startable);

public sealed record PanelModel(
    Situation Situation,
    bool Busy,
    string? RepoLabel = null,
    IReadOnlyList<PanelReview>? Reviews = null,
    /// <summary>
    /// Same rule as Reviews: only with NoReview, empty in any other situation.
    /// A review in progress is always the most important thing the panel has to
    /// say, and another branch's draft does not compete for the body.
    /// </summary>
    IReadOnlyList<PanelDraft>? Drafts = null,
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
        if (entry.Annotated == false) marks.Add("uncovered");
        if (entry.Banked == true) marks.Add("banked edits");
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
                Startable: d.Source != DraftSource.Unknown && d.Range != DraftRange.Unknown));
        }
        return out_;
    }

    /// <summary>
    /// The draft row at index, resolved against the HOST's state. Same role as
    /// ResumableSourceAt: what ends up in the CLI does not come from the panel.
    /// </summary>
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
