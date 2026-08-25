using Xunit;

namespace GitReview.Domain.Tests;

public class ConfigPorcelainTests
{
    private static string Lines(params string[] lines) => string.Join("\n", lines);

    [Fact]
    public void Parse_full()
    {
        var text = Lines(
            "config\tbase\tmain",
            "config\tremote\torigin",
            "candidate\tfeature\tremote\t1",
            "candidate\tfeature\tlocal\t0",
            "remote-candidate\torigin\t1",
            "delta\tfeature\tabc\tremote",
            "offer\twalk\trecommended",
            "offer\tstep\tavailable");
        var r = ConfigPorcelain.ParseConfigPorcelain(text);
        Assert.Equal("main", r.Config.Base);
        Assert.Equal("origin", r.Config.Remote);
        Assert.Equal(2, r.Candidates.Count);
        Assert.Single(r.Remotes);
        Assert.True(r.Remotes[0].Current);
        Assert.Single(r.Deltas!);
        Assert.Equal(2, r.Offers!.Count);
        Assert.Equal("abc", ConfigPorcelain.DeltaForSource(r.Deltas, "remote")?.Tip);
        Assert.Null(ConfigPorcelain.DeltaForSource(r.Deltas, "local"));
    }

    [Fact]
    public void Remote_defaults_to_origin_and_base_stays_unset()
    {
        var r = ConfigPorcelain.ParseConfigPorcelain("");
        Assert.Equal("origin", r.Config.Remote);
        Assert.Null(r.Config.Base);
        Assert.Empty(r.Candidates);
        Assert.Empty(r.Remotes);
        // Absent, not empty: the panel distinguishes "none reported" from "none exist".
        Assert.Null(r.Deltas);
        Assert.Null(r.Offers);
    }

    [Fact]
    public void Malformed_records_are_dropped_not_half_read()
    {
        var text = Lines(
            "config\tremote\torigin",
            "candidate\tfeature\telsewhere\t1",   // origin is neither remote nor local
            "remote-candidate\t\t1",              // no name
            "delta\tfeature\tabc\tsideways",      // unknown origin
            "delta\tfeature\tabc",                // no origin at all
            "offer\twalk\tmandatory");            // unknown rank
        var r = ConfigPorcelain.ParseConfigPorcelain(text);
        Assert.Empty(r.Candidates);
        Assert.Empty(r.Remotes);
        Assert.Null(r.Deltas);
        Assert.Null(r.Offers);
    }

    /// <summary>
    /// Pins a shared quirk rather than this client's own: a <c>candidate</c> is gated
    /// on its origin field, so an empty name survives, while <c>remote-candidate</c>
    /// is gated on the name and drops. All three clients read it the same way (the
    /// CLI never emits either), so this is here to catch a port drifting from the
    /// other two, not to bless the asymmetry.
    /// </summary>
    [Fact]
    public void A_nameless_candidate_survives_and_a_nameless_remote_does_not()
    {
        var r = ConfigPorcelain.ParseConfigPorcelain(
            Lines("candidate\t\tremote\t1", "remote-candidate\t\t1"));
        Assert.Single(r.Candidates);
        Assert.Equal("", r.Candidates[0].Name);
        Assert.Empty(r.Remotes);
    }

    /// <summary>011: the new ids parse, and the picker order places them.</summary>
    [Fact]
    public void Draft_offers_parse_and_order()
    {
        var text = Lines(
            "config\tremote\torigin",
            "offer\tdraft\tavailable",
            "offer\tstep\tavailable",
            "offer\twhole\tavailable");
        var r = ConfigPorcelain.ParseConfigPorcelain(text);
        Assert.Equal(
            new[] { OfferId.Draft, OfferId.Step, OfferId.Whole },
            r.Offers!.Select(o => o.Id));
        var items = LayoutOffers.BuildLayoutItems(r.Offers);
        Assert.Equal(
            new[] { "Build a reading order first", "Commit by commit", "Whole diff" },
            items.Select(i => i.Label));
        Assert.Equal(LayoutOffers.DraftStep.Create, items[0].Draft);
        Assert.Equal(ReviewLayout.Walk, items[0].Layout);
        Assert.Null(items[1].Draft);
    }

    [Fact]
    public void Draft_resume_sits_behind_a_recommended_walk()
    {
        var text = Lines(
            "config\tremote\torigin",
            "offer\twalk\trecommended",
            "offer\tdraft-resume\tavailable",
            "offer\tstep\tavailable");
        var items = LayoutOffers.BuildLayoutItems(ConfigPorcelain.ParseConfigPorcelain(text).Offers);
        Assert.Equal(
            new[] { "Walkthrough (recommended)", "Finish the reading order you started", "Commit by commit" },
            items.Select(i => i.Label));
        Assert.Null(items[0].Draft);
        Assert.Equal(LayoutOffers.DraftStep.Resume, items[1].Draft);
        Assert.Equal("pick up the one you left half-written", items[1].Description);
    }

    /// <summary>
    /// "pick up the one you left half-written" describes a half-written order; over
    /// one that is finished and already used it is false, and what is left is not
    /// finishing it but reconciling it or starting a new one.
    /// </summary>
    [Fact]
    public void A_spent_draft_row_says_something_else()
    {
        var offers = new[] { new ReadingOffer(OfferId.DraftResume, OfferRank.Available) };
        var fresh = LayoutOffers.BuildLayoutItems(offers);
        var spent = LayoutOffers.BuildLayoutItems(offers, spentDraft: true);

        Assert.Equal("Finish the reading order you started", fresh[0].Label);
        Assert.Equal("Reuse the reading order you wrote", spent[0].Label);
        Assert.NotEqual(fresh[0].Description, spent[0].Description);
        // The rest of the row does not change.
        Assert.Equal(LayoutOffers.DraftStep.Resume, spent[0].Draft);
        Assert.Equal(ReviewLayout.Walk, spent[0].Layout);
    }

    [Fact]
    public void The_draft_state_touches_no_other_row()
    {
        var offers = new[]
        {
            new ReadingOffer(OfferId.Walk, OfferRank.Recommended),
            new ReadingOffer(OfferId.Step, OfferRank.Available),
            new ReadingOffer(OfferId.Whole, OfferRank.Available),
        };
        Assert.Equal(
            LayoutOffers.BuildLayoutItems(offers).Select(i => i.Label),
            LayoutOffers.BuildLayoutItems(offers, spentDraft: true).Select(i => i.Label));
    }

    /// <summary>
    /// Recommended offers come first whatever order the CLI printed them in, and the
    /// rest keep the canonical order — not the order of arrival.
    /// </summary>
    [Fact]
    public void Recommended_offers_sort_ahead_of_available_ones()
    {
        var text = Lines(
            "config\tremote\torigin",
            "offer\twhole\tavailable",
            "offer\tstep\tavailable",
            "offer\tkeys\trecommended");
        var items = LayoutOffers.BuildLayoutItems(ConfigPorcelain.ParseConfigPorcelain(text).Offers);
        Assert.Equal(
            new[] { ReviewLayout.Keys, ReviewLayout.Step, ReviewLayout.Whole },
            items.Select(i => i.Layout));
        Assert.StartsWith("Walkthrough — keys only", items[0].Label);
        Assert.EndsWith("(recommended)", items[0].Label);
    }

    [Fact]
    public void Unknown_offer_ids_are_dropped()
    {
        var text = Lines(
            "config\tremote\torigin",
            "offer\tdrafts\tavailable",
            "offer\tdraft_resume\tavailable",
            "offer\tdraft\tavailable");
        Assert.Equal(
            new[] { OfferId.Draft },
            ConfigPorcelain.ParseConfigPorcelain(text).Offers!.Select(o => o.Id));
    }

    /// <summary>
    /// No offers at all is not "no way to read this branch": the CLI predates the
    /// record, so the client falls back to the two forms that always work.
    /// </summary>
    [Fact]
    public void No_offers_falls_back_to_step_and_whole()
    {
        foreach (var offers in new IReadOnlyList<ReadingOffer>?[] { null, Array.Empty<ReadingOffer>() })
        {
            var items = LayoutOffers.BuildLayoutItems(offers);
            Assert.Equal(2, items.Count);
            Assert.Equal(ReviewLayout.Step, items[0].Layout);
            Assert.Equal(ReviewLayout.Whole, items[1].Layout);
            Assert.All(items, i => Assert.Null(i.Draft));
            Assert.DoesNotContain("(recommended)", items[0].Label);
        }
    }

    [Fact]
    public void Branch_picker_collapses_origins_and_puts_current_first()
    {
        var candidates = new[]
        {
            new CandidateBranch("main", "remote", false),
            new CandidateBranch("feature/checkout", "remote", false),
            new CandidateBranch("feature/checkout", "local", true),
            new CandidateBranch("develop", "local", false),
        };
        var items = ConfigPorcelain.BranchPickerItems(candidates);
        Assert.Equal(new[] { "feature/checkout", "develop", "main" }, items.Select(i => i.Name));
        Assert.True(items[0].Current);
        Assert.Equal(
            new[] { "feature/checkout  (current)", "develop", "main" },
            items.Select(ConfigPorcelain.BranchPickerLabel));
    }

    /// <summary>
    /// The collapse keeps whichever copy is the current branch, whichever side it
    /// arrived on — otherwise the "(current)" marker lands on the wrong row.
    /// </summary>
    [Fact]
    public void Collapse_prefers_the_current_copy_in_either_order()
    {
        var localFirst = ConfigPorcelain.BranchPickerItems(new[]
        {
            new CandidateBranch("f", "local", true),
            new CandidateBranch("f", "remote", false),
        });
        Assert.Single(localFirst);
        Assert.True(localFirst[0].Current);
        Assert.Equal("local", localFirst[0].Origin);

        var remoteFirst = ConfigPorcelain.BranchPickerItems(new[]
        {
            new CandidateBranch("f", "remote", false),
            new CandidateBranch("f", "local", true),
        });
        Assert.Single(remoteFirst);
        Assert.True(remoteFirst[0].Current);
    }

    [Fact]
    public void Branch_picker_is_empty_when_there_are_no_candidates()
    {
        Assert.Empty(ConfigPorcelain.BranchPickerItems(Array.Empty<CandidateBranch>()));
    }

    [Fact]
    public void Delta_for_source_matches_the_origin_the_start_will_use()
    {
        var deltas = new[]
        {
            new DeltaRecord("f", "localtip", DeltaOrigin.Local),
            new DeltaRecord("f", "remotetip", DeltaOrigin.Remote),
        };
        Assert.Equal("remotetip", ConfigPorcelain.DeltaForSource(deltas, "remote")?.Tip);
        Assert.Equal("localtip", ConfigPorcelain.DeltaForSource(deltas, "local")?.Tip);
        // Offline reviews resolve locally, so they read the local marker.
        Assert.Equal("localtip", ConfigPorcelain.DeltaForSource(deltas, "offline")?.Tip);
        Assert.Null(ConfigPorcelain.DeltaForSource(null, "remote"));
        Assert.Null(ConfigPorcelain.DeltaForSource(Array.Empty<DeltaRecord>(), "remote"));
    }

    [Fact]
    public void Offer_and_delta_ids_round_trip()
    {
        foreach (var id in Enum.GetValues<OfferId>())
            Assert.Equal(id, OfferIdExt.Parse(id.Id()));
        foreach (var rank in Enum.GetValues<OfferRank>())
            Assert.Equal(rank, OfferRankExt.Parse(rank.Id()));
        foreach (var origin in Enum.GetValues<DeltaOrigin>())
            Assert.Equal(origin, DeltaOriginExt.Parse(origin.Id()));
        Assert.Equal("draft-resume", OfferId.DraftResume.Id());
        Assert.Null(OfferIdExt.Parse("nope"));
    }

    [Fact]
    public void Layout_summary_reads_in_the_confirmation_sentence()
    {
        Assert.Equal("as a walkthrough", LayoutOffers.LayoutSummary(ReviewLayout.Walk));
        Assert.Equal("keys only", LayoutOffers.LayoutSummary(ReviewLayout.Keys));
        Assert.Equal("commit by commit", LayoutOffers.LayoutSummary(ReviewLayout.Step));
        Assert.Equal("as the whole diff", LayoutOffers.LayoutSummary(ReviewLayout.Whole));
    }

    [Fact]
    public void Offer_config_flags_mirror_the_start_flags()
    {
        Assert.Empty(LayoutOffers.OfferConfigFlags(ReviewSource.Remote, ReviewRange.Full));
        Assert.Equal(new[] { "--local" }, LayoutOffers.OfferConfigFlags(ReviewSource.Local, ReviewRange.Full));
        Assert.Equal(new[] { "--offline" }, LayoutOffers.OfferConfigFlags(ReviewSource.Offline, ReviewRange.Full));
        Assert.Equal(new[] { "--delta" }, LayoutOffers.OfferConfigFlags(ReviewSource.Remote, ReviewRange.Delta));
        Assert.Equal(
            new[] { "--local", "--delta" },
            LayoutOffers.OfferConfigFlags(ReviewSource.Local, ReviewRange.Delta));
    }

    [Fact]
    public void Draft_records_parse_their_seven_fields()
    {
        var stdout =
            "config\tremote\torigin\n" +
            "draft\tfeature/checkout\t/repo/.git/review-walkthrough/feature/checkout.md\t3\t9\tlocal\tdelta\n";
        var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(stdout).Drafts!);
        Assert.Equal("feature/checkout", draft.Src);
        Assert.Equal("/repo/.git/review-walkthrough/feature/checkout.md", draft.Path);
        Assert.Equal(3, draft.Annotated);
        Assert.Equal(9, draft.Total);
        Assert.Equal(DraftSource.Local, draft.Source);
        Assert.Equal(DraftRange.Delta, draft.Range);
    }

    [Fact]
    public void An_unknown_source_or_range_reads_as_unknown()
    {
        // What the CLI emits when the instruction block was deleted by hand, and
        // the only honest reading of a value a newer CLI might add: in both cases
        // this client cannot replicate the flags.
        var stdout = "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tunknown\tunknown\n";
        var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(stdout).Drafts!);
        Assert.Equal(DraftSource.Unknown, draft.Source);
        Assert.Equal(DraftRange.Unknown, draft.Range);
    }

    [Fact]
    public void A_malformed_draft_record_is_ignored_whole()
    {
        // Half a progress pair would be worse than none: a total that is not an
        // integer cannot be drawn as "3/N" without inventing the N.
        var stdout =
            "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\tmany\t2\tremote\tfull\n" +
            "draft\t\t/repo/.git/review-walkthrough/feature/y.md\t0\t2\tremote\tfull\n" +
            "draft\tfeature/z\n" +
            "draft\tfeature/ok\t/repo/.git/review-walkthrough/feature/ok.md\t1\t2\tremote\tfull\n";
        var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(stdout).Drafts!);
        Assert.Equal("feature/ok", draft.Src);
    }

    [Theory]
    [InlineData("-3")]
    [InlineData("+3")]
    [InlineData(" 3")]
    [InlineData("3 ")]
    [InlineData("3.0")]
    [InlineData("")]
    [InlineData("0x2")]
    public void A_progress_that_is_not_a_non_negative_integer_invalidates_the_record(string bad)
    {
        // The rule has to be the same in all three clients: the CLI counts with awk
        // and only ever emits digits, so a sign or a space is a record this client
        // did not understand. int.TryParse on its own accepted "-3", "+3" and " 3 ",
        // so the same porcelain line drew a row here and was dropped by VS Code.
        const string path = "/repo/.git/review-walkthrough/feature/x.md";
        Assert.Empty(
            ConfigPorcelain.ParseConfigPorcelain($"draft\tfeature/x\t{path}\t{bad}\t9\tremote\tfull\n")
                .Drafts!);
        Assert.Empty(
            ConfigPorcelain.ParseConfigPorcelain($"draft\tfeature/x\t{path}\t0\t{bad}\tremote\tfull\n")
                .Drafts!);
    }
}
