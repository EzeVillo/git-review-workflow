using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// US4 (012): what is left of the draft path inside the wizard, and its parity
/// with the other two clients (<c>vscode-extension/test/unit/draftFlow.spec.ts</c>,
/// jetbrains <c>DraftFlowTest</c>). The cases are deliberately the same ones: if
/// one of the three drifts, it shows up here.
/// </summary>
public class DraftFlowTests
{
    [Fact]
    public void Initial_state_skips_creation_when_resuming()
    {
        Assert.IsType<DraftFlowState.Create>(DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create));
        // Resume recreates nothing: the file exists and recreating it would
        // overwrite what the reviewer wrote, which is what --force is there to
        // ask for by hand. With nothing to create, the wizard is done.
        Assert.IsType<DraftFlowState.Done>(DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume));
    }

    [Fact]
    public void Creating_green_ends_the_wizard()
    {
        var s = DraftFlow.AdvanceDraftFlow(
            DraftFlowState.Create.Instance,
            new DraftFlowEvent.Created(true));
        Assert.IsType<DraftFlowState.Done>(s);
    }

    /// <summary>
    /// The 011 loop (Open / Wait / Build / Reload / PickKeys) was removed whole:
    /// what it did lives in the panel now, over a state that outlives the IDE.
    /// If any of it came back, this is what says so.
    /// </summary>
    [Fact]
    public void The_machine_has_three_states_and_none_waits()
    {
        var kinds = new[]
        {
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create),
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume),
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Create.Instance, new DraftFlowEvent.Created(true)),
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Create.Instance, new DraftFlowEvent.Created(false)),
        }.Select(s => s.GetType().Name).Distinct().OrderBy(n => n, StringComparer.Ordinal).ToArray();
        Assert.Equal(new[] { "Back", "Create", "Done" }, kinds);
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
    public void A_failure_without_stderr_goes_back_without_inventing_a_reason()
    {
        Assert.Equal(
            new DraftFlowState.Back(),
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Create.Instance, new DraftFlowEvent.Created(false)));
    }

    [Fact]
    public void Done_and_back_are_terminal()
    {
        var done = DraftFlowState.Done.Instance;
        Assert.Equal(done, DraftFlow.AdvanceDraftFlow(done, new DraftFlowEvent.Created(true)));
        var back = new DraftFlowState.Back("boom");
        Assert.Equal(back, DraftFlow.AdvanceDraftFlow(back, new DraftFlowEvent.Created(true)));
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
}
