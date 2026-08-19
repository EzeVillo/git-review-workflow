using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// US3 (011): the draft loop's state machine, and its parity with the other two
/// clients (<c>vscode-extension/test/unit/draftFlow.spec.ts</c>, jetbrains
/// <c>DraftFlowTest</c>). The cases are deliberately the same ones: if one of the
/// three drifts, it shows up here.
/// </summary>
public class DraftFlowTests
{
    private static DraftFlowState Run(DraftFlowState start, params DraftFlowEvent[] events) =>
        events.Aggregate(start, DraftFlow.AdvanceDraftFlow);

    [Fact]
    public void Initial_state_skips_creation_when_resuming()
    {
        Assert.IsType<DraftFlowState.Create>(DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create));
        Assert.IsType<DraftFlowState.Open>(DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume));
    }

    [Fact]
    public void Happy_path_without_keys_ends_in_walk()
    {
        var end = Run(
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create),
            new DraftFlowEvent.Created(true),
            DraftFlowEvent.Opened.Instance,
            DraftFlowEvent.Continue.Instance,
            new DraftFlowEvent.Built(true),
            new DraftFlowEvent.Offers(new[]
            {
                new ReadingOffer(OfferId.Walk, OfferRank.Recommended),
                new ReadingOffer(OfferId.Step, OfferRank.Available),
            }));
        Assert.Equal(new DraftFlowState.Done(ReviewLayout.Walk), end);
    }

    [Fact]
    public void Every_step_of_the_create_path_is_the_next_one()
    {
        var s = DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create);
        s = DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Created(true));
        Assert.IsType<DraftFlowState.Open>(s);
        s = DraftFlow.AdvanceDraftFlow(s, DraftFlowEvent.Opened.Instance);
        Assert.IsType<DraftFlowState.Wait>(s);
        s = DraftFlow.AdvanceDraftFlow(s, DraftFlowEvent.Continue.Instance);
        Assert.IsType<DraftFlowState.Build>(s);
        s = DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Built(true));
        Assert.IsType<DraftFlowState.Reload>(s);
    }

    [Fact]
    public void Keys_offer_asks_before_deciding()
    {
        var asked = Run(
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume),
            DraftFlowEvent.Opened.Instance,
            DraftFlowEvent.Continue.Instance,
            new DraftFlowEvent.Built(true),
            new DraftFlowEvent.Offers(new[]
            {
                new ReadingOffer(OfferId.Walk, OfferRank.Recommended),
                new ReadingOffer(OfferId.Keys, OfferRank.Available),
            }));
        Assert.IsType<DraftFlowState.PickKeys>(asked);
        Assert.Equal(
            new DraftFlowState.Done(ReviewLayout.Keys),
            DraftFlow.AdvanceDraftFlow(asked, new DraftFlowEvent.KeysPicked(true)));
        Assert.Equal(
            new DraftFlowState.Done(ReviewLayout.Walk),
            DraftFlow.AdvanceDraftFlow(asked, new DraftFlowEvent.KeysPicked(false)));
        // Closing the picker goes back, with no error and nothing deleted.
        Assert.Equal(
            new DraftFlowState.Back(),
            DraftFlow.AdvanceDraftFlow(asked, new DraftFlowEvent.KeysPicked(null)));
    }

    [Fact]
    public void Failed_build_retries_without_a_limit()
    {
        var state = Run(
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume),
            DraftFlowEvent.Opened.Instance,
            DraftFlowEvent.Continue.Instance,
            new DraftFlowEvent.Built(false, "entry 3 still has the placeholder why"));
        Assert.Equal(new DraftFlowState.Wait("entry 3 still has the placeholder why"), state);

        state = Run(state, DraftFlowEvent.Continue.Instance, new DraftFlowEvent.Built(false, "duplicate entry"));
        Assert.Equal(new DraftFlowState.Wait("duplicate entry"), state);

        state = Run(state, DraftFlowEvent.Continue.Instance, new DraftFlowEvent.Built(true));
        Assert.IsType<DraftFlowState.Reload>(state);
    }

    [Fact]
    public void Cancel_keeps_the_draft_and_reports_no_error()
    {
        var state = Run(
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume),
            DraftFlowEvent.Opened.Instance,
            DraftFlowEvent.Cancel.Instance);
        var back = Assert.IsType<DraftFlowState.Back>(state);
        Assert.Null(back.Error);
    }

    [Fact]
    public void Failed_creation_goes_back_with_the_reason()
    {
        var state = DraftFlow.AdvanceDraftFlow(
            DraftFlowState.Create.Instance,
            new DraftFlowEvent.Created(false, "a draft already exists; use --force"));
        Assert.Equal(new DraftFlowState.Back("a draft already exists; use --force"), state);
    }

    [Fact]
    public void Events_that_do_not_apply_leave_the_state_alone()
    {
        Assert.Equal(
            new DraftFlowState.Wait(),
            DraftFlow.AdvanceDraftFlow(new DraftFlowState.Wait(), new DraftFlowEvent.Built(true)));
        Assert.IsType<DraftFlowState.Create>(
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Create.Instance, DraftFlowEvent.Continue.Instance));
        Assert.IsType<DraftFlowState.Open>(
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Open.Instance, DraftFlowEvent.Cancel.Instance));
        Assert.IsType<DraftFlowState.Reload>(
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Reload.Instance, DraftFlowEvent.Continue.Instance));
    }

    [Fact]
    public void Done_and_back_are_terminal()
    {
        var done = new DraftFlowState.Done(ReviewLayout.Walk);
        Assert.Equal(done, DraftFlow.AdvanceDraftFlow(done, DraftFlowEvent.Cancel.Instance));
        var back = new DraftFlowState.Back("boom");
        Assert.Equal(back, DraftFlow.AdvanceDraftFlow(back, DraftFlowEvent.Continue.Instance));
    }

    /// <summary>No offers after a build means no keys to ask about, not a dead end.</summary>
    [Fact]
    public void Reload_without_offers_still_lands_on_walk()
    {
        Assert.Equal(
            new DraftFlowState.Done(ReviewLayout.Walk),
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Reload.Instance, new DraftFlowEvent.Offers(null)));
    }

    [Fact]
    public void Offers_include_keys_only_when_reported()
    {
        Assert.False(DraftFlow.OffersIncludeKeys(null));
        Assert.False(DraftFlow.OffersIncludeKeys(Array.Empty<ReadingOffer>()));
        Assert.False(DraftFlow.OffersIncludeKeys(new[] { new ReadingOffer(OfferId.Walk, OfferRank.Recommended) }));
        Assert.True(DraftFlow.OffersIncludeKeys(new[]
        {
            new ReadingOffer(OfferId.Walk, OfferRank.Recommended),
            new ReadingOffer(OfferId.Keys, OfferRank.Available),
        }));
    }

    [Fact]
    public void Gitdir_link_is_read_for_worktrees_and_submodules()
    {
        Assert.Equal("/repo/.git/worktrees/wt1", DraftFlow.GitdirFromLink("gitdir: /repo/.git/worktrees/wt1\n"));
        Assert.Equal("../.git/modules/sub", DraftFlow.GitdirFromLink("gitdir: ../.git/modules/sub"));
        Assert.Equal(
            "C:/repo/.git/worktrees/wt1",
            DraftFlow.GitdirFromLink("gitdir:   C:/repo/.git/worktrees/wt1  \r\n"));
        Assert.Null(DraftFlow.GitdirFromLink(""));
        Assert.Null(DraftFlow.GitdirFromLink("ref: refs/heads/main\n"));
        Assert.Null(DraftFlow.GitdirFromLink("gitdir:\n"));
    }
}
