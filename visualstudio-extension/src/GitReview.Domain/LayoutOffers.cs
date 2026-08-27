namespace GitReview.Domain;

public static class LayoutOffers
{
    public static readonly IReadOnlyList<ReadingOffer> FallbackOffers = new[]
    {
        new ReadingOffer(OfferId.Step, OfferRank.Available),
        new ReadingOffer(OfferId.Whole, OfferRank.Available),
    };

    /// <summary>
    /// Update is the path the CLI points at when the reading order fell behind
    /// the range: the SAME command as Create — the verb reconciles instead of
    /// refusing — keeping every entry whose file is still in range and adding the
    /// ones that came in.
    /// </summary>
    public enum DraftStep
    {
        Create,
        Resume,
        Update,
    }

    public sealed record LayoutPickItem(
        string Label,
        string Description,
        ReviewLayout Layout,
        DraftStep? Draft = null);

    private sealed record OfferMeta(
        string Label,
        string Description,
        ReviewLayout Layout,
        DraftStep? Draft = null);

    private static readonly Dictionary<OfferId, OfferMeta> OfferMetaMap = new()
    {
        [OfferId.Walk] = new("Walkthrough", "guided reading order from the PR", ReviewLayout.Walk),
        [OfferId.Keys] = new("Walkthrough — keys only", "only entries marked key", ReviewLayout.Keys),
        // Without the word "walkthrough" as if it were a known term: these two
        // are the only offers that do not pick a way to read but build the one
        // the PR does not carry, and whoever reads them does not know yet what a
        // walkthrough is. Byte for byte identical in the three clients.
        [OfferId.Draft] = new("Build a reading order first", "nobody wrote one for this PR; otherwise you read the whole diff", ReviewLayout.Walk, DraftStep.Create),
        [OfferId.DraftResume] = new("Finish the reading order you started", "pick up the one you left half-written", ReviewLayout.Walk, DraftStep.Resume),
        // The CLI sends this one INSTEAD of DraftResume once the draft has
        // fallen behind the range. The two situations used to arrive
        // indistinguishable and the wizard asked with a modal which one it was
        // -- that is, it asked the reviewer for a datum only the CLI holds, and
        // when the answer was "nothing moved" the reconcile was a no-op that
        // landed on a row with no Validate and start.
        [OfferId.DraftUpdate] = new("Update the reading order you wrote", "the PR moved on; keeps the whys whose files are still in range", ReviewLayout.Walk, DraftStep.Update),
        [OfferId.Step] = new("Commit by commit", "one commit at a time", ReviewLayout.Step),
        [OfferId.Whole] = new("Whole diff", "entire diff at once", ReviewLayout.Whole),
    };

    private static readonly OfferId[] OfferOrder =
    {
        OfferId.Walk, OfferId.Keys, OfferId.Draft, OfferId.DraftResume, OfferId.DraftUpdate,
        OfferId.Step, OfferId.Whole,
    };

    public static IReadOnlyList<ReadingOffer> EffectiveOffers(IReadOnlyList<ReadingOffer>? offers) =>
        offers is null || offers.Count == 0 ? FallbackOffers.ToList() : offers;

    /// <summary>
    /// Which of the two draft rows is drawn is no longer decided here: the CLI
    /// sends DraftResume or DraftUpdate and each carries its own fixed copy.
    ///
    /// This used to read the draft record's state to rewrite the DraftResume copy
    /// once the review had closed. That field answers "has this order been read?",
    /// not "does it still cover the range?", so a branch that moved after its
    /// review and one that never moved arrived with the SAME reviewed -- and the
    /// row ended up offering to reconcile an order with nothing to reconcile.
    /// </summary>
    public static IReadOnlyList<LayoutPickItem> BuildLayoutItems(
        IReadOnlyList<ReadingOffer>? offers)
    {
        var list = EffectiveOffers(offers);
        var byId = new Dictionary<OfferId, OfferRank>();
        foreach (var o in list) byId[o.Id] = o.Rank;

        var ordered = new List<OfferId>();
        foreach (var id in OfferOrder)
            if (byId.TryGetValue(id, out var rank) && rank == OfferRank.Recommended)
                ordered.Add(id);
        foreach (var id in OfferOrder)
            if (byId.ContainsKey(id) && byId[id] != OfferRank.Recommended)
                ordered.Add(id);

        return ordered.Select(id =>
        {
            var meta = OfferMetaMap[id];
            var rank = byId.GetValueOrDefault(id, OfferRank.Available);
            var description = rank == OfferRank.Recommended
                ? $"{meta.Description} (recommended)"
                : meta.Description;
            var label = rank == OfferRank.Recommended
                ? $"{meta.Label} (recommended)"
                : meta.Label;
            return new LayoutPickItem(label, description, meta.Layout, meta.Draft);
        }).ToList();
    }

    public static string LayoutSummary(ReviewLayout layout) => layout switch
    {
        ReviewLayout.Walk => "as a walkthrough",
        ReviewLayout.Keys => "keys only",
        ReviewLayout.Step => "commit by commit",
        ReviewLayout.Whole => "as the whole diff",
        _ => "",
    };

    public static IReadOnlyList<string> OfferConfigFlags(ReviewSource source, ReviewRange range)
    {
        var flags = new List<string>();
        switch (source)
        {
            case ReviewSource.Local: flags.Add("--local"); break;
            case ReviewSource.Offline: flags.Add("--offline"); break;
        }
        if (range == ReviewRange.Delta) flags.Add("--delta");
        return flags;
    }
}
