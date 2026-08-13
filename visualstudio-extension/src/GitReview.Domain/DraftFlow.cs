namespace GitReview.Domain;

public abstract record DraftFlowState
{
    public sealed record Create : DraftFlowState
    {
        public static readonly Create Instance = new();
    }
    public sealed record Open : DraftFlowState
    {
        public static readonly Open Instance = new();
    }
    public sealed record Wait(string? Error = null) : DraftFlowState;
    public sealed record Build : DraftFlowState
    {
        public static readonly Build Instance = new();
    }
    public sealed record Reload : DraftFlowState
    {
        public static readonly Reload Instance = new();
    }
    public sealed record PickKeys : DraftFlowState
    {
        public static readonly PickKeys Instance = new();
    }
    public sealed record Done(ReviewLayout Layout) : DraftFlowState;
    public sealed record Back(string? Error = null) : DraftFlowState;
}

public abstract record DraftFlowEvent
{
    public sealed record Created(bool Ok, string? Error = null) : DraftFlowEvent;
    public sealed record Opened : DraftFlowEvent
    {
        public static readonly Opened Instance = new();
    }
    public sealed record Continue : DraftFlowEvent
    {
        public static readonly Continue Instance = new();
    }
    public sealed record Cancel : DraftFlowEvent
    {
        public static readonly Cancel Instance = new();
    }
    public sealed record Built(bool Ok, string? Error = null) : DraftFlowEvent;
    public sealed record Offers(IReadOnlyList<ReadingOffer>? Value) : DraftFlowEvent;
    public sealed record KeysPicked(bool? KeysOnly) : DraftFlowEvent;
}

public static class DraftFlow
{
    public static DraftFlowState InitialDraftFlowState(LayoutOffers.DraftStep step) =>
        step == LayoutOffers.DraftStep.Create
            ? DraftFlowState.Create.Instance
            : DraftFlowState.Open.Instance;

    public static DraftFlowState AdvanceDraftFlow(DraftFlowState state, DraftFlowEvent ev) => state switch
    {
        DraftFlowState.Create => ev is DraftFlowEvent.Created c
            ? c.Ok ? DraftFlowState.Open.Instance : new DraftFlowState.Back(c.Error)
            : state,
        DraftFlowState.Open => ev is DraftFlowEvent.Opened
            ? new DraftFlowState.Wait()
            : state,
        DraftFlowState.Wait => ev switch
        {
            DraftFlowEvent.Continue => DraftFlowState.Build.Instance,
            DraftFlowEvent.Cancel => new DraftFlowState.Back(),
            _ => state,
        },
        DraftFlowState.Build => ev is DraftFlowEvent.Built b
            ? b.Ok ? DraftFlowState.Reload.Instance : new DraftFlowState.Wait(b.Error)
            : state,
        DraftFlowState.Reload => ev is DraftFlowEvent.Offers o
            ? OffersIncludeKeys(o.Value)
                ? DraftFlowState.PickKeys.Instance
                : new DraftFlowState.Done(ReviewLayout.Walk)
            : state,
        DraftFlowState.PickKeys => ev is DraftFlowEvent.KeysPicked k
            ? k.KeysOnly switch
            {
                null => new DraftFlowState.Back(),
                true => new DraftFlowState.Done(ReviewLayout.Keys),
                false => new DraftFlowState.Done(ReviewLayout.Walk),
            }
            : state,
        DraftFlowState.Done or DraftFlowState.Back => state,
        _ => state,
    };

    public static bool OffersIncludeKeys(IReadOnlyList<ReadingOffer>? offers) =>
        offers is not null && offers.Any(o => o.Id == OfferId.Keys);

    /// <summary>
    /// Resolves gitdir from a .git file (worktree / submodule): line <c>gitdir: &lt;path&gt;</c>.
    /// </summary>
    public static string? GitdirFromLink(string content)
    {
        var match = System.Text.RegularExpressions.Regex.Match(
            content, @"^gitdir:[ \t]*(.+?)[ \t\r]*$",
            System.Text.RegularExpressions.RegexOptions.Multiline);
        if (!match.Success) return null;
        var path = match.Groups[1].Value;
        return string.IsNullOrEmpty(path) ? null : path;
    }
}
