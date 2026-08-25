namespace GitReview.Domain;

public static class LayoutOffers
{
    public static readonly IReadOnlyList<ReadingOffer> FallbackOffers = new[]
    {
        new ReadingOffer(OfferId.Step, OfferRank.Available),
        new ReadingOffer(OfferId.Whole, OfferRank.Available),
    };

    /// <summary>
    /// Update and StartOver are the two ways out of the picker that appears when
    /// the reading order has already been used in a review. Update is the SAME
    /// command as Create — the verb reconciles instead of refusing — and StartOver
    /// is that command with --force.
    /// </summary>
    public enum DraftStep
    {
        Create,
        Resume,
        Update,
        StartOver,
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
        [OfferId.Step] = new("Commit by commit", "one commit at a time (--step)", ReviewLayout.Step),
        [OfferId.Whole] = new("Whole diff", "entire diff at once", ReviewLayout.Whole),
    };

    private static readonly OfferId[] OfferOrder =
    {
        OfferId.Walk, OfferId.Keys, OfferId.Draft, OfferId.DraftResume, OfferId.Step, OfferId.Whole,
    };

    public static IReadOnlyList<ReadingOffer> EffectiveOffers(IReadOnlyList<ReadingOffer>? offers) =>
        offers is null || offers.Count == 0 ? FallbackOffers.ToList() : offers;

    /// <summary>
    /// What the draft row says once its review is over. The usual copy describes
    /// a half-written order, and over one that is finished and already used it is
    /// simply false: what is left is not finishing it but reconciling it with what
    /// the PR changed since, or starting a new one.
    /// </summary>
    private static readonly OfferMeta SpentResumeMeta = new(
        "Reuse the reading order you wrote",
        "you already reviewed with it; update it for what changed, or start over",
        ReviewLayout.Walk,
        DraftStep.Resume);

    /// <param name="spentDraft">
    /// Whether this branch's draft has its review closed, which is the only thing
    /// that changes the DraftResume copy. The CLI says so in the draft record's
    /// state field; nothing is derived here.
    /// </param>
    public static IReadOnlyList<LayoutPickItem> BuildLayoutItems(
        IReadOnlyList<ReadingOffer>? offers,
        bool spentDraft = false)
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
            var meta = id == OfferId.DraftResume && spentDraft
                ? SpentResumeMeta
                : OfferMetaMap[id];
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
